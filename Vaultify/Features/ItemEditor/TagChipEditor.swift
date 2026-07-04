import SwiftUI

/// Add/remove free-text tags for an item. Chips show `#tag` with a remove
/// button; the text field commits on return or comma, trims, and dedups
/// case-insensitively. No per-tag color — tags are the lightweight layer.
struct TagChipEditor: View {
    @Binding var tags: [String]
    @State private var entry = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                PolarisIcon(Icons.hashtag, size: 12).themedForeground(.secondary)
                                Text(tag).font(.subheadline)
                                Button { remove(tag) } label: {
                                    PolarisIcon(Icons.close, size: 11).themedForeground(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(VaultColors.surface, in: Capsule())
                        }
                    }
                }
            }
            TextField("Add tag", text: $entry)
                .autocorrectionDisabled()
                .platformAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit(commit)
                .onChange(of: entry) { _, newValue in
                    if newValue.contains(",") { commit() }
                }
        }
    }

    private func commit() {
        for part in entry.split(whereSeparator: { $0 == "," || $0 == "\n" }) {
            add(String(part))
        }
        entry = ""
    }

    private func add(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        tags.append(trimmed)
    }

    private func remove(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}
