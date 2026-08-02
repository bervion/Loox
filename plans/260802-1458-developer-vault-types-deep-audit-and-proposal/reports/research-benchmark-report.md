# Product and Platform Benchmark

Date: 2026-08-02  
Method: official vendor/product documentation and platform documentation; used to set product scope,
not to copy another product's UI.

## Benchmark Conclusions

1. A useful SSH item is not merely two text areas. Mature products model public/private material,
   fingerprint, import formats, and gated use/export.
2. “Secrets” are semantically different from login passwords. API keys, environment values, and
   database strings need key/value or typed-secret workflows without password AutoFill/scoring.
3. Seamless Git/SSH terminal use requires a process on the machine running Git: an SSH agent,
   credential helper, or CLI secret injection. A vault UI can manage and transfer assets but
   must not market copy/snippet actions as full Git integration.
4. Apple developer credentials are a strong differentiation opportunity because `.p8` keys are
   high-value, downloaded once, and combined with stable public identifiers; signing assets also have
   meaningful expiry/fingerprint metadata.
5. Binary credentials need file-oriented durability and explicit export controls, not a string field
   containing a sidecar pointer.

## SSH and Git

Bitwarden's SSH item includes private key, public key, and fingerprint, documents OpenSSH/PKCS#8
imports, and positions actual SSH-agent use on desktop. This validates both the semantic fields and the
platform boundary: [Bitwarden SSH documentation](https://bitwarden.com/help/about-ssh/).

1Password similarly treats the SSH agent as a local process whose key use is authorized through the
desktop app; its security description emphasizes that private keys are not kept available while the app
is locked: [1Password SSH Agent security](https://www.1password.dev/ssh/agent/security),
[getting started](https://www.1password.dev/ssh/get-started/).

Git's own documentation describes credential helpers as programs Git invokes and lists platform helpers.
The plain credential store persists secrets unencrypted, illustrating why “copy token to a file” is not a
safe integration strategy: [Git credential helpers](https://git-scm.com/doc/credential-helpers.html),
[credential store](https://git-scm.com/docs/git-credential-store.html).

The `ssh-keygen` manual is the interoperability oracle for supported algorithms, fingerprint output,
and golden test vectors: [OpenBSD ssh-keygen](https://man.openbsd.org/ssh-keygen).

### Vaultify implication

- iOS v1: import, inspect, fingerprint, link, copy public material, and gated export.
- Future signed Mac helper/CLI: agent/helper or secret injection with a separate threat model; this is
  distinct from the existing macOS app/AutoFill target.
- Do not implement encrypted OpenSSH parsing/serialization from scratch.

## API and Environment Secrets

Bitwarden Secrets Manager defines secrets as sensitive key/value pairs such as API keys, environment
variables, and database connection strings rather than browser logins:
[Bitwarden secrets](https://bitwarden.com/help/secrets/).

1Password CLI demonstrates that secret injection into scripts is a separate local CLI workflow, not a
mobile-vault behavior: [1Password CLI secret references](https://developer.1password.com/docs/cli/secrets-scripts/).

### Vaultify implication

API Secret gets provider/environment/endpoint/scopes/expiry and controlled secret-bearing header/env snippets. It does not
inherit password AutoFill, password reuse/HIBP, or Safari bridge eligibility. A future CLI could consume
the same role IDs without changing the encrypted item model.

## Apple Developer Credentials

Apple documents certificates, identifiers, and profiles as the signing/deployment primitives:
[Apple developer glossary](https://developer.apple.com/help/glossary/certificates-identifiers-profiles/).

App Store Connect API keys consist of key identifiers and a private key that can only be downloaded once;
Apple advises secure storage and revocation if compromised:
[App Store Connect API](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api).

Xcode can export signing certificates and provisioning profiles as a developer-profile bundle, and
signing private keys otherwise live in the Keychain:
[Xcode account export](https://help.apple.com/xcode/mac/current/en.lproj/dev8a2822e0b.html).

Apple's profile documentation confirms the first-class metadata users care about, including App ID,
certificates, devices, and profile purpose:
[create a development provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile/).

### Vaultify implication

- Prioritize App Store Connect `.p8`, APNs `.p8`, signing `.p12`, certificate, and provisioning profile.
- Store exact original artifact; parse bounded public metadata locally.
- Distinguish local expiry/inspection from live revocation/status.
- Never install into the system Keychain or mutate Xcode signing automatically.

## Recommended Positioning

“A private developer credential vault for iPhone” is credible when the product can:

- keep developer identities and artifact bytes offline-first;
- explain what a credential is, where it is used, and when it expires;
- link Git accounts, SSH auth/signing keys, API secrets, and Apple signing assets;
- recover all bytes from encrypted backup and optional device sync;
- deliberately transfer/export an asset under re-authentication.

Avoid claims such as “SSH agent”, “Git integration”, “Xcode signing management”, or “secure file vault”
until the corresponding platform component and lifecycle gates actually exist.

## Competitive Differentiation for Vaultify

- iOS-developer-first templates and metadata instead of a generic custom field form.
- Offline-first with no Vaultify backend; optional CloudKit remains a user choice.
- Strict capability isolation: developer secrets cannot silently become browser passwords.
- Linked credential graph avoids stale duplicate PAT/key material.
- Honest portability state for every artifact: local-only, syncing, synced, unavailable, or deleted.
