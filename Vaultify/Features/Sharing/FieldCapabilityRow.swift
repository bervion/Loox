import SwiftUI

/// One field row in the share-config sheet: kind icon + label + a
/// kind-constrained capability control. Value fields are binary, so a Toggle
/// (V1.2 decision V6); TOTP has four modes, so a menu (off, ask each time,
/// always show code, hand over). The mapping can only ever produce what the
/// type system allows (user-locked decision 2). Extra-protected (Level-2) and
/// attachment fields render disabled — they are not shareable.
struct FieldCapabilityRow: View {
    let field: DynamicField
    /// The owning item, when the sheet has it — enables full resolver policy
    /// (template + role). Without it the kind-shape policy still applies.
    var item: VaultItem? = nil
    let capability: FieldCapability
    /// Every mode the owner picks, hand-over included. Required on purpose: it
    /// used to be an optional hand-over hook with a no-op default, so a sheet
    /// that forgot to pass it compiled fine and silently dropped "Hand over".
    /// `ShareCapabilityDraft` decides which picks need the INV-08 confirmation.
    let onSelect: (FieldCapability) -> Void

    /// Central policy, not a local denylist: key material (protected multiline —
    /// SSH private keys, recovery codes) is not offerable in v1 alongside the
    /// existing Level-2 and attachment exclusions.
    private var shareable: Bool {
        if let item {
            return ItemCapabilityResolver.capabilities(for: field, in: item).approvalShare
                // TOTP is offerable as a ROW (its tri-state flow decides the
                // mode); the resolver's value-share bit doesn't model that.
                || (field.kind == .totp && !field.isExtraProtected)
        }
        return TransitionalSharePolicy.approvalShareAllows(field)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            controlRow
            if shareable, capability == .totp(.alwaysShowCode) {
                // The mode's whole promise, full width under the row (beside
                // the menu it would wrap into a sliver): what they see, what
                // stays hidden, when it leaves their device, and the version it
                // needs (older apps fail closed on the new mode).
                Text("They see the current code at any time. Loox never shows them the secret, and removes it from their device when you change this option or stop sharing. They need the latest version of Loox.")
                    .vaultType(.footnote)
                    .themedForeground(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Metric.iconInline + Space.s3)
            }
        }
        .opacity(shareable ? 1 : 0.5)
    }

    private var controlRow: some View {
        HStack(spacing: Space.s3) {
            VaultIcon(field.kind.iconAsset, size: Metric.iconInline)
                .themedForeground(.iconSecondary)
            VStack(alignment: .leading, spacing: Space.s1) {
                fieldLabelText(field.label)
                    .vaultType(.body)
                    .themedForeground()
                    .lineLimit(1)
                if !shareable {
                    Text(notShareableReason)
                        .vaultType(.footnote)
                        .themedForeground(.secondary)
                } else {
                    // The control's meaning per kind, since it is unlabeled:
                    // what enabling grants (or the current TOTP mode).
                    Text(isTOTP ? totpModeTitle : "Shared")
                        .vaultType(.footnote)
                        .themedForeground(.secondary)
                }
            }
            Spacer()
            if shareable {
                if isTOTP {
                    // Several modes need a real menu (V6's "binary → Toggle"
                    // rule no longer applies to TOTP since seed hand-over).
                    Menu {
                        Button { onSelect(.totp(.none)) } label: { Text("Off") }
                        Button { onSelect(.totp(.askEachTime)) } label: { Text("Ask each time") }
                        Button { onSelect(.totp(.alwaysShowCode)) } label: { Text("Always show code") }
                        Button { onSelect(.totp(.shared)) } label: {
                            Label { Text("Hand over secret…") } icon: { VaultIcon(Icons.alert) }
                        }
                    } label: {
                        HStack(spacing: Space.s1) {
                            Text(totpModeTitle).vaultType(.callout)
                            VaultIcon(Icons.chevronDown, size: 14)
                        }
                        .themedForeground(.accentText)
                    }
                } else {
                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                }
            }
        }
        .frame(minHeight: Metric.hitMin)
    }

    private var notShareableReason: LocalizedStringKey {
        if field.isExtraProtected { return "Extra-protected, not shareable" }
        if field.kind == .fileRef { return "Attachments aren’t shareable" }
        return "Key material isn’t shareable"
    }

    private var isTOTP: Bool {
        if case .totp = capability { return true }
        return false
    }

    private var totpModeTitle: LocalizedStringKey {
        switch capability {
        case .totp(.askEachTime): "Ask each time"
        case .totp(.alwaysShowCode): "Always show code"
        case .totp(.shared): "Secret handed over"
        default: "Off"
        }
    }

    /// ON ↔ the single grantable capability for this field kind.
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: {
                switch capability {
                case .totp(let c): return c == .askEachTime
                case .value(let c): return c == .shared
                // Passkey rows get dedicated UI in the capability-v2 phase;
                // until then the toggle maps to the ask-each-time default.
                case .passkey(let c): return c != .none
                }
            },
            set: { enabled in
                switch capability {
                case .totp: onSelect(.totp(enabled ? .askEachTime : .none))
                case .value: onSelect(.value(enabled ? .shared : .none))
                case .passkey: onSelect(.passkey(enabled ? .askEachTime : .none))
                }
            })
    }
}
