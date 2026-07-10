#if os(macOS)
import SwiftUI

/// Mac shell sidebar: profile row on top, the library filters, then Spaces,
/// Tags, and the Archive / Recently Deleted library tail. Selection drives the
/// list column (`MacVaultFilter`).
struct MacSidebarList: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var filter: MacVaultFilter
    let onProfile: () -> Void

    @State private var creatingSpace = false

    var body: some View {
        List(selection: Binding(get: { filter }, set: { filter = $0 ?? .allItems })) {
            profileRow

            Section {
                row("All Items", icon: Icons.apps, tag: .allItems)
                row("Favorites", icon: Icons.star, tag: .favorites)
                row("Watchtower", icon: Icons.organization, tag: .watchtower)
            }

            if !env.repository.folders.isEmpty {
                Section {
                    ForEach(env.repository.folders) { folder in
                        Label {
                            Text(verbatim: folder.name)
                        } icon: {
                            PolarisIcon(folder.iconAsset).foregroundStyle(folder.color.tint)
                        }
                        .tag(MacVaultFilter.space(folder.id))
                    }
                } header: {
                    HStack {
                        Text("Spaces")
                        Spacer()
                        Button { creatingSpace = true } label: {
                            PolarisIcon(Icons.add, size: 12)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Create New Space"))
                    }
                }
            }

            let tags = env.repository.allTags()
            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags, id: \.tag) { entry in
                        Label {
                            Text(verbatim: entry.tag)
                        } icon: {
                            PolarisIcon(Icons.hashtag)
                        }
                        .tag(MacVaultFilter.tag(entry.tag))
                    }
                }
            }

            Section {
                row("Archive", icon: Icons.archive, tag: .archive)
                row("Recently Deleted", icon: Icons.trash, tag: .trash)
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $creatingSpace) { FolderEditorSheet(folder: nil) }
    }

    private func row(_ title: LocalizedStringResource, icon: String, tag: MacVaultFilter) -> some View {
        Label { Text(title.inAppLocalized) } icon: { PolarisIcon(icon) }
            .tag(tag)
    }

    /// Default-identity avatar + name — opens the profile sheet (not a filter row,
    /// so it deliberately carries no selection tag).
    private var profileRow: some View {
        Button(action: onProfile) {
            HStack(spacing: Space.s3) {
                Group {
                    if let identity = env.repository.defaultIdentity,
                       let image = env.repository.avatarImage(for: identity.id) {
                        Image(platformImage: image).resizable().scaledToFill()
                    } else {
                        PolarisIcon(Icons.person, size: 16).themedForeground(.secondary)
                    }
                }
                .frame(width: Metric.iconTile, height: Metric.iconTile)
                .clipShape(Circle())
                Text(verbatim: env.repository.defaultIdentity?.title ?? appString("Profile"))
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Profile"))
    }
}
#endif
