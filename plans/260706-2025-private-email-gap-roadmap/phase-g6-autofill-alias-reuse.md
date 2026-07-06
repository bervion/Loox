# G6 — AutoFill existing-alias reuse

Priority: low. Status: pending. Depends: G2/G4.

## Scope (V1 = reuse only, per proposal §25)

- Extension surfaces existing bound aliases for matching sites (registrable-domain match via
  the shared VaultifyCore helper from G4); alias fills as the credential username where the
  login item carries it.
- Multi-account same-site: extension's item picker already disambiguates by item — verify the
  alias-bearing items render distinctly (label subtitle).
- **No in-extension provisioning** V1: two signed network calls in a constrained extension is
  a flaky-flow risk; "Create in Loox" deep-link instead. Revisit only after real-device
  session-lifetime measurement.

## Success

- Extension target compiles with shared helpers (`make check` covers both targets).
- No relay network calls from the extension in V1 (grep-audit RelayAPIClient references in
  VaultifyAutoFill/).
