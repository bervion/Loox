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
    /// Inside a Form/List row the section card already provides the surface — the
    /// field's own capsule background would sit on top of it and read as broken,
    /// glued-together cards. `inList` drops the capsule and lets the row chrome win.
    var inList: Bool = false
    @State private var reveal = false
    @FocusState private var focused: Bool
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Space.s2) {
            if let icon {
                // Icon sits in a soft accent tile (mirrors the onboarding card iconography);
                // the tile also gives the prominent field its taller resting height.
                PolarisIcon(icon, size: Metric.iconInline)
                    .foregroundStyle(Color(rgb: theme.accentText))
                    .frame(width: Metric.controlSmall, height: Metric.controlSmall)
                    .background(Color(rgb: theme.accentSoft),
                                in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(title)
                        .vaultType(.body)
                        .foregroundStyle(Color(rgb: theme.secondaryText))
                }
                Group {
                    if reveal {
                        TextField("", text: $text)
                    } else {
                        SecureField("", text: $text)
                    }
                }
                .platformAutocapitalization(.never)
                .autocorrectionDisabled()
                .platformTextContentType(.password)
                .vaultType(.body)
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
                        // Expand the TAP area to the 44pt WCAG/HIG minimum without growing the
                        // glyph or the row: `.contentShape` only affects hit-testing, not the
                        // size this view reports to the parent `HStack`, so the field's height
                        // stays exactly what its own vertical padding dictates.
                        .contentShape(Rectangle().inset(by: -(Metric.hitMin - Metric.iconInline) / 2))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, inList ? 0 : Space.s3)
        .padding(.vertical, inList ? Space.s1 : Space.s3)
        .background(inList ? Color.clear
                           : Color(rgb: prominent ? theme.elevatedBackground : theme.controlBackground),
                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .elevation(prominent ? .level2 : .level0)
    }
}
