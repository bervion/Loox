# Private Email diagnosis, 2026-09-22

## Confirmed

- User reports TestFlight: verifying a forwarding inbox and creating aliases show the same relay-connection headline, with body “Kiểm tra kết nối mạng và iCloud, rồi thử lại”. This matches both principalUnavailable and generic rejected failures.
- Read-only production service-state request returned HTTP 200, `private_email: active`.
- Production domain registry returned v14: `relay-main` active for email; `email-pw` createDisabled. This HTTP check does not independently verify the signature.
- The domain section hid itself with exactly one choice; address rendering removed the domain for every non-active alias. Both now retain domain visibility. Forwarding status remains separate.
- Escrow errors were mapped to the generic relay headline. CloudKit reads also swallowed every error as absence. The client now distinguishes escrow failures and only treats unknownItem/zoneNotFound as absence.

## Unresolved

The reported device failure has not been reproduced. A healthy public endpoint does not prove signed mutations or delivery work. The confirmed alert body is shared by multiple failure paths; need a device log to distinguish CloudKit Production account/schema/escrow issues from App Attest and API rejection. No backend/CloudKit state was modified. No identity was deleted or regenerated.

## UI review

- Protagonist: identify the chosen email address/domain and its forwarding status. A single domain is a read-only row; multiple domains retain the existing picker.
- Text: reused Email Domain EN/VI and native status labels; added distinct EN/VI iCloud guidance. No user-copy separators or new visual constants.
- Controls: read-only row adds no hit target or haptic. Existing picker interactions remain unchanged.
- Shape/space: native Section/LabeledContent, semantic secondary foreground, no new colors, motion, or padding.
- States: one/multiple domains handled; no domains still means no creation choice. Unverified/paused aliases retain their domain but do not change forwarding state or trigger writeback.
- Device matrix: visual verification at SE/Pro Max widths, large Dynamic Type, EN/VI, light/dark, increased contrast and reduced motion/transparency is still pending. Static review does not substitute for this matrix.

## Validation

- Generated workspace using the repository-pinned Tuist 4.200.1 via mise (system Tuist 3.2.0 is incompatible).
- EN/VI catalog entries validated; git diff whitespace check passed.
- Targeted XCTest run passed: 35 tests, zero failures across EmailAliasTests, RelayRetryPolicyTests, RelayAPIClientTests and RelayPrincipalIdentityTests. App and embedded extensions compiled successfully for the iOS simulator. Log: `/tmp/vaultify-relay-xc.log`.
- Physical TestFlight inbox verification and mail forwarding remain required.

## Follow-up: Simulator authentication

User supplied `Principal escrow failed: domain=CKErrorDomain code=9`, then confirmed this
log came from Simulator. The installed SDK maps code 9 to `CKError.notAuthenticated`.
This particular attempt failed during CloudKit escrow access before a relay request.
It does not establish the cause of the earlier TestFlight report. Simulator needs its own
valid iCloud session; full relay verification still requires physical-device App Attest.
The client now maps this specific CloudKit error to localized account sign-in guidance,
while retaining the generic escrow failure for other domains/codes. No keys are replaced.

Validation of the authentication follow-up: the actual classifier was extracted and run
against the local Swift/CloudKit SDK. CKErrorDomain/9 mapped to authentication-required;
network, permission, server-rejected and unrelated-domain/9 mapped to generic escrow failure.
All five checks passed; EN/VI/JA entries and diff whitespace validated. The full XCTest run
was blocked twice by exhausted disk space, including after removing a duplicate package cache.
Task-owned temporary derived data was then removed. Do not treat earlier XCTest results as
verification of this follow-up; the new regression tests still require a full rerun.
