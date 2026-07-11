# Public Backend Authorization

Checkpoint's current shared bearer is suitable only as a rollout switch for a
bounded private/TestFlight backend. It is embedded in the app and therefore
extractable by anyone who receives the IPA. Install and source-IP quotas reduce
routine abuse, but caller-supplied installation IDs and a replayable bearer do
not establish that a request came from an authentic Checkpoint installation.

Do not enable unrestricted public Bedrock generation until this document's
App Attest/session gate is implemented and verified, or the owner explicitly
accepts the remaining abuse and AI-cost risk.

## Smallest Staged Design

```text
app -> POST /auth/challenge
app -> App Attest attestation or assertion
app -> POST /auth/attest or /auth/session
app <- short-lived opaque session token
app -> existing generation and /reserve/* routes
```

1. A rate-limited public challenge route returns a single-use challenge ID and
   exact client-data bytes.
2. The app keeps one App Attest key ID in device-only Keychain storage. It
   checks `DCAppAttestService.isSupported` and falls back locally when App
   Attest or the network is unavailable.
3. The backend validates Apple's certificate chain, nonce, App ID, environment,
   key identity, assertion signature, and monotonic counter. Follow Apple's
   [server validation guide](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server).
4. A successful attestation/assertion issues a random 256-bit opaque session.
   Store only its SHA-256 hash, bind it to the installation and attested key,
   expire it after about 30 minutes, and refresh five minutes early.
5. Preserve the existing per-install reserve secret as defense in depth. Remove
   the app-wide bearer after a measured dual-auth migration window.

Use a dedicated encrypted DynamoDB table for single-use challenges, attested
keys/counters/receipts, and hashed sessions. Every record needs an explicit
expiry check plus DynamoDB TTL cleanup.

The current Lambda Function URL can remain `AuthType: NONE`; Function URLs only
offer `NONE` and `AWS_IAM`, and anonymous iOS IAM credentials would add a much
larger Cognito/STS surface. Custom auth must run before any Bedrock work. Note
that public callers can still incur basic Lambda invocation cost, so quotas,
concurrency caps, alarms, and a billing budget remain necessary. See AWS's
[Function URL authorization](https://docs.aws.amazon.com/lambda/latest/dg/urls-auth.html).

## Keep Authentication Off The Checkpoint Path

- Always serve a blocked-app checkpoint from the validated local bank.
- Share one in-flight session refresh across concurrent app requests.
- Retry once after an authorization failure; never create a retry loop.
- Once reserve sync succeeds, queued generation continues without a live app
  session.
- Never invoke App Attest from Screen Time extensions.
- Keep a never-asked local fallback set for offline, unsupported, reinstall,
  migration, or invalid-key recovery.

Apple requires checking support and handling unsupported devices gracefully.
Attest keys survive normal updates but not every reinstall, backup restore, or
device migration. Use Apple's
[client integration guidance](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity)
for key lifecycle and recovery.

## Rollout

1. Deploy challenge, attestation, assertion, and session validation in a
   `legacy_or_attest` mode.
2. Add an injected Swift authorization coordinator and fake-service tests.
3. Enable the development entitlement and pass real-iPhone tests.
4. Validate production App Attest through TestFlight. Development and
   distribution environments must remain distinct; see Apple's
   [App Attest environment rules](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.devicecheck.appattest-environment).
5. Build a replacement binary with no shared bearer in Info.plist, xcconfig,
   command arguments, or archive contents.
6. Measure session/attestation failure rates during a defined grace period.
7. Disable legacy authorization, rotate/remove the old bearer, and keep local
   generation available to older builds.

## Work Possible Before Apple Access

- Backend auth routes, DynamoDB state, dual-auth flag, and deterministic tests.
- Swift coordinator, Keychain lifecycle, coalesced refresh, and local fallback.
- Synthetic attestation/assertion rejection fixtures.
- Archive checks that fail if a shared bearer remains embedded.

Apple team access is still required to confirm the App ID prefix, enable and
sign the App Attest capability, refresh profiles, run real-device development
attestation, and validate a distributed TestFlight build. Optional DeviceCheck
risk receipt calls also require an Apple-created private key.

## Release Acceptance

- Wrong root, nonce, App ID, environment, key ID, category, bundle version,
  signature, counter, install binding, or session expiry is rejected.
- Challenges are single-use under concurrent replay.
- Concurrent app calls perform one shared refresh.
- Unsupported/offline App Attest cleanly selects Apple Foundation/local
  generation.
- Physical background reserve sync passes in development and TestFlight.
- The final archive contains no global backend bearer.
- Installation/IP quotas, four CloudWatch alarms, and an owner-selected AWS
  budget/notification destination remain active.

This is moderate, security-sensitive work rather than a prompt-only change.
Plan roughly four to eight focused engineering days, with most implementation
and unit tests possible before Apple access and final device/distribution proof
dependent on Apple provisioning.
