#!/bin/bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/generate_release_manifest.sh ARCHIVE OUTPUT_DIR SOURCE_COMMIT [IPA]

Creates a write-once Markdown manifest plus SHA-256 inventories for an
xcarchive and, when supplied, its exported IPA. OUTPUT_DIR may exist, but the
script refuses to replace a manifest for the same version and build.

The source commit is explicit because an xcarchive does not contain a reliable
Git commit identifier. Use the commit that produced the archive.
EOF
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
    usage >&2
    exit 64
fi

archive=${1%/}
output_dir=${2%/}
source_commit=$3
ipa=${4:-}
plist_buddy=/usr/libexec/PlistBuddy
script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_root=$(git -C "$script_dir/.." rev-parse --show-toplevel)

if [[ ! -d "$archive" || ! -f "$archive/Info.plist" ]]; then
    echo "Archive not found or invalid: $archive" >&2
    exit 66
fi

if [[ ! "$source_commit" =~ ^[0-9a-fA-F]{40}$ ]]; then
    echo "SOURCE_COMMIT must be a full 40-character Git commit." >&2
    exit 64
fi

if ! source_commit=$(
    git -C "$repo_root" rev-parse --verify "${source_commit}^{commit}" 2>/dev/null
); then
    echo "SOURCE_COMMIT does not identify a commit in this repository." >&2
    exit 65
fi

if [[ -n "$ipa" && ! -f "$ipa" ]]; then
    echo "IPA not found: $ipa" >&2
    exit 66
fi

application_path=$(
    "$plist_buddy" -c 'Print :ApplicationProperties:ApplicationPath' "$archive/Info.plist"
)
app="$archive/Products/$application_path"

if [[ ! -d "$app" || ! -f "$app/Info.plist" ]]; then
    echo "Archived application not found: $app" >&2
    exit 66
fi

read_app_key() {
    "$plist_buddy" -c "Print :$1" "$app/Info.plist"
}

read_archive_key() {
    "$plist_buddy" -c "Print :ApplicationProperties:$1" "$archive/Info.plist"
}

app_name=$(read_app_key CFBundleDisplayName)
bundle_id=$(read_app_key CFBundleIdentifier)
version=$(read_app_key CFBundleShortVersionString)
build=$(read_app_key CFBundleVersion)
minimum_os=$(read_app_key MinimumOSVersion)
sdk_name=$(read_app_key DTSDKName)
xcode_build=$(read_app_key DTXcodeBuild)
team_id=$(read_archive_key Team)
architectures=$(read_archive_key Architectures | tr '\n' ' ' | sed 's/[[:space:]]*$//')
created_at=$("$plist_buddy" -c 'Print :CreationDate' "$archive/Info.plist")
generated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

record_name="Checkpoint-${version}-${build}"
manifest_name="${record_name}-manifest.md"
archive_checksums_name="${record_name}-xcarchive-files.sha256"
artifact_checksums_name="${record_name}-artifacts.sha256"

mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd -P)
case "$output_dir/" in
    "$repo_root/"*)
        echo "OUTPUT_DIR must be outside the Git worktree." >&2
        exit 64
        ;;
esac

for target in \
    "$output_dir/$manifest_name" \
    "$output_dir/$archive_checksums_name" \
    "$output_dir/$artifact_checksums_name"; do
    if [[ -e "$target" ]]; then
        echo "Refusing to replace release record: $target" >&2
        exit 73
    fi
done

temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/checkpoint-release-manifest.XXXXXX")
trap 'rm -rf "$temporary_dir"' EXIT

extension_identities() {
    local application=$1
    local plugins="$application/PlugIns"
    if [[ ! -d "$plugins" ]]; then
        return
    fi
    while IFS= read -r -d '' extension; do
        local executable
        executable=$("$plist_buddy" -c 'Print :CFBundleExecutable' "$extension/Info.plist")
        printf '%s|%s|%s|%s\n' \
            "$("$plist_buddy" -c 'Print :CFBundleIdentifier' "$extension/Info.plist")" \
            "$("$plist_buddy" -c 'Print :CFBundleShortVersionString' "$extension/Info.plist")" \
            "$("$plist_buddy" -c 'Print :CFBundleVersion' "$extension/Info.plist")" \
            "$(binary_uuid_fingerprint "$extension/$executable")"
    done < <(find "$plugins" -mindepth 1 -maxdepth 1 -type d -name '*.appex' -print0)
}

binary_uuid_fingerprint() {
    local executable=$1
    if [[ ! -f "$executable" ]]; then
        return 1
    fi
    xcrun dwarfdump --uuid "$executable" \
        | awk '{print $2 ":" $3}' \
        | LC_ALL=C sort \
        | tr '\n' ','
}

if [[ -n "$ipa" ]]; then
    if ! unzip -tqq "$ipa" >/dev/null 2>&1; then
        echo "IPA is not a readable ZIP archive." >&2
        exit 65
    fi
    mkdir -p "$temporary_dir/ipa"
    unzip -q "$ipa" -d "$temporary_dir/ipa"
    shopt -s nullglob
    ipa_apps=("$temporary_dir/ipa/Payload/"*.app)
    shopt -u nullglob
    if [[ ${#ipa_apps[@]} -ne 1 || ! -f "${ipa_apps[0]}/Info.plist" ]]; then
        echo "IPA must contain exactly one main application in Payload." >&2
        exit 65
    fi
    ipa_app=${ipa_apps[0]}
    ipa_bundle_id=$("$plist_buddy" -c 'Print :CFBundleIdentifier' "$ipa_app/Info.plist")
    ipa_version=$("$plist_buddy" -c 'Print :CFBundleShortVersionString' "$ipa_app/Info.plist")
    ipa_build=$("$plist_buddy" -c 'Print :CFBundleVersion' "$ipa_app/Info.plist")
    archive_executable=$(read_app_key CFBundleExecutable)
    ipa_executable=$("$plist_buddy" -c 'Print :CFBundleExecutable' "$ipa_app/Info.plist")
    archive_binary_uuid=$(binary_uuid_fingerprint "$app/$archive_executable")
    ipa_binary_uuid=$(binary_uuid_fingerprint "$ipa_app/$ipa_executable")
    archive_extensions=$(extension_identities "$app" | LC_ALL=C sort)
    ipa_extensions=$(extension_identities "$ipa_app" | LC_ALL=C sort)
    if [[ "$ipa_bundle_id" != "$bundle_id" \
        || "$ipa_version" != "$version" \
        || "$ipa_build" != "$build" \
        || -z "$archive_binary_uuid" \
        || "$ipa_binary_uuid" != "$archive_binary_uuid" \
        || "$ipa_extensions" != "$archive_extensions" ]]; then
        echo "IPA identity, linked Mach-O binaries, or embedded extensions do not match the archive." >&2
        exit 65
    fi
fi

(
    cd "$archive"
    find . -type f -print0 \
        | xargs -0 shasum -a 256 \
        | LC_ALL=C sort -k 2
) > "$temporary_dir/$archive_checksums_name"

archive_fingerprint=$(
    shasum -a 256 "$temporary_dir/$archive_checksums_name" | awk '{print $1}'
)

{
    printf '%s  %s\n' "$archive_fingerprint" "$archive_checksums_name"
    if [[ -n "$ipa" ]]; then
        ipa_digest=$(shasum -a 256 "$ipa" | awk '{print $1}')
        printf '%s  %s\n' "$ipa_digest" "$(basename "$ipa")"
    fi
} > "$temporary_dir/$artifact_checksums_name"

cat > "$temporary_dir/$manifest_name" <<EOF
# Checkpoint Release Manifest

This record is generated once for one exact archive. If any binary changes,
create a new archive and a new record; do not edit this record in place.

## Identity

- Generated (UTC): \`$generated_at\`
- Source commit supplied by release operator: \`$source_commit\`
- Archive creation date: \`$created_at\`
- App: \`$app_name\`
- Bundle ID: \`$bundle_id\`
- Version: \`$version\`
- Build: \`$build\`
- Team: \`$team_id\`
- Architectures: \`$architectures\`
- Minimum OS: \`$minimum_os\`
- SDK: \`$sdk_name\`
- Xcode build: \`$xcode_build\`

## Binary Contents

- \`$bundle_id\` (main app)
EOF

plugins="$app/PlugIns"
if [[ -d "$plugins" ]]; then
    while IFS= read -r extension; do
        extension_id=$(
            "$plist_buddy" -c 'Print :CFBundleIdentifier' "$extension/Info.plist"
        )
        # The backticks are literal Markdown delimiters around printf's %s field.
        # shellcheck disable=SC2016
        printf -- '- `%s` (extension)\n' "$extension_id" \
            >> "$temporary_dir/$manifest_name"
    done < <(find "$plugins" -mindepth 1 -maxdepth 1 -type d -name '*.appex' | LC_ALL=C sort)
fi

cat >> "$temporary_dir/$manifest_name" <<EOF

## Checksums

- Archive inventory: \`$archive_checksums_name\`
- Archive inventory fingerprint (SHA-256): \`$archive_fingerprint\`
- Artifact checksums: \`$artifact_checksums_name\`
- IPA included: \`$([[ -n "$ipa" ]] && printf yes || printf no)\`

When an IPA is included, its app bundle ID, version, build, main Mach-O UUID,
and versioned extension identities/Mach-O UUIDs were verified against the
archive before hashing.

The inventory contains file paths and SHA-256 digests only. It deliberately
does not print embedded configuration values, provisioning-profile contents,
Keychain values, or credentials.
EOF

mv "$temporary_dir/$manifest_name" "$output_dir/$manifest_name"
mv "$temporary_dir/$archive_checksums_name" "$output_dir/$archive_checksums_name"
mv "$temporary_dir/$artifact_checksums_name" "$output_dir/$artifact_checksums_name"
chmod 444 \
    "$output_dir/$manifest_name" \
    "$output_dir/$archive_checksums_name" \
    "$output_dir/$artifact_checksums_name"

printf 'Created release record:\n  %s\n  %s\n  %s\n' \
    "$output_dir/$manifest_name" \
    "$output_dir/$archive_checksums_name" \
    "$output_dir/$artifact_checksums_name"
