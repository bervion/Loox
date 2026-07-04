# Memory Index

- [Localization catalog convention](vaultify-localization-catalog-convention.md) — key IS the EN source; only `vi` needed; clipboard toast labels are untranslated literals
- [TOTP/Home privacy model](vaultify-totp-home-privacy-model.md) — two-layer secret protection (global PrivacyShield + .privacySensitiveContents); lock-on-background clears repo
- [Sync merge model](vaultify-sync-merge-model.md) — two-gate LWW (content/meta timestamps), changeTag short-circuit, snapshot markSynced; known push-first divergence gap
