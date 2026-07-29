import SwiftUI

/// Turn-off could complete its writes and still find sealed fields (an item the
/// repository refused to rewrite, or a field sealed under a different key).
/// Destroying the wrap then would make that ciphertext permanent, so the flow
/// aborts with this instead — the Extra Password stays on and usable.
private enum Level2TurnOffError: LocalizedError {
    case sealedFieldsRemain
    var errorDescription: String? {
        appString("Some protected fields could not be unlocked, so the Extra Password was kept on. Try again.")
    }
}

/// Set, change, or turn off the Extra Password — the second password that keeps
/// selected fields sealed even while the vault is unlocked. Styled like the
/// onboarding password step (plain page, capsule fields, bottom CTA) with the
/// Security swirl playing its one-shot dot reveal above the form.
struct Level2SettingsView: View {
    /// Presented as a nested SETUP sheet (from Protect Field), the caller needs
    /// the key this screen just minted — clearing it on dismiss would throw away
    /// the very thing the user came here to create. The standalone Settings entry
    /// keeps clearing, so a verify-then-leave never arms the whole app.
    var retainsFreshKey: Bool = false

    @Environment(AppEnvironment.self) private var env
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Mode { case setup, overview, change, turnOff }
    @State private var mode: Mode = .setup
    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?
    @State private var confirmTurnOff = false
    /// True once THIS visit created the Extra Password (and therefore holds a
    /// freshly minted key). A verification typed for change/turn-off never sets it.
    @State private var didProvisionKey = false

    private var meetsLength: Bool { newPassword.count >= 6 }
    private var matches: Bool { !confirm.isEmpty && newPassword == confirm }

    private var canSubmit: Bool {
        guard !busy else { return false }
        switch mode {
        case .setup: return meetsLength && matches
        case .change: return !current.isEmpty && meetsLength && matches
        case .turnOff: return !current.isEmpty
        case .overview: return false
        }
    }

    /// Level2-sealed fields and the items carrying them — the honest scope of a
    /// turn-off. Custom-code fields don't depend on the Extra Password and are
    /// never touched.
    private var protectedTally: (fields: Int, items: Int) {
        var fields = 0, items = 0
        for item in env.repository.items {
            let n = item.fields.filter {
                $0.isExtraProtected && SecretGuard.scheme(of: $0.value) == .level2
            }.count
            if n > 0 { items += 1; fields += n }
        }
        return (fields, items)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                content
                if let error {
                    Text(verbatim: error).vaultType(.footnote).foregroundStyle(VaultColors.strengthWeak)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s6)
            .vaultContentWidth(.form)
        }
        // Same Apple-Account idiom as the master-password step: a plain page
        // with capsule fields — also what the swirl's dot mask reads best on.
        .background(Color(rgb: theme.background).ignoresSafeArea())
        // Dismiss the keyboard on scroll or when an empty area is tapped, matching
        // the onboarding password steps (field/button taps keep their own
        // handling — children win over this gesture).
        .scrollDismissesKeyboard(.immediately)
        .onTapGesture { PlatformAppearance.dismissKeyboard() }
        .navigationTitle("Extra Protection")
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mode == .change || mode == .turnOff {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { switchTo(.overview) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if mode != .overview {
                // ONLY the CTA ignores the keyboard: it holds the bottom edge
                // instead of riding up under the thumb. The scroll view keeps its
                // keyboard inset, which matters most here — change/turn-off
                // autofocus their secure field, so the keyboard is up before the
                // user touches anything and an un-inset field would be typed blind.
                BrandCapsuleCTA(title: ctaTitle, enabled: canSubmit, busy: busy) {
                    Task { await submit() }
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .confirmationDialog("Turn off Extra Password?", isPresented: $confirmTurnOff,
                            titleVisibility: .visible) {
            Button("Turn Off and Unseal Fields", role: .destructive) {
                Task { await turnOff() }
            }
        } message: {
            Text("Every field protected with the Extra Password becomes visible like a normal field.")
        }
        .onAppear { mode = env.session.hasLevel2 ? .overview : .setup }
        // A verify here (turn-off typed, then cancelled) must not leave every
        // protected field one tap from visible across the app. The one exception
        // is a nested setup sheet: its caller is waiting for the key it minted.
        .onDisappear {
            guard !(retainsFreshKey && didProvisionKey) else { return }
            env.session.clearLevel2Key()
        }
        .analyticsScreen("extra_protection")
    }

    // MARK: Pieces

    /// The Security swirl (one-shot dots radiating from the shield, then still)
    /// + per-mode title and subtitle.
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            LooxSwirlAnimationView(mode: .reveal,
                                   centerIcon: "dt_shield_keyhole",
                                   centerTint: env.theme.active.color(.accent))
                .frame(width: 150, height: 150)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s4)
            Text(title)
                .vaultType(.screenTitle)
            subtitleText
                .vaultType(.subhead).themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: LocalizedStringKey {
        switch mode {
        case .setup: return "Set your Extra Password"
        case .overview: return "Extra Protection is on"
        case .change: return "Change Extra Password"
        case .turnOff: return "Turn Off Extra Password"
        }
    }

    @ViewBuilder private var subtitleText: some View {
        switch mode {
        case .setup:
            Text("A second password that keeps chosen fields sealed even while the vault is unlocked.")
        case .overview:
            // Grammar branches by count — "1 fields in 1 items" is not a
            // sentence this screen is allowed to show.
            let tally = protectedTally
            if tally.fields == 1 {
                Text("One field is protected.")
            } else if tally.fields > 1, tally.items == 1 {
                Text("\(tally.fields) fields in one item are protected.")
            } else if tally.fields > 1 {
                Text("\(tally.fields) fields in \(tally.items) items are protected.")
            } else {
                Text("No fields are protected yet. Open an item and choose Protect from a field's menu.")
            }
        case .change:
            Text("Enter your current Extra Password, then choose a new one. Protected fields stay sealed.")
        case .turnOff:
            let tally = protectedTally
            if tally.fields == 1 {
                Text("Enter your Extra Password. The protected field will return to normal visibility.")
            } else if tally.fields > 1 {
                Text("Enter your Extra Password. \(tally.fields) protected fields will return to normal visibility.")
            } else {
                Text("Nothing is protected right now. Turning off only removes the password.")
            }
        }
    }

    /// Field titles stay PLAIN ("Password", not "Extra Password"): the screen
    /// title and subtitle above already establish which password this form is
    /// for, and repeating it on every row read as three different secrets.
    @ViewBuilder private var content: some View {
        switch mode {
        case .setup:
            PasswordCreationGroup(password: $newPassword, confirm: $confirm,
                                  passwordTitle: "Password",
                                  confirmTitle: "Re-enter password")
            if !confirm.isEmpty && !matches {
                Text("Passwords don’t match")
                    .vaultType(.caption).foregroundStyle(VaultColors.strengthWeak)
            }
            infoNote
        case .overview:
            actionList
        case .change:
            currentPasswordCapsule
            PasswordCreationGroup(password: $newPassword, confirm: $confirm,
                                  passwordTitle: "New password",
                                  confirmTitle: "Re-enter password")
            if !confirm.isEmpty && !matches {
                Text("Passwords don’t match")
                    .vaultType(.caption).foregroundStyle(VaultColors.strengthWeak)
            }
        case .turnOff:
            currentPasswordCapsule
        }
    }

    /// The manage state's two actions, in one capsule group.
    private var actionList: some View {
        VStack(spacing: 0) {
            actionRow("Change Extra Password", destructive: false) { switchTo(.change) }
            Divider().padding(.leading, Space.s5)
            actionRow("Turn Off Extra Password", destructive: true) { switchTo(.turnOff) }
        }
        .background(Color(rgb: theme.secondaryBackground),
                    in: RoundedRectangle(cornerRadius: 27, style: .continuous))
    }

    private func actionRow(_ title: LocalizedStringKey, destructive: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .vaultType(.body)
                    .foregroundStyle(destructive ? env.theme.active.color(.destructive)
                                                 : env.theme.active.color(.primary))
                Spacer()
                VaultIcon(Icons.chevronRight, size: 14)
                    .themedForeground(.iconSecondary)
            }
            .padding(.horizontal, Space.s5)
            .frame(height: 54)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Single capsule row for the current password (change / turn-off modes).
    private var currentPasswordCapsule: some View {
        RevealableSecureField(title: "Current password", text: $current,
                              inList: true, autofocus: true)
            .padding(.horizontal, Space.s5)
            .frame(height: 54)
            .background(Color(rgb: theme.secondaryBackground),
                        in: RoundedRectangle(cornerRadius: 27, style: .continuous))
    }

    /// Duotone info glyph + the no-recovery note, mirroring the master step.
    private var infoNote: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Image("HandshakeDuotone")
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
            Text("Loox asks for it only when you reveal a protected field. If you forget it, protected fields cannot be recovered.")
                .vaultType(.footnote).themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.s2)
    }

    /// Setup and change both end a password FORM, so their button is the form's
    /// plain confirm. Turn-off is a destructive action rather than a form, so it
    /// keeps naming what it destroys.
    private var ctaTitle: LocalizedStringKey {
        switch mode {
        case .setup, .change: return "Confirm password"
        case .turnOff: return "Turn Off Extra Password"
        case .overview: return ""
        }
    }

    // MARK: Actions

    private func switchTo(_ newMode: Mode) {
        error = nil
        current = ""; newPassword = ""; confirm = ""
        withAnimation(.vault(.spring(response: 0.4, dampingFraction: 0.85),
                             reduceMotion: reduceMotion)) { mode = newMode }
    }

    private func submit() async {
        guard canSubmit else { return }
        busy = true; error = nil
        do {
            switch mode {
            case .setup:
                try await env.session.setLevel2Password(newPassword)
                // The key this just minted is what a nested caller is waiting for.
                didProvisionKey = true
                Haptics.success()
                switchTo(.overview)
            case .change:
                try await env.session.changeLevel2Password(current: current, new: newPassword)
                Haptics.success()
                switchTo(.overview)
            case .turnOff:
                // Prove the password BEFORE the destructive confirmation, so a
                // typo surfaces here instead of aborting mid-dialog.
                try await env.session.unlockLevel2(password: current)
                confirmTurnOff = true
            case .overview:
                break
            }
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
        busy = false
    }

    /// Decrypt every level2-sealed field back to plaintext, then drop the wrap.
    /// The password was verified in `submit()`, so `level2Key` is present.
    ///
    /// Order is load-bearing: a read-only preflight unseals every field across
    /// live, archived, AND trashed items in memory first; writes happen only
    /// after the whole preflight succeeded; and the wrap key is destroyed only
    /// after a re-scan confirms no level2 ciphertext remains. An abort at any
    /// point leaves the key intact, and a retry skips already-unsealed fields,
    /// so a crash mid-way can never strand unrecoverable ciphertext.
    private func turnOff() async {
        busy = true; error = nil
        do {
            guard let key = env.session.level2Key else { throw AuthError.locked }
            // Shared projections are the owner's sealed payload, not ours to rewrite.
            let ownItems = { (env.repository.items + env.repository.archived + env.repository.trashed)
                .filter { $0.sharedOrigin == nil && !$0.id.hasPrefix("shared::") } }
            let unsealed = try Level2Disable.unsealed(ownItems(), l2Key: key.bytes)
            try AnalyticsEngine.shared.runSuppressed {
                for item in unsealed { try env.repository.update(item) }
            }
            guard !Level2Disable.hasSealedLeftovers(ownItems()) else {
                throw Level2TurnOffError.sealedFieldsRemain
            }
            env.session.removeLevel2Wrap()
            // The wrap is gone, so there is no minted key left to hand back.
            didProvisionKey = false
            Haptics.success()
            switchTo(.setup)
        } catch {
            self.error = error.localizedDescription
            Haptics.error()
        }
        busy = false
    }
}

/// Pure steps of the Extra Password turn-off transaction, split out so the
/// abort-before-write guarantee can be proven in unit tests without a store.
nonisolated enum Level2Disable {
    /// Preflight: every level2-sealed field across the given items, unsealed in
    /// memory. Throws on the FIRST failure — the caller must not have written
    /// anything yet, so an abort here leaves the vault untouched.
    static func unsealed(_ items: [VaultItem], l2Key: [UInt8]) throws -> [VaultItem] {
        var out: [VaultItem] = []
        for var item in items {
            var touched = false
            for index in item.fields.indices
            where item.fields[index].isExtraProtected
                && SecretGuard.scheme(of: item.fields[index].value) == .level2 {
                item.fields[index].value = try SecretGuard.openLevel2(
                    item.fields[index].value, l2Key: l2Key)
                item.fields[index].guard2 = false
                touched = true
            }
            if touched { out.append(item) }
        }
        return out
    }

    /// Post-write check: true while any level2 ciphertext survives. The wrap key
    /// must not be destroyed as long as this returns true — that ciphertext
    /// would become permanently unreadable.
    static func hasSealedLeftovers(_ items: [VaultItem]) -> Bool {
        items.contains { item in
            item.fields.contains {
                $0.isExtraProtected && SecretGuard.scheme(of: $0.value) == .level2
            }
        }
    }
}
