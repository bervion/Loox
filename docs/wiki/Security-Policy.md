# Security Policy

Loox stores people's passwords, passkeys and recovery material, so security reports get priority over everything else. The authoritative policy is [SECURITY.md](https://github.com/bervion/Loox/blob/main/SECURITY.md) in the repository.

## Reporting a vulnerability

**Do not open a public issue, discussion or pull request for a vulnerability.**

Report it privately by email to **support@looxpassword.com** with the subject `Security report`. When the repository's **Security** tab offers **Report a vulnerability**, you can use GitHub's private reporting instead.

Include the affected component (app, AutoFill extension, Safari extension, Mac app, or a Loox service such as Loox Link, Quick View or Private Email) and the version or commit, the impact and steps to reproduce, and your device, OS version and any non-default settings that matter. Use test data only; never send real vault contents, master passwords, recovery keys or tokens.

## Supported versions

The latest App Store release and the `main` branch. Older releases are not supported; please update first.

## Scope

In scope: vault encryption, key derivation and key wrapping; unlock, biometric and recovery flows including the extensions; anything that lets data leave the device in a way [[Privacy and Data]] does not describe; sharing, Loox Link, Quick View and Private Email on the client and the service side.

Out of scope: attacks that need a jailbroken device or an already unlocked device in the attacker's hands; missing hardening headers or best practices without a demonstrated impact; social engineering and denial of service against Loox services.

## What to expect

The report is acknowledged, reproduction is confirmed, and you are kept updated while a fix is prepared. Disclosure is coordinated with you and you are credited in the release notes unless you prefer to stay anonymous. Good-faith research that tests only your own devices, vaults and accounts and gives reasonable time for a fix is welcome.
