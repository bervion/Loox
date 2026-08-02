# Red-Team and Validation Log

Date: 2026-08-02  
Verdict after amendments: proposal is ready for implementation planning spikes, not immediate full
feature implementation. Phase 1 and the compatibility/crypto spikes are the entry gate.

## Review Lenses

Four hostile passes reviewed the complete draft without editing it:

1. Architecture and backward compatibility.
2. Security, privacy, crypto, and outbound data surfaces.
3. Delivery, CloudKit operations, migration, CI, and rollback.
4. UI/UX, accessibility, localization, recovery, and honest product language.

## Confirmed Findings and Disposition

| Severity | Finding | Disposition applied |
|---|---|---|
| P0 | Unsupported future Codable keys cannot be losslessly edited | Unsupported `schemaVersion` is concealed read-only/recovery; preserve original sealed payload. Supported-schema raw IDs round-trip. |
| P0 | A pre-semantic app can edit/reseal and erase new semantics | Added Release-A writer floor, actual previous-binary edit/sync tests, device/protocol gate, and explicit unsupported downgrade. |
| P0 | Legacy template UUIDs make deterministic role inference impossible | Only provable roles become authoritative; ambiguous fields stay role-less; label/position is suggestion-only. |
| P0 | SSH/Git Release B contradicted Artifact v2/backup durability | Release B now requires Artifact v2 local lifecycle, portable backup, stable IDs, and links; text-only API may precede it. |
| P0 | Artifact backup copied a Vault-Key-wrapped DEK that a new vault cannot open | Backup KEK rewrap contract added; restore test uses a new vault/Keychain with no source key. |
| P0 | “Streaming AEAD” was not an auditable construction | Added a design spike/independent review; exact versioned protocol required, otherwise bounded one-shot AEAD. |
| P0 | Quick Link/View and old share receivers could expose key material | Developer secrets absolutely denied in Quick Link/View v1; receiver negotiation required for policy-sensitive sharing. |
| P0 | Old CloudKit client can advance the shared zone cursor past unknown artifact records | Added per-plane/versioned cursor or mandatory upgrade full-refetch and explicit old-consumer upgrade test. |
| P0 | Live two-device CloudKit gate cannot run in unsigned XCTest CI | Split pure CI mapping/failure tests from signed staging/TestFlight two-device evidence before tag. |
| P0 | Unknown recovery contracts conflicted across phases | One contract: concealed/read-only, encrypted raw recovery export; conversion creates a copy and preserves original. |
| P0 | Secret-derived header/env snippets could bypass source policy | Derived output inherits strictest source policy, action authorization, clipboard, AX, logs, and snapshot restrictions. |
| P0 | SSH canonical bytes versus editable derived fields was undefined | Original bytes immutable until Replace; derived metadata read-only; annotations editable; unverified status gates actions. |
| P1 | Imported policy could lower registry protection | Registry is trusted minimum; stored policy can only tighten; hostile backup/import fixtures added. |
| P1 | Resolver migration inventory omitted direct consumers | Added authoritative consumer inventory, typed projections, and CI/static rule against direct eligibility checks. |
| P1 | UI re-auth and Level-2 crypto were conflated | Split action authorization from crypto protection; L2 artifact DEK requires L2-key wrapping. |
| P1 | Artifact owner/conflict/delete protocol was unclear | V1 is single-owner; item links point to owner item; upload-before-reference and tombstone-before-GC. |
| P1 | Metadata/hash could fingerprint developer infrastructure | Sensitive manifest fields remain sealed; opaque record names; explicit CloudKit leakage budget. |
| P1 | Parser resource and trust states were underspecified | Added bytes/depth/object/KDF/time limits, magic sniffing, bidi handling, signature/trust distinction, fuzz/sanitizers, Keychain janitor. |
| P1 | Shared Core could unnecessarily expose parser/artifact APIs to extensions | Parser/import/unwrap/export remains app-only; extensions receive pure models/resolver; compile-time dependency tests added. |
| P1 | Project already has iPad/Mac destinations despite iPhone-focused premise | Existing targets join decode/resolver/storage regression matrix; terminal agent/helper remains future separate scope. |
| P1 | Picker, error states, VoiceOver, search privacy, and terminology were checklist-only | Added exact picker hierarchy, fallback/error model, behavior-level AX contract, memory-only index, per-type UX table, EN/VI glossary and JA continuity. |
| P1 | CloudKit schema deploy and feature rollback were too vague | Phase 3 owns runbook/full-refetch; flags are honest local/build discovery gates; Phase 7 defines fix-forward owner/SLA. |
| P2 | Template version could silently mutate or grant capability | Version is provenance; IDs append-only; upgrade explicit/idempotent; no silent field re-add/capability escalation. |
| P2 | 10-14 week estimate was too precise | Replaced with 12-20 week provisional p50/p90 model after three mandatory spikes. |

## Validation Decisions

The proposal uses these recommended defaults unless product direction changes:

- Developer private keys, API tokens, and signing assets are not shareable through Quick Link or Quick
  View in v1. Existing login sharing remains intentional and policy-sensitive sharing is negotiated.
- SSH original-file import waits for Artifact v2 local lifecycle plus portable backup; there is no
  device-local warning used as a substitute for durability.
- Portable backup must restore to a new vault/key hierarchy and preserve or correctly remap item IDs,
  artifact ownership, and typed links.
- Unknown future schema is never generically plaintext-copied; the only recovery path is authenticated
  encrypted raw export or copy-conversion preserving the original.
- Re-authentication is an action-bound device-owner authorization grant; Level 2 is a distinct crypto key
  policy. The implementation spike chooses fallback/lifetime/invalidation and AX focus behavior.
- Search projection is decrypted-memory-only and cleared on vault lock.
- Git Hosting Account is account-level unless an explicit repository owner/path is stored; it does not
  promise a clone URL otherwise.
- Apple status is local parse or user-recorded state, never implied live revocation status.
- Proposed artifact ceiling is 20 MiB per file and 250 MiB per vault for product design; the crypto/
  memory/quota spike may lower it. General archives/source repositories remain out of scope.
- UI is iPhone-first for the requested developer workflow, while iPad/Mac compile/decode/policy safety is
  mandatory because those destinations already exist.

## Remaining Design Spikes Before Estimation Freeze

1. Unsupported payload preservation plus real previous-release writer/sync behavior.
2. Exact artifact AEAD/envelope construction, size ceiling, crash recovery journal, and backup KEK rewrap.
3. SSH/OpenSSH and Apple Security parser/library choice, limits, licensing, and sanitizer harness.

## Approval Gate

Implementation may start with Phase 1 containment and the three spikes. It must not start type discovery,
file-backed import, or CloudKit artifact writes until the corresponding P0 contracts are proven by the
specified fixtures. No confirmed P0/P1 red-team finding is intentionally left unresolved in the plan;
the spikes are explicit proof gates rather than hidden assumptions.

