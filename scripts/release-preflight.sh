#!/usr/bin/env python3
"""Local, credential-safe release gate for Checkpoint."""

import argparse
import ipaddress
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend" / "bedrock-question-service"
PROJECT = ROOT / "Checkpoint.xcodeproj"
SCHEME = "Checkpoint"
TARGETS = (
    ("Checkpoint", "com.samchou.checkpoint", "Checkpoint/Checkpoint.entitlements"),
    (
        "ShieldConfigurationExtension",
        "com.samchou.checkpoint.ShieldConfigurationExtension",
        "ShieldConfigurationExtension/ShieldConfigurationExtension.entitlements",
    ),
    (
        "ShieldActionExtension",
        "com.samchou.checkpoint.ShieldActionExtension",
        "ShieldActionExtension/ShieldActionExtension.entitlements",
    ),
    (
        "DeviceActivityMonitorExtension",
        "com.samchou.checkpoint.DeviceActivityMonitorExtension",
        "DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.entitlements",
    ),
)
EXTENSIONS = {name: bundle for name, bundle, _ in TARGETS[1:]}


def load_plist(path):
    with path.open("rb") as handle:
        return plistlib.load(handle)


def is_public_https_url(value):
    if not isinstance(value, str) or not value.strip() or "$(" in value:
        return False
    try:
        parsed = urlparse(value.strip())
        hostname = parsed.hostname
    except ValueError:
        return False
    if not hostname or not is_public_host(hostname):
        return False
    return (
        parsed.scheme.lower() == "https"
        and parsed.username is None
        and parsed.password is None
    )


def is_public_host(hostname):
    normalized = hostname.lower().strip(".")
    blocked_names = {"localhost", "example.com", "example.net", "example.org"}
    blocked_suffixes = (
        ".example.com", ".example.net", ".example.org", ".example",
        ".invalid", ".local", ".localhost",
        ".test", ".internal", ".lan",
    )
    if "." not in normalized or normalized in blocked_names:
        return False
    if any(normalized.endswith(suffix) for suffix in blocked_suffixes):
        return False
    try:
        return ipaddress.ip_address(normalized).is_global
    except ValueError:
        return True


class Preflight:
    def __init__(self, args):
        self.args = args
        self.failures = 0
        self.warnings = 0
        self.release = {}
        self.temp = Path(tempfile.mkdtemp(prefix="checkpoint-preflight-"))

    def close(self):
        shutil.rmtree(str(self.temp), ignore_errors=True)

    def passed(self, message):
        print("[PASS] " + message)

    def warn(self, message):
        self.warnings += 1
        print("[WARN] " + message)

    def fail(self, message):
        self.failures += 1
        print("[FAIL] " + message, file=sys.stderr)

    def run(self, label, command, cwd=ROOT, env=None):
        print("[RUN ] " + label)
        command_env = os.environ.copy()
        if env:
            command_env.update(env)
        try:
            result = subprocess.run(
                [str(part) for part in command],
                cwd=str(cwd),
                env=command_env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                errors="replace",
                check=False,
            )
        except OSError:
            self.fail(label + " (command could not start)")
            return None
        if result.returncode:
            self.fail(label + " (output suppressed to protect release credentials)")
        else:
            self.passed(label)
        return result

    def git(self, *arguments):
        return subprocess.run(
            ["git", "-C", str(ROOT)] + list(arguments),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )

    def check_git(self):
        print("\nGit source")
        branch = self.git("symbolic-ref", "--quiet", "--short", "HEAD").stdout.strip()
        commit = self.git("rev-parse", "--short=12", "HEAD").stdout.strip()
        if branch:
            self.passed("branch: " + branch)
        else:
            self.fail("HEAD is detached")
        if commit:
            self.passed("commit: " + commit)
        else:
            self.fail("HEAD commit could not be resolved")

        dirty = bool(self.git("status", "--porcelain", "--untracked-files=all").stdout)
        if dirty and self.args.allow_dirty:
            self.warn("working tree has uncommitted changes (--allow-dirty)")
        elif dirty:
            self.fail("working tree has uncommitted changes")
        else:
            self.passed("working tree is clean")

        upstream = self.git(
            "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"
        ).stdout.strip()
        if not upstream:
            self.fail("current branch has no upstream")
            return
        counts = self.git("rev-list", "--left-right", "--count", "HEAD..." + upstream).stdout.split()
        if counts == ["0", "0"]:
            self.passed("HEAD matches its upstream")
        else:
            self.fail("HEAD differs from its upstream")

    def check_credentials(self):
        print("\nCredential hygiene")
        tracked = [Path(item) for item in self.git("ls-files").stdout.splitlines()]
        pending = [
            Path(item)
            for item in self.git("ls-files", "--others", "--exclude-standard").stdout.splitlines()
        ]
        source_paths = sorted(set(tracked + pending))
        sensitive_suffixes = {".p8", ".p12", ".mobileprovision", ".provisionprofile"}
        sensitive_names = [
            path
            for path in source_paths
            if path.name in {"Secrets.xcconfig", ".env"} or path.suffix in sensitive_suffixes
        ]
        if sensitive_names:
            self.fail("credential-shaped files are tracked")
        else:
            self.passed("local credential and signing-file patterns are untracked")

        ignored = all(
            self.git("check-ignore", "-q", candidate).returncode == 0
            for candidate in (
                "Checkpoint/Config/Secrets.xcconfig",
                "release-key.p8",
                "release-profile.mobileprovision",
            )
        )
        if ignored:
            self.passed("local backend and Apple signing material is ignored")
        else:
            self.fail("expected credential paths are not covered by .gitignore")

        credential_pattern = re.compile(
            r"A[K]IA[0-9A-Z]{16}|A[S]IA[0-9A-Z]{16}|"
            r"gh[pousr]_[A-Za-z0-9]{30,}|"
            r"sk-(?:proj-)?[A-Za-z0-9_-]{24,}|"
            r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|"
            r"-----BEGIN (?:[A-Z]+ )?PRIVATE K[E]Y-----"
        )
        literal_assignment = re.compile(
            r"(?i)\b(?:api[_-]?key|access[_-]?token|authorization|backend[_-]?token|"
            r"client[_-]?secret|password|secret(?:[_-]?key)?|token)\b\s*[:=]\s*"
            r"[\"']([A-Za-z0-9+/_=.-]{24,})[\"']"
        )
        obvious_fixture_markers = {
            "different", "dummy", "example", "fake", "placeholder", "replace", "sample", "test"
        }
        suspicious_path = None
        for relative in source_paths:
            if relative.as_posix() == "scripts/release-preflight.sh":
                continue
            path = ROOT / relative
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeError):
                continue
            literal_matches = literal_assignment.finditer(text)
            has_literal_secret = any(
                not any(marker in match.group(1).lower() for marker in obvious_fixture_markers)
                for match in literal_matches
            )
            if credential_pattern.search(text) or has_literal_secret:
                suspicious_path = relative
                break
            if path.suffix == ".xcconfig":
                for line in text.splitlines():
                    match = re.match(
                        r"\s*(CHECKPOINT_AI_BACKEND_TOKEN|AWS_SECRET_ACCESS_KEY)\s*=\s*(.*)", line
                    )
                    if match and match.group(2) and not match.group(2).startswith(("$(", "replace-", "<")):
                        suspicious_path = relative
                        break
        if suspicious_path:
            self.fail(
                "tracked or pending source contains credential-shaped content in {} "
                "(value suppressed)".format(suspicious_path)
            )
        else:
            self.passed(
                "tracked and pending source contains no recognized access key, private key, or literal token"
            )

        config = (ROOT / "Checkpoint/Config/Backend.xcconfig").read_text(encoding="utf-8")
        expected_lines = (
            "CHECKPOINT_AI_BACKEND_ENDPOINT = $(CHECKPOINT_AI_BACKEND_ENDPOINT_OVERRIDE)",
            "CHECKPOINT_AI_BACKEND_TOKEN = $(CHECKPOINT_AI_BACKEND_TOKEN_OVERRIDE)",
            '#include? "Secrets.xcconfig"',
        )
        if all(line in config for line in expected_lines):
            self.passed("backend settings use overrides or the ignored local include")
        else:
            self.fail("backend release settings are not using the expected indirection")

        info = load_plist(ROOT / "Checkpoint/Info.plist")
        if (
            info.get("CheckpointAIBackendEndpoint") == "$(CHECKPOINT_AI_BACKEND_ENDPOINT)"
            and info.get("CheckpointAIBackendToken") == "$(CHECKPOINT_AI_BACKEND_TOKEN)"
            and info.get("CheckpointPrivacyPolicyURL") == "$(CHECKPOINT_PRIVACY_POLICY_URL)"
            and info.get("CheckpointSupportURL") == "$(CHECKPOINT_SUPPORT_URL)"
            and info.get("CheckpointTermsOfUseURL") == "$(CHECKPOINT_TERMS_OF_USE_URL)"
        ):
            self.passed("source Info.plist contains only release build-setting placeholders")
        else:
            self.fail("source Info.plist contains a literal or unexpected release value")

    def check_ios_configuration(self):
        print("\niOS configuration")
        if not shutil.which("xcodebuild"):
            self.fail("xcodebuild is unavailable")
            return
        try:
            archive_action = ET.parse(
                PROJECT / "xcshareddata/xcschemes/Checkpoint.xcscheme"
            ).getroot().find("ArchiveAction")
            scheme_ok = archive_action is not None and archive_action.get("buildConfiguration") == "Release"
        except (OSError, ET.ParseError):
            scheme_ok = False
        if scheme_ok:
            self.passed("shared scheme archives the Release configuration")
        else:
            self.fail("shared scheme is missing a Release archive action")

        info = load_plist(ROOT / "Checkpoint/Info.plist")
        if info.get("ITSAppUsesNonExemptEncryption") is False:
            self.passed("export-compliance encryption declaration is present")
        else:
            self.fail("ITSAppUsesNonExemptEncryption must be false")
        expected_tasks = {
            "com.samchou.checkpoint.question-refresh",
            "com.samchou.checkpoint.question-processing",
        }
        if expected_tasks.issubset(set(info.get("BGTaskSchedulerPermittedIdentifiers", []))):
            self.passed("question-maintenance background tasks are declared")
        else:
            self.fail("question-maintenance background task identifiers are incomplete")

        base = None
        for name, expected_bundle, entitlements_path in TARGETS:
            result = self.run(
                name + " Release build settings",
                [
                    "xcodebuild", "-project", PROJECT, "-target", name,
                    "-configuration", "Release", "-showBuildSettings",
                ],
            )
            if not result or result.returncode:
                continue
            settings = {}
            for line in result.stdout.splitlines():
                key, separator, value = line.strip().partition(" = ")
                if separator:
                    settings[key] = value
            identity = {
                "version": settings.get("MARKETING_VERSION"),
                "build": settings.get("CURRENT_PROJECT_VERSION"),
                "team": settings.get("DEVELOPMENT_TEAM"),
            }
            if base is None:
                base = identity
                self.release = identity
            valid = (
                identity == base
                and all(identity.values())
                and settings.get("PRODUCT_BUNDLE_IDENTIFIER") == expected_bundle
                and settings.get("CODE_SIGN_ENTITLEMENTS") == entitlements_path
            )
            entitlements = load_plist(ROOT / entitlements_path)
            valid = valid and entitlements.get("com.apple.developer.family-controls") is True
            valid = valid and entitlements.get("com.apple.security.application-groups") == [
                "group.com.samchou.checkpoint"
            ]
            if valid:
                self.passed("{}: {} ({}) identity and entitlements".format(
                    name, identity["version"], identity["build"]
                ))
            else:
                self.fail(name + " Release identity/configuration is inconsistent")

    def check_backend(self):
        print("\nBackend")
        candidates = [
            os.environ.get("CHECKPOINT_PYTHON"),
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/opt/homebrew/bin/python3.12",
            shutil.which("python3"),
        ]
        python = next((item for item in candidates if item and Path(item).is_file()), None)
        if not python:
            self.fail("a Python interpreter for backend tests is unavailable")
        else:
            result = self.run(
                "backend unit tests",
                [python, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"],
                BACKEND,
            )
            match = re.search(r"Ran (\d+) tests", result.stdout if result else "")
            if result and not result.returncode and match:
                self.passed("backend suite executed " + match.group(1) + " tests")

        sam = shutil.which("sam")
        if not sam:
            self.warn("SAM CLI is unavailable; template validation/build skipped")
            return
        sam_env = {"SAM_CLI_TELEMETRY": "0", "AWS_EC2_METADATA_DISABLED": "true"}
        self.run(
            "SAM template validation with lint",
            [sam, "validate", "--lint", "--template-file", "template.yaml"],
            BACKEND,
            sam_env,
        )
        self.run(
            "SAM clean build",
            [sam, "build", "--template-file", "template.yaml", "--build-dir", self.temp / "sam-build"],
            BACKEND,
            sam_env,
        )

    def check_ios_build(self):
        print("\niOS tests and Release build")
        simulator_result = self.run(
            "available iPhone simulator discovery",
            ["xcrun", "simctl", "list", "devices", "available", "--json"],
        )
        simulator_id = None
        if simulator_result and not simulator_result.returncode:
            try:
                devices = json.loads(simulator_result.stdout)["devices"]
                simulator_id = next(
                    device["udid"]
                    for runtime_devices in devices.values()
                    for device in runtime_devices
                    if device.get("name", "").startswith("iPhone")
                )
            except (KeyError, StopIteration, TypeError, ValueError):
                pass
        if simulator_id:
            self.run(
                "iOS simulator tests",
                [
                    "xcodebuild", "-project", PROJECT, "-scheme", SCHEME,
                    "-configuration", "Debug", "-destination",
                    "platform=iOS Simulator,id=" + simulator_id,
                    "-derivedDataPath", self.temp / "DerivedData",
                    "test",
                ],
            )
        else:
            self.fail("no available iPhone simulator was found for tests")
        self.run(
            "Release simulator build with signing disabled",
            [
                "xcodebuild", "-project", PROJECT, "-scheme", SCHEME,
                "-configuration", "Release", "-destination", "generic/platform=iOS Simulator",
                "-derivedDataPath", self.temp / "DerivedData", "CODE_SIGNING_ALLOWED=NO", "build",
            ],
        )

    def check_archive(self, archive):
        print("\nArchive metadata")
        if not archive.is_dir():
            self.fail("archive does not exist: " + str(archive))
            return
        try:
            archive_info = load_plist(archive / "Info.plist")
            properties = archive_info["ApplicationProperties"]
            app = archive / "Products" / properties["ApplicationPath"]
            app_info = load_plist(app / "Info.plist")
        except (OSError, KeyError, plistlib.InvalidFileException):
            self.fail("archive application metadata is incomplete")
            return

        matches = (
            app_info.get("CFBundleIdentifier") == TARGETS[0][1]
            and app_info.get("CFBundleShortVersionString") == self.release.get("version")
            and app_info.get("CFBundleVersion") == self.release.get("build")
            and properties.get("Team") == self.release.get("team")
        )
        if matches:
            self.passed("archive matches the configured bundle, version, build, and team")
        else:
            self.fail("archive metadata does not match the Release configuration")
        if app_info.get("ITSAppUsesNonExemptEncryption") is False:
            self.passed("archive contains the export-compliance declaration")
        else:
            self.fail("archive export-compliance declaration is missing")

        legal_resources = (
            ("Privacy Policy", "CheckpointPrivacyPolicyURL"),
            ("Support", "CheckpointSupportURL"),
            ("Terms of Use", "CheckpointTermsOfUseURL"),
        )
        for label, key in legal_resources:
            if is_public_https_url(app_info.get(key)):
                self.passed("archive contains a configured HTTPS {} URL".format(label))
            else:
                self.fail("archive is missing a valid HTTPS {} URL".format(label))

        endpoint = app_info.get("CheckpointAIBackendEndpoint", "")
        token = app_info.get("CheckpointAIBackendToken", "")
        if not endpoint and not token:
            self.warn("archive has no backend configuration; generation will use on-device fallbacks")
        elif not endpoint or not token:
            self.fail("archive has only half of the backend endpoint/token pair")
        elif "$(" in endpoint or "$(" in token or not endpoint.startswith("https://") or len(token) < 32:
            self.fail("archive backend configuration is unresolved or malformed (values redacted)")
        else:
            self.passed("archive backend endpoint/token pair is resolved (values redacted)")
        del endpoint, token

        plugin_dir = app / "PlugIns"
        embedded = sorted(plugin_dir.glob("*.appex")) if plugin_dir.is_dir() else []
        valid_extensions = len(embedded) == len(EXTENSIONS)
        for name, bundle in EXTENSIONS.items():
            try:
                extension_info = load_plist(plugin_dir / (name + ".appex") / "Info.plist")
            except (OSError, plistlib.InvalidFileException):
                valid_extensions = False
                continue
            valid_extensions = valid_extensions and (
                extension_info.get("CFBundleIdentifier") == bundle
                and extension_info.get("CFBundleShortVersionString") == self.release.get("version")
                and extension_info.get("CFBundleVersion") == self.release.get("build")
            )
        if valid_extensions:
            self.passed("archive embeds all three version-matched Screen Time extensions")
        else:
            self.fail("archive Screen Time extension metadata is incomplete")
        if "arm64" in properties.get("Architectures", []):
            self.passed("archive contains an arm64 device build")
        else:
            self.fail("archive does not contain an arm64 device build")

        self.run("archive signature verification", ["codesign", "--verify", "--deep", "--strict", app])
        signing_identity = properties.get("SigningIdentity", "")
        if "Distribution" in signing_identity:
            self.passed("archive uses a distribution signing identity")
        elif "Development" in signing_identity:
            self.warn("archive is development-signed; App Store export must re-sign it")
        else:
            self.warn("archive signing identity could not be classified")


def arguments():
    parser = argparse.ArgumentParser(
        description="Run Checkpoint's local release checks without App Store Connect."
    )
    parser.add_argument("--archive", type=Path, help="Inspect this .xcarchive.")
    parser.add_argument("--no-archive", action="store_true", help="Skip archive inspection.")
    parser.add_argument("--allow-dirty", action="store_true", help="Do not fail on local changes.")
    parser.add_argument("--skip-git", action="store_true", help="Skip branch/upstream checks in CI.")
    parser.add_argument("--skip-backend", action="store_true", help="Skip backend tests/SAM checks.")
    parser.add_argument("--skip-ios-build", action="store_true", help="Skip the Release simulator build.")
    return parser.parse_args()


def main():
    args = arguments()
    preflight = Preflight(args)
    try:
        print("Checkpoint local release preflight")
        print("No deployment, export, upload, or credential values will be emitted.")
        if args.skip_git:
            print("\nGit source")
            preflight.warn("branch, cleanliness, and upstream checks skipped by request")
        else:
            preflight.check_git()
        preflight.check_credentials()
        preflight.check_ios_configuration()
        if args.skip_backend:
            print("\nBackend")
            preflight.warn("backend checks skipped by request")
        else:
            preflight.check_backend()
        if args.skip_ios_build:
            print("\niOS tests and Release build")
            preflight.warn("iOS simulator tests and Release build skipped by request")
        else:
            preflight.check_ios_build()

        if args.no_archive:
            print("\nArchive metadata")
            preflight.warn("archive inspection skipped by request")
        elif args.archive:
            archive = args.archive if args.archive.is_absolute() else ROOT / args.archive
            preflight.check_archive(archive)
        elif preflight.release.get("version") and preflight.release.get("build"):
            archive = ROOT.parent / "release" / "Checkpoint-{}-{}.xcarchive".format(
                preflight.release["version"], preflight.release["build"]
            )
            if archive.is_dir():
                preflight.check_archive(archive)
            else:
                print("\nArchive metadata")
                preflight.fail(
                    "no version-matched archive found; create it or use --no-archive only for development"
                )

        print("\nSummary: {} failure(s), {} warning(s)".format(
            preflight.failures, preflight.warnings
        ))
        if preflight.failures:
            return 1
        print("Local release preflight passed. App Store upload remains a separate credentialed step.")
        return 0
    finally:
        preflight.close()


if __name__ == "__main__":
    sys.exit(main())
