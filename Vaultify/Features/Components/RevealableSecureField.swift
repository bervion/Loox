import SwiftUI

/// A secure text field with a reveal/hide toggle, in a rounded container.
struct RevealableSecureField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    /// Optional leading Polaris glyph (e.g. a lock on the onboarding password fields).
    var icon: String? = nil
    /// Elevated onboarding treatment: white surface + soft shadow + always-visible reveal
    /// (default keeps the flat control-fill look used inside Forms/lists elsewhere).
    var prominent: Bool = false
    @State private var reveal = false
    @FocusState private var focused: Bool
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Space.s2) {
            if let icon {
                // Icon sits in a soft accent tile (mirrors the onboarding card iconography);
                // the tile also gives the prominent field its taller resting height.
                PolarisIcon(icon, size: Metric.iconInline)
                    .foregroundStyle(Color(rgb: theme.accent))
                    .frame(width: Metric.controlSmall, height: Metric.controlSmall)
                    .background(Color(rgb: theme.accentSoft),
                                in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Color(rgb: theme.secondaryText))
                }
                Group {
                    if reveal {
                        TextField("", text: $text)
                    } else {
                        SecureField("", text: $text)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .font(.body)
                .focused($focused)
                .foregroundStyle(Color(rgb: theme.primaryText))
            }

            if !text.isEmpty || prominent {
                Button {
                    reveal.toggle()
                    Haptics.tap()
                } label: {
                    PolarisIcon(reveal ? Icons.hide : Icons.reveal, size: Metric.iconInline)
                        .foregroundStyle(Color(rgb: theme.secondaryText))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Space.s3)
        .background(Color(rgb: prominent ? theme.elevatedBackground : theme.controlBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .elevation(prominent ? .level2 : .level0)
    }
}
