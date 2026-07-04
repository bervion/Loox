import SwiftUI

/// A website row for the Login editor: URL-only (no type/label controls, so the field
/// can't be changed to another kind). Typing a bare domain (e.g. "google.com") reveals a
/// tappable suggestion chip showing that domain's favicon; tapping it fills in the full
/// "https://…" URL.
struct WebsiteFieldRow: View {
    @Binding var field: DynamicField
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            // Empty built-in placeholder + a gray Text overlay: the default placeholder here
            // picks up the app accent tint (shows blue), so draw our own neutral one.
            TextField("", text: $field.value)
                .font(.body)
                .platformKeyboardType(.url)
                .platformAutocapitalization(.never)
                .autocorrectionDisabled()
                .overlay(alignment: .leading) {
                    if field.value.isEmpty {
                        Text(verbatim: "https://example.com")
                            .font(.body)
                            .themedForeground(.tertiary)
                            .allowsHitTesting(false)
                    }
                }

            if let suggestion {
                Button { field.value = suggestion } label: { suggestionChip(suggestion) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    /// Chip: favicon of the typed domain + the full https URL it would become.
    private func suggestionChip(_ suggestion: String) -> some View {
        HStack(spacing: Space.s2) {
            FaviconView(urlString: field.value, category: .login, size: 20)
            Text(verbatim: suggestion)
                .vaultType(.footnote)
                .themedForeground(.accent)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            PolarisIcon(Icons.add, size: 13).themedForeground(.accent)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(Color(rgb: env.theme.active.accentSoft), in: Capsule())
        .contentShape(Capsule())
    }

    /// The "https://<host>" suggestion when the user typed a bare domain (no scheme,
    /// no spaces, has a dot, doesn't start/end with a dot). Hidden once the value already
    /// carries a scheme.
    private var suggestion: String? {
        let raw = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains("://"), !raw.contains(" "),
              raw.contains("."), !raw.hasPrefix("."), !raw.hasSuffix(".") else { return nil }
        return "https://\(raw)"
    }
}
