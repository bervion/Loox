---
title: "Phase 5: Developer Core Pack SSH API and Git"
status: done
---

# Phase 5: Developer Core Pack SSH API and Git

## Outcome

Ship the first useful developer pack around three distinct concepts: SSH key material, API secrets,
and Git hosting accounts that link to credentials instead of duplicating them.

## Type Contracts

### Enhanced SSH Key (`developer.ssh-key`)

Private/public key, passphrase, algorithm, bit size/curve, SHA256 fingerprint, comment, purpose,
username, hosts, created/expiry, original artifact. Import OpenSSH/PEM/PKCS#8/authorized-key formats
using audited parsing support; preserve original bytes. Primary action is Copy Public Key. Private
copy/export always uses action-bound device-owner re-auth; when crypto protection is Level 2 it also
requires the Level-2 key. Unsupported format may be stored opaque with
an honest “saved, not verified” status.

Imported key material is immutable until an explicit Replace flow. Algorithm/fingerprint/public metadata
is read-only and recomputed; purpose/host/comment annotations remain editable. “Saved, not verified”
disables any action requiring verified metadata while still allowing safe opaque recovery/export policy.

### API Secret (`developer.api-secret`)

Provider, account, environment, base URL, key/client ID, token/secret, header name/prefix, scopes,
created/expiry, rotation URL. Actions copy token, authorization header, or environment assignment.
Never enter password strength, HIBP, login AutoFill, or Safari content-script fill.

### Git Hosting Account (`developer.git-account`)

Provider preset, host, username, profile URL, organizations, optional repository owner/path; typed links to PAT/API secret, SSH auth
key, SSH signing key, recovery item. Actions copy clone/config snippets only; no command execution.
Provider presets such as GitHub/GitLab/Bitbucket are metadata, not separate core types.

## Optional Follow-on Types

`developer.server` and `developer.database` should follow the same link model after the core pack is
stable. A server links to SSH authentication; a database links to server/tunnel/TLS artifacts. They do
not block this phase.

## File Inventory

- Add built-in descriptors, role namespaces, validators, summaries, actions, and Polaris icon mappings.
- Add local-only SSH/public-key parsing and fingerprint services behind nonisolated Core APIs.
- Add typed `ItemLink` models and repository resolution; broken links are non-destructive.
- Add import flows, developer action sheets, snippets, expiry/rotation rules, and search operators.
- Add an approved EN/VI terminology glossary (preserving identifiers such as SSH, SHA-256, PAT, `.p8`)
  and maintain existing JA catalog coverage; approve language for unverified/device-only/unavailable states.
- Update integration capability tests and EN/VI localization.

## Implementation Steps

1. Register types and semantic roles with explicit capability matrices before adding UI.
2. Implement SSH import as a parser adapter. Do not hand-write encrypted OpenSSH cryptography; use an
   audited library or deliberately narrow accepted formats and test against `ssh-keygen` vectors.
3. Derive public metadata and validate key pairs where supported. Original bytes remain canonical.
4. Add API Secret templates/presets and generalized field-level expiry/rotation status.
5. Add typed links and Git Account workflows. Deleting a linked item never cascade-deletes another;
   it produces a broken-link state and relink action.
6. Add Copy/snippet actions with explicit source labels and expiry; avoid claiming clipboard contents are
   “safe”. Secret-derived output inherits the strictest source authorization/concealment/clipboard policy,
   is excluded from VoiceOver/logs/snapshots, and snippets are never executed. Clone snippets require an
   explicit repository owner/path; account-only items provide account/config/SSH-host snippets.
7. Gate optional SSH generation until import/export/fingerprint round-trip tests are stable. Device-bound
   Secure Enclave keys, if explored later, are a separate non-portable product type.

## Verification Matrix

- Golden SSH vectors: Ed25519/RSA/ECDSA where supported; CRLF/comments; encrypted/unsupported input;
  private/public mismatch; fingerprint parity with `ssh-keygen -lf`; parser work/depth/time ceilings.
- Round-trip: original SSH bytes and metadata survive edit, backup, and sync.
- API: header/env snippet escaping, expiry boundaries, no accidental search/telemetry of secrets.
- Links: create/relink/delete/broken-link and cycle-safe resolution.
- Negative integrations: all three developer types absent from login AutoFill, Safari fill, password
  health, Quick Link/Quick View, and unauthorized sharing; recipient independently resolves policy.
  Only allowlisted public fields can be copied without re-auth.

## Risks and Mitigations

- SSH format scope can balloon: import-first, audited parser, opaque fallback, generation deferred.
- Git promise mismatch: name UX “Git Hosting Account” and “Copy setup snippet”, never “Git integration”.
- Secret duplication causes stale credentials: link PAT/key items instead of embedding duplicate values.

## Success Criteria

- [ ] Valid supported SSH files import in under 60 seconds and preserve bytes exactly.
- [ ] Fingerprints match the platform oracle; mismatched pairs are detected where parsing supports it.
- [ ] Git account can link authentication and signing items without duplicating secrets.
- [ ] Capability contract proves zero developer-secret leakage to unintended integrations.
