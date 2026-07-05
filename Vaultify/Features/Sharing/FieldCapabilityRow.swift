import SwiftUI

/// One field row in the share-config sheet: kind icon + label + a
/// kind-constrained capability picker. The picker can only ever offer what
/// the type system allows (user-locked decision 2): TOTP → none/askEachTime;
/// value fields → none/shared. Extra-protected (Level-2) and attachment
/// fields render disabled — they are not shareable.
struct FieldCapabilityRow: View {
    let field: DynamicField
    @Binding var capability: FieldCapability

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
                    Text(field.isExtraProtected ? "Extra-protected — not shareable"
                                                : "Attachments aren’t shareable")
                        .vaultType(.footnote)
                        .themedForeground(.secondary)
                }
            }
            Spacer()
            if shareable { picker }
        }
        .frame(minHeight: Metric.hitMin)
        .opacity(shareable ? 1 : 0.5)
    }

    @ViewBuilder private var picker: some View {
        switch capability {
        case .totp(let current):
            Picker("", selection: Binding(
                get: { current },
                set: { capability = .totp($0) })) {
                Text("Off").tag(TOTPFieldCapability.none)
                Text("Ask each time").tag(TOTPFieldCapability.askEachTime)
            }
            .pickerStyle(.menu)
            .labelsHidden()
        case .value(let current):
            Picker("", selection: Binding(
                get: { current },
                set: { capability = .value($0) })) {
                Text("Off").tag(ValueFieldCapability.none)
                Text("Shared").tag(ValueFieldCapability.shared)
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}
