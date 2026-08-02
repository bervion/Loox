---
title: "Phase 6: iOS Developer Asset Pack"
status: done
---

# Phase 6: iOS Developer Asset Pack

## Outcome

Make Vaultify genuinely useful to iOS developers by safely storing, inspecting, linking, and exporting
small Apple developer credentials and signing artifacts after Artifact v2 is proven.

## Type Contracts

| Type | Semantic data | Artifact/action policy |
|---|---|---|
| App Store Connect API Key | issuer ID, key ID, Team ID, role, created date, user-recorded status | `.p8`; import/export gated; key is downloadable once at creation |
| APNs Authentication Key | key ID, Team ID, environments/topics notes | `.p8`; gated export; never network-test automatically |
| Apple Signing Identity | certificate kind, common name, Team ID, serial, SHA-256 fingerprint, validity | `.p12` plus separate passphrase policy; inspect locally, gated export |
| Provisioning Profile | UUID, name, app identifier, Team ID, distribution, platforms, entitlements summary, devices, expiry | `.mobileprovision`; local metadata parser, gated export |
| TLS Certificate | subject/issuer, serial, fingerprint, key usage, validity | `.cer/.pem`; link to private-key artifact when applicable |

## Requirements

- [ ] Artifact v2 backup/sync/delete/temp gates from Phase 3 are green before release enablement.
- [ ] Parsers are local-only, bounded, and treat all imported metadata as untrusted.
- [ ] Parser services/frameworks are app-only; AutoFill and Safari targets receive only pure models and resolver contracts.
- [ ] `.p12` inspection does not persist a second extracted private-key copy.
- [ ] Expiry is field/artifact lifecycle, not overloaded `passwordChangedAt`.
- [ ] No automatic Keychain installation, signing-environment mutation, network validation, or revocation.

## File Inventory

- Add Apple developer template descriptors and semantic roles.
- Add bounded parser adapters using Security/Foundation APIs available on iOS 17.3.
- Add artifact metadata projections, validity/expiry audit rules, and typed links.
- Add import-first editor/detail flows and guarded system Share/Export; do not promise a specific AirDrop destination.
- Add fixture generators or sanitized test fixtures; never commit real keys/certificates/profiles.

## Implementation Steps

1. Define parser output structs and strict byte, nesting depth, object/key count, string length, KDF work,
   and deadline/cancellation limits. Sniff content instead of trusting extension/UTI/MIME. Normalize or
   escape bidi/control characters in display metadata. Original bytes remain canonical.
2. Implement ASC/APNs `.p8` inspection and metadata entry; never infer authority from filename alone.
3. Implement `.p12` inspection through platform Security APIs with passphrase scoped in memory. Extract
   display metadata only; erase transient buffers and temporary keychain objects.
4. Implement provisioning profile/certificate parsing with untrusted-input limits and expiry derivation.
   Distinguish parsed, CMS signature valid, locally trusted, and live revocation checked; never imply one
   from another or automatically open URLs supplied by imported metadata.
5. Add typed relationships: signing identity to profiles/certificates and team/application metadata.
6. Add explicit export confirmation with artifact type, destination, and re-auth policy. Clean temp files.
7. Add expiry/rotation dashboard slices for developer assets without sending identifying metadata.

## Verification Matrix

- Valid/expired/not-yet-valid/malformed/wrong-extension/oversized fixtures for every parser.
- Deep ASN.1/plist, large KDF, Unicode bidi/control, parser timeout, and fuzz fixtures under sanitizers.
- `.p12` correct/wrong/empty passphrase; zero persistent extracted private keys after inspection.
- Provision profile distribution variants, entitlements limits, and timestamp boundary cases.
- Backup/restore and two-device sync of metadata plus ciphertext bytes.
- Negative: no Apple private material in search, logs, automated snapshots, analytics, AutoFill, or Safari.
- Scope screenshot guarantees honestly: automated snapshots/logs/app-switcher are concealed; after an
  explicit user reveal the OS cannot guarantee prevention of a user-initiated screenshot.

## Risks and Mitigations

- Security framework import may create transient Keychain state: isolate and assert cleanup in tests.
- Give transient P12 imports a dedicated tag/access group, `synchronizable = false`, cleanup before/after,
  and a startup janitor for crash recovery. Avoid unprovable “zeroize Swift String” claims; minimize copies.
- Apple formats evolve: preserve opaque original bytes and show “unverified” instead of rejecting recovery.
- Users may confuse storage with revocation status: only show locally known expiry; link to provider for live state.

## Success Criteria

- [ ] Supported Apple artifacts import, inspect, export, backup, restore, sync, and delete without byte loss.
- [ ] Validity/fingerprint metadata matches independent platform tooling fixtures.
- [ ] No parser leaves durable extracted secrets or plaintext temp files.
- [ ] UI states clearly distinguish locally parsed validity from live provider status.
