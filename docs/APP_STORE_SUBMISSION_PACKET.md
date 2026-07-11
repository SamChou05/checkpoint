# App Store Submission Packet

Prepared July 10, 2026. This is the canonical handoff for Checkpoint's first
App Store submission. It separates verified build facts from owner decisions
and placeholders so missing business information is never guessed.

## Release Status

- AWS question generation and the optional cloud reserve are deployed.
- The iOS app and its three Screen Time extensions have a successful local
  device archive for version `1.0`, build `2`.
- The production backend credential was rotated after a local diagnostic
  exposure. The earlier archive was deleted, and version `1.0`, build `2` was
  rebuilt and verified with the replacement credential on July 10, 2026.
- The current archive is development-signed. App Store export must re-sign it
  after the shipping Apple Account and distribution profiles are available.
- New consent and in-app legal-link release gates were added after that archive;
  rebuild from the final commit with owner-approved Privacy and Support URLs.
  Build 2 may be reused only if App Store Connect confirms it was never uploaded.
- App Store export and upload remain blocked until the shipping Apple Account
  is associated with team `RF8739P5MC` in App Store Connect and Xcode.
- Family Controls distribution approval must show as assigned for the main app
  and every Screen Time extension before App Store signing can succeed.
- The bearer value embedded in the client is extractable from any IPA and must
  be treated as a public API identifier, not a secret. Install/IP quotas bound
  routine use, but a public launch still needs App Attest/server-issued auth or
  an explicit owner acceptance of the remaining abuse and Bedrock-cost risk.

## Verified Identifiers

| Field | Value |
| --- | --- |
| Requested app name | `Checkpoint` (App Store name availability not verified) |
| Main bundle ID | `com.samchou.checkpoint` |
| Shield Configuration extension | `com.samchou.checkpoint.ShieldConfigurationExtension` |
| Shield Action extension | `com.samchou.checkpoint.ShieldActionExtension` |
| Device Activity Monitor extension | `com.samchou.checkpoint.DeviceActivityMonitorExtension` |
| App Group | `group.com.samchou.checkpoint` |
| Apple team | `RF8739P5MC` |
| Current marketing version | `1.0` |
| Current candidate build | `2` — confirm it is unused in App Store Connect before upload |
| Monthly product ID | `checkpoint.membership.monthly` |
| Annual product ID | `checkpoint.membership.yearly` |
| In-app account | None; no demo username or password is required |

## Owner Inputs Required

Fill every required placeholder before selecting **Add for Review**. Do not
substitute temporary or invented URLs.

| App Store Connect field | Submission value |
| --- | --- |
| App name | **OWNER CONFIRMATION — `Checkpoint`, subject to availability** |
| SKU | **REQUIRED PLACEHOLDER — internal owner-selected value** |
| Primary language | **REQUIRED PLACEHOLDER — owner selection** |
| Subtitle | **REQUIRED DECISION — choose one final option from `docs/APP_STORE_COPY.md`** |
| Primary category | **OWNER CONFIRMATION — project currently declares Productivity** |
| Secondary category | **OPTIONAL PLACEHOLDER** |
| Privacy Policy URL | **REQUIRED PLACEHOLDER — must be public, hosted, and linked inside the app** |
| Terms of Use URL | **REQUIRED DECISION — Apple standard EULA or an approved custom EULA, linked inside the app** |
| Support URL | **REQUIRED PLACEHOLDER — must be a working public page with actual support/feedback contact information** |
| Marketing URL | **OPTIONAL PLACEHOLDER** |
| Copyright | **REQUIRED PLACEHOLDER — exact owner/legal entity and year** |
| App Review contact name | **REQUIRED PLACEHOLDER** |
| App Review contact email | **REQUIRED PLACEHOLDER** |
| App Review contact phone | **REQUIRED PLACEHOLDER** |
| Release option | **REQUIRED DECISION — manual, automatic, or scheduled** |
| App availability | **REQUIRED DECISION — countries/regions** |
| Subscription availability | **REQUIRED DECISION — countries/regions** |
| Monthly and annual prices | **OWNER CONFIRMATION — drafts are `$4.99` and `$29.99`; storefront tiers are not configured yet** |
| Content rights | **OWNER/LEGAL ANSWER REQUIRED** |
| Age rating | **OWNER ANSWERS REQUIRED — complete Apple's current questionnaire** |
| Privacy responses | **OWNER/LEGAL CONFIRMATION REQUIRED — use the worksheet below** |
| Screenshots | **REQUIRED PLACEHOLDER — capture from the final release candidate** |
| Subscription review screenshots | **REQUIRED PLACEHOLDER — one clear purchase-screen image per product** |

The copy drafts and screenshot shot list remain in `docs/APP_STORE_COPY.md`.
The privacy-policy source remains in `docs/PRIVACY_POLICY_DRAFT.md`; it is not a
substitute for a hosted policy URL.

## App Review Notes — Copy/Paste Draft

Replace no text in this block unless behavior changes. Add the completed review
contact fields in App Store Connect, not inside the notes.

```text
Checkpoint does not require an account or demo credentials.

Purpose and reviewer path:
1. Launch the app and create a learning goal.
2. In Settings, tap “Allow Screen Time,” approve Family Controls access, then tap “Choose protected apps” and select an app or category.
3. Return to Home and tap “Start protection.”
4. Open a selected app. iOS displays Checkpoint’s custom Screen Time shield.
5. Tap “Open Checkpoint.” Complete the short multiple-choice set. By default, 4 correct answers out of 5 starts a timed break; a failed set keeps protection active and prioritizes missed questions on the next attempt.

Checkpoint uses Family Controls, Managed Settings, Managed Settings UI, Device Activity, three Screen Time extensions, and App Group group.com.samchou.checkpoint. The App Group shares only the state needed for the shield and timed unlock flow, including the pending shield action, selected opaque Screen Time tokens, current goal display text, protection state, unlock expiration, and diagnostics.

Question generation is batch-based and cached locally, so opening a protected app does not wait for an AI request. The app asks iOS to run bounded BGAppRefreshTask/BGProcessingTask maintenance when the bank is low; execution timing remains controlled by iOS. Generation may use supported on-device Apple Foundation Models, the configured AWS Bedrock service, or local templates.

Users explicitly enable Settings > “Cloud question generation” before any ordinary backend generation receives goal context. Pro users may then separately enable “Questions ready while the app is closed.” A per-install authenticated AWS queue worker can prepare a bounded reserve while the app process is not running, and the app pulls it at the next permitted maintenance run or launch. The reserve stores one revisioned goal-generation snapshot and at most 20 prepared or awaiting-delivery questions per goal, with automatic expiry after at most 30 days without an authenticated update. It does not receive Screen Time selections, unlock history, purchase records, or the learner’s complete answer history. Withdrawing cloud-generation consent, reserve opt-out, goal deletion, downgrade, and reset request deletion; TTL expiry is the offline fallback.

Checkpoint uses StoreKit 2 for the optional monthly and annual Checkpoint Pro subscriptions. The complete Screen Time protection, checkpoint, timed-unlock, and re-lock flow is available on Free. Pro charges only for additional learning goals, ongoing question generation and variety, the optional cloud reserve, and guided review features.
```

Before submission, confirm this note still matches the final binary and remains
within App Store Connect's 4,000-byte Notes limit.

## App Privacy Worksheet

This worksheet is evidence for the App Store privacy questionnaire, not legal
advice and not a preselected answer. Apple requires responses to include the
app and third-party partners. The Account Holder, Admin, or App Manager must
confirm and publish the final answers.

| Behavior in the shipping app | Current evidence | App Store answer to confirm |
| --- | --- | --- |
| Goals, focus areas, derived learning targets, weak topics, prompt coverage, and question reports may be sent to the configured generation service | Used only to generate and diversify practice questions | **CONFIRM classification, likely User Content and/or Product Interaction; purpose App Functionality; determine whether linked to the random installation ID** |
| Optional cloud reserve retains a bounded goal snapshot and prepared questions | Opt-in Pro feature; maximum 20 prepared/held questions per goal; expires after at most 30 days without an authenticated update | **CONFIRM collected data types, retention disclosure, and whether each is linked to the installation identifier** |
| A random installation ID and hashed installation secret support authentication and quotas | No user account, advertising ID, or contact identity is created by Checkpoint | **CONFIRM whether Apple classifies the random app installation ID as an Identifier/Device ID** |
| Source IP may be used by the backend for abuse and generation quotas | Operational security and cost control | **CONFIRM whether IP handling requires an Other Data or identifier disclosure under the final AWS logging/retention configuration** |
| Screen Time app/category/web selections and unlock history stay on device | Shared locally with extensions through the App Group; not uploaded to the reserve | **CONFIRM “not collected” for these fields** |
| StoreKit supplies subscription entitlement state | Apple handles billing; Checkpoint reads current entitlement | **CONFIRM Purchases/Financial Information answers against Apple's current definitions** |
| No advertising or cross-company tracking is implemented | No tracking domains or ad SDKs in the current implementation | **CONFIRM data is not used for tracking** |
| Local goals, questions, answers, history, competency, and diagnostics remain on device unless included in the limited generation context above | Deleted by app reset/uninstall; local persistence is described in the policy draft | **CONFIRM on-device-only data is excluded where Apple's definition permits** |

Do not choose “No, we do not collect data from this app” without resolving the
backend and reserve rows. Apple explains that app privacy answers must cover
the developer and third-party partners in its
[App Privacy workflow](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy).

Before release, the hosted and in-app policy must explain collection and use,
AWS/model-provider processing and safeguards, IP/quota/log handling, retention
and deletion (including TTL fallback), and how consent can be withdrawn. The
cloud-reserve toggle covers reserve retention only; ordinary backend generation
also needs a clear consent path before goal context is transmitted.

## Exact Final App Store Connect Sequence

1. **Restore account access.** The Account Holder signs in to App Store
   Connect, accepts current agreements, and invites the release operator in
   **Users and Access** if needed. Upload requires Account Holder, Admin, App
   Manager, or Developer; final submission requires Account Holder, Admin, or
   App Manager. Add the same Apple Account in Xcode Settings > Accounts. See
   Apple's [App Store Connect workflow](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-workflow).

2. **Confirm distribution capabilities.** In Certificates, Identifiers &
   Profiles > Capability Requests, verify Family Controls (Distribution) is
   **Assigned** to the main app and all three extension identifiers. The
   Account Holder must request each identifier separately. With automatic
   signing, refresh profiles in Xcode after approval. Apple documents this in
   [Requesting the Family Controls entitlement](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement).

3. **Create the app record if it does not exist.** In Apps, click **+ > New
   App**, select iOS, then enter the confirmed name, primary language, main
   bundle ID, SKU, and user access. Apple requires the record before upload;
   follow [Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/).

4. **Complete business setup.** In Business, make the Paid Apps Agreement
   active before submitting or updating subscriptions. Finish tax and banking
   details before proceeds can be paid. Set the app's price and availability;
   the intended app price must be confirmed by the owner.

5. **Create subscriptions.** Under Monetization > Subscriptions, create one
   group named `Checkpoint Pro`, then create monthly and annual products using
   the exact IDs above at the same subscription level because they grant the
   same access for different durations. Add duration, localization, price,
   availability, review notes, and a review screenshot to each until both show
   **Ready to Submit**.
   Apple's current sequence is in
   [Offer auto-renewable subscriptions](https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions).

6. **Finalize the release artifact.** The exposed production credential has
   been rotated. After the final source commit and owner URL configuration,
   rerun `scripts/release-preflight.sh`, create the final archive (build 2 only
   if still unused), complete the physical-device checks, and generate the
   immutable record from `docs/RELEASE_ARTIFACTS.md`.

7. **Upload.** In Xcode Organizer, select the new archive, then **Distribute
   App > App Store Connect > Upload** with automatic signing. Upload only the
   final post-rotation archive produced from the final commit; never upload an
   earlier archive.
   Apple associates the upload using bundle ID, version, and build number;
   wait for processing to complete and inspect every warning. See
   [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

8. **Resolve compliance.** If App Store Connect requests export-compliance
   answers, complete them truthfully for the final binary. The project declares
   `ITSAppUsesNonExemptEncryption = false`, but that declaration does not
   replace the owner's legal determination. Use Apple's
   [export-compliance workflow](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation).

9. **Complete app-level information.** In General > App Information, confirm
   name, categories, content rights, copyright, and the required age-rating
   questionnaire. Do not mark the app as Made for Kids without an explicit
   owner/legal decision.

10. **Publish privacy answers.** In App Privacy, enter the hosted privacy-policy
    URL, complete every data-type follow-up using the final backend behavior,
    preview the labels, and click **Publish**. Verify the same policy and the
    selected Terms of Use are easily accessible inside the app, and that the
    ordinary backend-generation flow obtains the documented consent.

11. **Complete version 1.0 metadata.** Add the final subtitle, promotional text,
    plain-text description, keywords, support URL with real contact information,
    screenshots, review contact, and the canonical notes above. If using
    Apple's standard EULA, include its link in the description. Use the final
    build for screenshots and verify all purchase claims against the products
    actually available.

12. **Select the processed build.** On the iOS version page, add the processed
    release build and clear any compliance or warning badge. Confirm its
    version, build number, manifest fingerprint, and IPA digest match the
    release record.

13. **Attach the first subscriptions.** On the version page, under In-App
    Purchases and Subscriptions, select both Ready to Submit subscriptions.
    Apple requires first subscriptions to be reviewed with a new app version;
    see [Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase).

14. **Choose release timing and save.** Select manual, automatic, or scheduled
    release only after the owner makes that decision. Manual release is safest
    for a first launch when operational monitoring is still being verified.

15. **Run TestFlight gates.** Install the processed build on a physical iPhone
    and finish the shield/unlock/re-lock, background maintenance, cloud-reserve,
    purchase, restore, expiration, privacy, and support-link checks in
    `docs/FINAL_LAUNCH_TEST_LOG.md`. Do not submit a build that differs from the
    tested build.

16. **Submit.** With both first subscriptions already attached to the version
    in step 13, click **Add for Review**, add the app version to the draft
    submission, inspect the draft, then click **Submit for Review**. This
    two-step flow is documented in
    [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app).

## Stop Conditions

Do not click **Submit for Review** while any of these is unresolved:

- App Store Connect provider/team access;
- Family Controls distribution approval for any shipping identifier;
- a post-rotation archive and manifest from the final source commit;
- physical-device Screen Time and background validation;
- Paid Apps Agreement, tax, banking, or subscription metadata;
- hosted and in-app Privacy Policy/Terms access, backend consent, and a support
  URL with real contact information;
- a public-backend abuse-control decision (App Attest/server-issued auth or an
  explicit acceptance of the extractable-client-token risk);
- final privacy answers, screenshots, age rating, content rights, review
  contact, or release timing; or
- a build, manifest, IPA, and selected App Store Connect build number that do
  not match exactly.
