import SwiftUI

/// Cross-platform navigation / toolbar / list chrome. The iOS forms
/// (`navigationBarTitleDisplayMode`, `.topBarTrailing`, `.insetGrouped`,
/// `.platformHiddenNavigationBar()`) are unavailable on macOS; these
/// wrappers keep shared screens compiling with sensible macOS equivalents.

enum PlatformTitleDisplayMode { case inline, large, automatic }

extension View {
    /// iOS navigation-bar title display mode; no-op on macOS (no nav bar).
    func platformNavigationBarTitleDisplayMode(_ mode: PlatformTitleDisplayMode) -> some View {
        #if os(iOS)
        let uiMode: NavigationBarItem.TitleDisplayMode =
            switch mode { case .inline: .inline; case .large: .large; case .automatic: .automatic }
        return navigationBarTitleDisplayMode(uiMode)
        #else
        return self
        #endif
    }

    /// Inset-grouped list on iOS; the nearest macOS equivalent (`.inset`).
    func platformInsetGroupedListStyle() -> some View {
        #if os(iOS)
        return listStyle(.insetGrouped)
        #else
        return listStyle(.inset)
        #endif
    }

    /// Full-screen cover on iOS; falls back to a sheet on macOS (no full-screen
    /// modal presentation there).
    func platformFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        return fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #else
        return sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }

    /// Item-driven full-screen cover on iOS; sheet on macOS.
    func platformFullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(iOS)
        return fullScreenCover(item: item, onDismiss: onDismiss, content: content)
        #else
        return sheet(item: item, onDismiss: onDismiss, content: content)
        #endif
    }

    /// Hide the leading navigation chrome (screens that draw their own header).
    func platformHiddenNavigationBar() -> some View {
        #if os(iOS)
        return toolbar(.hidden, for: .navigationBar)
        #else
        return toolbar(.hidden, for: .windowToolbar)
        #endif
    }

    /// A pushed detail that fills the screen: hide the tab bar while it is on the
    /// stack (the SwiftUI equivalent of UIKit's `hidesBottomBarWhenPushed`). iOS
    /// reveals the bar again on the underlying screen during the back swipe. No-op
    /// on macOS (no tab bar).
    func fullScreenPush() -> some View {
        #if os(iOS)
        return toolbar(.hidden, for: .tabBar)
        #else
        return self
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Trailing primary action: `.topBarTrailing` on iOS, `.primaryAction` on macOS.
    static var platformPrimaryAction: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    /// Leading bar item: `.topBarLeading` on iOS, `.navigation` on macOS.
    static var platformTopBarLeading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }
}

/// Platform-neutral sheet detents: applied on iOS, a no-op on macOS (native
/// macOS sheets have no detent API; they size to content).
enum PlatformDetent { case medium, large }

extension View {
    @ViewBuilder
    func platformPresentationDetents(_ detents: [PlatformDetent]) -> some View {
        #if os(iOS)
        presentationDetents(Set(detents.map { detent in
            switch detent {
            case .medium: PresentationDetent.medium
            case .large: PresentationDetent.large
            }
        }))
        #else
        self
        #endif
    }

    /// Hide the navigation bar's background (screens drawing their own chrome).
    /// `.navigationBar` isn't a macOS toolbar placement — no-op there.
    func platformHiddenNavigationBarBackground() -> some View {
        #if os(iOS)
        return toolbarBackground(.hidden, for: .navigationBar)
        #else
        return self
        #endif
    }
}
