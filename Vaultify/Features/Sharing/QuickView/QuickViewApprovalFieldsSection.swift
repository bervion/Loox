import SwiftUI

/// SAS card + expiry countdown + per-field toggles for the Quick View
/// approval sheet — split out from `QuickViewApprovalSheet` to keep each
/// file focused on one concern (field-selection UI vs. the ceremony's state
/// machine rendering).
struct QuickViewApprovalFieldsSection: View {
    @Bindable var flow: QuickViewApprovalFlowModel
    let item: VaultItem
    let sas: String
    let expiresAtUnixMs: Int64

    var body: some View {
        VStack(spacing: Space.s5) {
            sasCard
            countdown
            fieldTogglesCard
        }
    }

    private var sasCard: some View {
        VStack(spacing: Space.s2) {
            Text("Safety phrase").vaultType(.sectionLabel).themedForeground(.secondary)
            Text(verbatim: sas)
                .font(.vaultCode(size: 22))
                .themedForeground()
            Text("Make sure this matches the phrase shown on your computer.")
                .vaultType(.footnote).themedForeground(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
    }

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Double(expiresAtUnixMs) / 1000 - context.date.timeIntervalSince1970)
            HStack(spacing: Space.s2) {
                PolarisIcon(Icons.clock, size: Metric.iconInline).themedForeground(.secondary)
                Text("Expires in \(Int(remaining)) seconds")
                    .vaultType(.footnote).themedForeground(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var fieldTogglesCard: some View {
        let shareable = LooxLinkEnvelope.shareableFields(of: item)
        // Only offer the 2FA toggle for a readable (non-guard2) TOTP seed —
        // an extra-protected TOTP can never be handed off (its value is
        // SecretGuard ciphertext), so the row must not appear.
        let hasTOTPSeed = (item.totpField.map { !$0.isExtraProtected }) ?? false
        return VStack(spacing: 0) {
            ForEach(Array(shareable.enumerated()), id: \.element.id) { index, field in
                fieldToggleRow(field: field)
                if index < shareable.count - 1 || hasTOTPSeed {
                    Divider().padding(.leading, Space.gutter)
                }
            }
            if hasTOTPSeed {
                totpToggleRow
            }
        }
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
    }

    private func fieldSelectionBinding(for field: DynamicField) -> Binding<Bool> {
        Binding<Bool>(
            get: { flow.selectedFieldIDs.contains(field.id) },
            set: { newValue in setFieldSelected(field.id, selected: newValue) })
    }

    private func setFieldSelected(_ fieldID: String, selected: Bool) {
        if selected {
            flow.selectedFieldIDs.insert(fieldID)
        } else {
            flow.selectedFieldIDs.remove(fieldID)
        }
    }

    private func fieldToggleRow(field: DynamicField) -> some View {
        let isSelected = fieldSelectionBinding(for: field)
        return VStack(alignment: .leading, spacing: Space.s1) {
            Toggle(isOn: isSelected) {
                Text(appLabel(field.label)).vaultType(.body).themedForeground()
            }
            if field.kind == .password, isSelected.wrappedValue {
                Text("Password will be visible on this computer.")
                    .vaultType(.footnote).themedForeground(.warning)
            }
        }
        .padding(.horizontal, Space.gutter).padding(.vertical, Space.s3)
    }

    private var totpToggleRow: some View {
        Toggle(isOn: $flow.includeCurrentTOTP) {
            Text("Current 2FA code").vaultType(.body).themedForeground()
        }
        .padding(.horizontal, Space.gutter).padding(.vertical, Space.s3)
    }
}
