# Outbound-Surface Matrix (Release A freeze)

Date: 2026-08-02
Status: frozen for the eight shipped categories. Every future type/role change must update
this table and its capability tests before enablement.

Legend: Y = value can reach the surface. M = masked/metadata only. N = never. RA = after
explicit reveal/re-auth interaction.

| Surface | login | note | card | identity | sshKey | recoveryCodes | securityQuestions | custom |
|---|---|---|---|---|---|---|---|---|
| Detail screen (before reveal) | M (password masked) | Y (note body) | M (number/CVV/PIN masked) | Y except protected ID | M (private key masked) | M (codes masked) | M (answers masked) | per-field `protected` |
| Detail screen (after reveal) | RA | — | RA | RA | RA (auto-conceals: timeout/background/navigation) | RA | RA | RA |
| Accessibility tree (masked) | "Hidden value" | value | "Hidden value" | mixed | "Hidden value" | "Hidden value" | "Hidden value" | per-field |
| Clipboard (copy) | Y (sensitive: local-only + expiry) | Y | Y (sensitive) | Y | Y (sensitive, local-only + expiry) | Y (sensitive) | Y (sensitive) | per-field |
| Large Type viewer | Y | N (no menu) | Y | Y | N (denied for protected multiline) | N | Y | per-field |
| Login AutoFill (QuickType) | Y (username/password/totp) | N | N | N (profile fill is separate) | N | N | N | N |
| Safari extension `getFillPayload` | Y (login/card/identity mapping) | N | Y | Y | N | N | N | N |
| Password audit / HIBP / strength | Y (`.password` fields) | N | N | N | N | N | N | `.password` fields only |
| Quick Link (LooxLink) | Y (opt-in fields) | Y (opt-in) | Y (opt-in) | Y (opt-in) | public key only — private key DENIED | DENIED | Y (opt-in) | protected multiline DENIED |
| Quick View (QR) | same policy as Quick Link (shares `shareableFields`) | | | | | | | |
| Approval / Space sharing | Y (owner opt-in per field) | body opt-in (plain only) | Y | Y | private key NOT OFFERABLE | NOT OFFERABLE | Y | protected multiline NOT OFFERABLE |
| Encrypted backup | Y (sealed) | Y | Y | Y | Y | Y | Y | Y (unknown category raw preserved) |
| CSV export | username/password/url/notes | notes | N (not mapped) | N | N | N | N | N |
| CloudKit item record | sealed blob only (no plaintext fields) | | | | | | | |
| Search index (in-memory) | non-protected fields + tags | body excluded? (protected excluded) | non-protected | non-protected | public key searchable, private N | N | questions Y answers N | per-field |
| Telemetry (GA4) | category rawValue + buckets ONLY — never values/names/hosts | | | | | | | |

Invariants pinned by tests as of this freeze:

- `DetailValuePresentationTests` — protected multiline can never render Markdown/plain.
- `TransitionalSharePolicyTests` — Quick Link/Quick View/Approval key-material denial.
- `SharedItemsProjectionTests` — category + protection survive owner→recipient projection;
  missing metadata fails closed to a masked secret kind.
- `UnknownCategoryRoundTripTests` — unknown categories decode, present generically, and
  re-encode losslessly (repository, backup).
- `WebExtensionReader`/`VaultReader` tests — Safari/AutoFill remain login-shaped surfaces;
  `getFillPayload` is the only value-returning native command (test-enforced).

Gaps accepted at freeze (tracked for Phase 2+):

- `.password`-kind fields inside non-login categories still enter password audit
  (kind-based inference); Phase 2 routes audit eligibility through the capability resolver.
- Unknown `FieldKind` still decodes to `.text` and re-encodes lossily; Phase 2 makes the
  raw kind round-trip alongside field semantics.
- Reveal re-auth is behavioral (UI policy), not cryptographic; Level-2 (`guard2`) remains
  the only per-field crypto boundary until Phase 3 artifact DEKs.
