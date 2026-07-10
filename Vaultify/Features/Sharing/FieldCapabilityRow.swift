import SwiftUI

/// One field row in the share-config sheet: kind icon + label + a
/// kind-constrained capability SWITCH (V1.2 decision V6: both capability
/// kinds are binary, so a Toggle — popups are reserved for genuinely
/// multi-option controls). The mapping can only ever produce what the type
/// system allows (user-locked decision 2): TOTP → none/askEachTime; value
/// fields → none/shared. Extra-protected (Level-2) and attachment fields
/// render disabled — they are not shareable.
struct FieldCapabilityRow: View {
    let field: DynamicField
    @Binding var capability: FieldCapability
    /// Hand-over modes (TOTP seed) never write directly: the parent shows the
    /// irreversibility warning (INV-08) and applies the capability on confirm.
    var requestHandOver: (FieldCapability) -> Void = { _ in }

    private var shareable: Bool {
        !(field.isExtraProtected || field.kind == .fileRef)
    }

    var body: some View {
        HStack(spacing: Space.s3) {
            PolarisIcon(field.kind.iconAsset, size: Metric.iconInline)
                .themedForeground(.iconSecondary)
            VStack(alignment: .leading, spacing: Space.s1) {
                fieldLabelText(field.label)
                    .vaultType(.body)
                    .themedForeground()
                    .lineLimit(1)
                if !shareable {
                    Text(field.isExtraProtected ? "Extra-protected, not shareable"
                                                : "Attachments aren’t shareable")
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
                    // Three modes need a real menu (V6's "binary → Toggle"
                    // rule no longer applies to TOTP since seed hand-over).
                    Menu {
                        Button { capability = .totp(.none) } label: { Text("Off") }
                        Button { capability = .totp(.askEachTime) } label: { Text("Ask each time") }
                        Button { requestHandOver(.totp(.shared)) } label: {
                            Label("Hand over secret…", image: Icons.alert)
                        }
                    } label: {
                        HStack(spacing: Space.s1) {
                            Text(totpModeTitle).vaultType(.callout)
                            PolarisIcon(Icons.chevronDown, size: 14)
                        }
                        .themedForeground(.accent)
                    }
                } else {
                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                }
            }
        }
        .frame(minHeight: Metric.hitMin)
        .opacity(shareable ? 1 : 0.5)
    }

    private var isTOTP: Bool {
        if case .totp = capability { return true }
        return false
    }

    private var totpModeTitle: LocalizedStringKey {
        switch capability {
        case .totp(.askEachTime): "Ask each time"
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
                case .totp: capability = .totp(enabled ? .askEachTime : .none)
                case .value: capability = .value(enabled ? .shared : .none)
                case .passkey: capability = .passkey(enabled ? .askEachTime : .none)
                }
            })
    }
}
