import SwiftUI

/// Minimal "all 2FA codes" screen — the destination of the "Mã 2FA" quick
/// action and "Xem tất cả" link from the Home TOTP scroller.
/// Reuses TotpCardView in a wrapping flow grid. YAGNI: no search/sort here;
/// Watchtower and the item detail screen handle deeper TOTP management.
struct TotpListScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var editorTarget: EditorTarget?
    private let columns = [GridItem(.adaptive(minimum: 158, maximum: 200), spacing: Space.s3)]

    var body: some View {
        let totpItems = env.repository.totpItems(folder: nil)
        VaultSheetScaffold(title: "2FA Codes",
                           leading: { EmptyView() },
                           trailing: { SheetDismissButton("Done") }) {
        ScrollView {
            if totpItems.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: Space.s3) {
                    ForEach(totpItems) { item in
                        TotpCardView(item: item)
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.vertical, Space.s4)
                .padding(.bottom, TabBarMetric.contentBottomInset)
            }
        }
        .vaultNavigationDestinations()
        .sheet(item: $editorTarget) { ItemEditorScreen(target: $0) }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No 2FA codes")
            } icon: {
                PolarisIcon(Icons.clock, size: 48)
                    .themedForeground(.secondary)
            }
        } description: {
            Text("Add a one-time code field to any login item to see it here.")
        }
        .padding(.top, Space.s10)
    }
}
