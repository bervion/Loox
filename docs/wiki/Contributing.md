# Contributing

Issues and pull requests are welcome. The full guide lives in the repository: [CONTRIBUTING.md](https://github.com/bervion/Loox/blob/main/CONTRIBUTING.md).

The short version:

- **Bugs:** open an issue with deterministic steps and synthetic data. Never paste real vault contents, recovery keys or tokens.
- **Features and larger changes:** open an issue first so the approach can be agreed before you write code.
- **Security issues:** do not open an issue. Follow the [[Security Policy]].
- **Setup:** `mise install`, then `mise exec -- tuist generate`. Never commit the generated `*.xcodeproj`, `*.xcworkspace` or `Derived/`. See [[Building from Source]].
- **Rules reviews enforce:** every user-facing string localized in English, Vietnamese and Japanese; design tokens and components instead of hard-coded visuals; icons through `VaultIcon` with no SF Symbols newer than iOS 17.3; the iOS 17.3 / macOS 15 platform floor; `nonisolated` crypto and data types; analytics events only from the typed catalog; tests, including known-answer vectors, for any change under `VaultifyCore/Crypto` or `VaultifyCore/CArgon2`.
- **Test before you push:** `mise exec -- make check` and `mise exec -- make test TEST_TARGETS=VaultifyTests`.
- **Commits and pull requests:** Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`), one focused change per pull request targeting `main`, with what changed, why and how you tested it.
- **License of contributions:** GPL-3.0, with permission for the maintainer to distribute the contribution as part of Loox through Apple's App Store.
