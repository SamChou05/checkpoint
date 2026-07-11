# Release Artifacts And Build Manifest

Use this procedure for every TestFlight or App Store binary. It creates a
write-once record that ties the source commit to one exact archive and, after
export, one exact IPA without exposing embedded configuration.

## Credential Rotation Record

A production credential appeared in local command output during release
inspection on July 10, 2026. The credential was rotated, the earlier archive
was deleted, and `Checkpoint 1.0 (2)` was rebuilt and verified with the
replacement injected through the local environment rather than an
`xcodebuild` argument. Only archives created after that rotation are eligible
for release.

Do not inspect a production archive with broad commands such as `plutil -p`,
`strings`, or recursive text search. They can print embedded credentials. Read
only specifically allowlisted, non-secret keys, and never paste a production
configuration value into a release record.

## Manifest Tool

The repository includes `scripts/generate_release_manifest.sh`. It reads only
non-secret identity fields and creates:

- a Markdown manifest with version, build, bundle IDs, team, SDK, and source
  commit;
- a sorted SHA-256 inventory of every regular file in the archive;
- a SHA-256 fingerprint of that inventory; and
- an IPA SHA-256 digest when an exported IPA is supplied.

The script refuses to overwrite a record for the same version and build. Its
output files are made read-only, and its output directory must be outside the
Git worktree. The supplied source commit must exist in this repository. When
an IPA is supplied, the tool extracts it privately and requires its main bundle
ID, version, build, linked Mach-O UUID, and versioned extension identities and
Mach-O UUIDs to match the archive before it writes any record. This ties the
export to the linked archive binaries while allowing distribution re-signing.
This is an operational guard, not tamper-proof storage;
copy the completed record to the team's restricted, durable release storage.

## Create The Record

1. Confirm the source tree and capture the exact commit that produced the
   archive:

   ```sh
   git status --short
   git rev-parse HEAD
   ```

2. Run `scripts/release-preflight.sh` from a clean, pushed source commit, then
   create or confirm the post-rotation archive with a unique build number. Keep production
   credentials out of shell arguments and logs. The preflight contract and
   options are documented in `docs/LOCAL_RELEASE_PREFLIGHT.md`.

3. Before export, generate an archive-only record. Replace the example paths
   and commit:

   ```sh
   scripts/generate_release_manifest.sh \
     ../release/Checkpoint-1.0-NEW_BUILD.xcarchive \
     ../release/manifests/1.0-NEW_BUILD-archive \
     FULL_40_CHARACTER_SOURCE_COMMIT
   ```

4. After App Store export succeeds, create the final record in a new output
   directory and include the IPA:

   ```sh
   scripts/generate_release_manifest.sh \
     ../release/Checkpoint-1.0-NEW_BUILD.xcarchive \
     ../release/manifests/1.0-NEW_BUILD-upload \
     FULL_40_CHARACTER_SOURCE_COMMIT \
     ../release/AppStore-1.0-NEW_BUILD/Checkpoint.ipa
   ```

5. Never edit or regenerate a record in place. If the archive, IPA, signing,
   configuration, or source changes, create a new build and record.

## Verify Before Upload Or Handoff

Verify every archive file from inside the archive directory so the relative
paths in the inventory resolve correctly:

```sh
checksums=$(cd ../release/manifests/1.0-NEW_BUILD-upload && pwd)/Checkpoint-1.0-NEW_BUILD-xcarchive-files.sha256
cd ../release/Checkpoint-1.0-NEW_BUILD.xcarchive
shasum -a 256 -c "$checksums"
```

Then independently hash the IPA and compare it with the digest in
`Checkpoint-1.0-NEW_BUILD-artifacts.sha256`:

```sh
shasum -a 256 ../release/AppStore-1.0-NEW_BUILD/Checkpoint.ipa
```

The final handoff is complete only when the manifest identity, archive
inventory, IPA digest, selected App Store Connect build number, and Git source
commit all agree.

## Safe Manifest Fields

Record these fields:

- app name, bundle ID, marketing version, and build number;
- source commit and archive creation timestamp;
- team ID, architecture, minimum OS, SDK, and Xcode build;
- main app and extension bundle IDs;
- archive inventory fingerprint and IPA digest; and
- validation results and the App Store Connect processing status.

Never record these fields:

- backend bearer tokens, reserve secrets, Keychain values, or credential
  hashes;
- complete `Info.plist` output or provisioning-profile contents;
- App Store Connect API private keys or app-specific passwords; or
- unredacted environment dumps or build command lines containing secrets.
