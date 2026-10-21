# Security Policy

Loox stores people's passwords, passkeys and recovery material, so security reports get priority over everything else.

## Supported versions

| Version | Supported |
|---|---|
| Latest App Store release | Yes |
| `main` branch | Yes |
| Older releases | No, please update first |

## Reporting a vulnerability

**Do not open a public issue, discussion or pull request for a vulnerability.**

Report it privately by email to **support@looxpassword.com** with the subject `Security report`. When the repository's **Security** tab offers **Report a vulnerability**, you can use GitHub's private reporting instead.

Please include:

- the affected component (app, AutoFill extension, Safari extension, Mac app, or a Loox service such as Quick Link, Quick View or Private Email) and the version or commit
- the impact and the steps to reproduce, ideally with a proof of concept
- your device, OS version and any non-default settings that matter

Use test data only. Never send real vault contents, master passwords, recovery keys or tokens.

## What to expect

- We acknowledge the report, confirm whether it reproduces and keep you updated while a fix is prepared.
- We coordinate the disclosure date with you and credit you in the release notes unless you prefer to stay anonymous.

## Scope

In scope:

- vault encryption, key derivation and key wrapping (`VaultifyCore/Crypto`, `VaultifyCore/CArgon2`)
- unlock, biometric and recovery flows, including the AutoFill and Safari extensions
- anything that lets data leave the device in a way the [privacy table in the README](README.md#what-leaves-your-device) does not describe
- sharing, Quick Link, Quick View and Private Email, on the client and the service side

Out of scope:

- attacks that need a jailbroken device or an already unlocked device in the attacker's hands
- missing hardening headers or best practices without a demonstrated impact
- social engineering and denial of service against Loox services

## Safe harbor

Good-faith research that follows this policy is welcome. Test only against your own devices, vaults and accounts, do not access other people's data and give us reasonable time to fix the issue before you publish.
