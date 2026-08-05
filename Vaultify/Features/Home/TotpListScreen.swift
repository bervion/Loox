import SwiftUI

/// All 2FA codes as full-width rows with an always-visible quick search —
/// pushed full-screen from Home's Authenticator section ("View All") and the
/// "2FA Codes" quick action (owner 260805: rows + search replaced the old
/// bottom-sheet grid). The iPad/Mac sidebar quick action still presents it as
/// a shell-owned sheet (`presentedAsSheet`), wrapping the same list in the
/// standard sheet scaffold.
struct TotpListScreen: View {
    /// Sheet variant (iPad/Mac sidebar quick action): adds the sheet chrome
    /// (inline title + Done). The pushed variant gets its bar from the
    /// enclosing navigation stack instead.
    var presentedAsSheet = false

    @Environment(AppEnvironment.self) private var env
    @State private var query = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    /// Every TOTP-bearing item of the active persona, narrowed live by the
    /// search field. Same contract as the repository's free-text search: every
    /// token must match the item's (lowercased) searchable text.
    private var items: [VaultItem] {
        let pool = env.repository.totpItems(folder: nil)
        guard !trimmed.isEmpty else { return pool }
        let tokens = trimmed.lowercased().split(separator: " ").map(String.init)
        return pool.filter { item in tokens.allSatisfy { item.searchText.contains($0) } }
    }

    /// Always-visible field so "search fast" needs no reveal scroll
    /// (`navigationBarDrawer` is iOS-only; macOS falls back to automatic).
    private static var searchPlacement: SearchFieldPlacement {
        #if os(macOS)
        .automatic
        #else
        .navigationBarDrawer(displayMode: .always)
        #endif
    }

    var body: some View {
        if presentedAsSheet {
            VaultSheetScaffold(title: "2FA Codes",
                               leading: { EmptyView() },
                               trailing: { SheetDismissButton("Done") }) {
                listContent
            }
        } else {
            listContent
                .themedFormBackground()
                .navigationTitle(Text("2FA Codes"))
                .platformNavigationBarTitleDisplayMode(.inline)
        }
    }

    private var listContent: some View {
        List {
            ForEach(items) { item in
                TotpRowView(item: item)
                    // Themed row panel — the List default is the raw system color,
                    // which mismatches every sibling list on non-default themes
                    // (same treatment as VaultItemRowLink).
                    .listRowBackground(VaultColors.surface)
            }
        }
        .platformInsetGroupedListStyle()
        .searchable(text: $query, placement: Self.searchPlacement, prompt: "Search")
        .autocorrectionDisabled()
        .platformAutocapitalization(.never)
        .overlay {
            if items.isEmpty {
                if trimmed.isEmpty {
                    emptyState
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .analyticsScreen("totp_list")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No 2FA codes")
            } icon: {
                VaultIcon(Icons.clock, size: 48)
                    .themedForeground(.secondary)
            }
        } description: {
            Text("Add a one-time code field to any login item to see it here.")
        }
    }
}
