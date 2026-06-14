import SwiftUI

/// Horizontal row of tag chips on Home; tap to see items with that tag. Hidden
/// when there are no tags. Neutral styling — tags are the lightweight layer.
struct TagsSection: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var path: NavigationPath
    private var tags: [(tag: String, count: Int)] { env.repository.allTags() }

    var body: some View {
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tags").font(.title3.bold()).padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.tag) { entry in
                            Button { path.append(VaultRoute.tag(entry.tag)) } label: { chip(entry) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func chip(_ entry: (tag: String, count: Int)) -> some View {
        HStack(spacing: 4) {
            PolarisIcon(Icons.hashtag, size: 12).foregroundStyle(.secondary)
            Text(entry.tag).font(.subheadline)
            Text("\(entry.count)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color(.secondarySystemBackground), in: Capsule())
        .foregroundStyle(.primary)
    }
}
