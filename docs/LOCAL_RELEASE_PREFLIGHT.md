# Local Release Preflight

Run the complete release gate from the repository root:

```bash
scripts/release-preflight.sh
```

The preflight is intentionally independent of App Store Connect and AWS credentials. It does not deploy the backend, export or upload an IPA, change signing assets, or make network mutations.

It checks:

- the current branch is attached, clean, pushed, and synchronized with its upstream
- credential/signing files are ignored and tracked or pending source has no recognized literal access key, private key, or backend token
- the source Info.plist retains release build-setting placeholders rather than literal configuration
- the app and all three extensions share the expected version, build, team, bundle IDs, Family Controls entitlement, and App Group
- the shared scheme archives the Release configuration and the app declares its background tasks and export-compliance value
- all backend unit tests pass
- `sam validate --lint` and a clean `sam build` pass when the SAM CLI is installed
- all iOS simulator tests pass and a signing-disabled Release simulator build succeeds
- the required matching `../release/Checkpoint-<version>-<build>.xcarchive` has the correct metadata, an arm64 device build, valid local signatures, all three extensions, and a resolved backend configuration
- the archive contains valid HTTPS Privacy Policy, Support, and Terms of Use URLs for the in-app Help & legal section

Backend values are never printed. Command output is captured privately and discarded; failures identify the stage without echoing a potentially credential-bearing build log. Temporary SAM and Xcode build products are deleted when the preflight exits.

## Useful options

Inspect an explicitly selected archive:

```bash
scripts/release-preflight.sh --archive ../release/Checkpoint-1.0-2.xcarchive
```

During development, allow the source tree to be dirty while retaining every other check:

```bash
scripts/release-preflight.sh --allow-dirty
```

For a fast configuration-only iteration (skipping both iOS tests and the
Release simulator build):

```bash
scripts/release-preflight.sh --allow-dirty --skip-backend --skip-ios-build --no-archive
```

The skip flags are for development feedback only. The default command fails
when its version-matched archive is missing; `--no-archive` is the explicit
development-only bypass. A release candidate should pass the default command
from a clean, pushed commit. App Store export/upload remains a separate final
step because it requires an Apple account associated with the correct App
Store Connect provider.

CI uses `--skip-git` because pull-request checkouts are detached and combines
it with the development-only skip flags after running backend and iOS jobs
separately. A human release must not use `--skip-git`.

A passing archive inspection validates local structure, metadata, and signatures; it does not establish credential provenance or make an archive eligible for upload when a separate release incident requires it to be rebuilt.
