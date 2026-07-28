import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Cross-platform app-chrome helpers: force light/dark appearance, dismiss the
/// software keyboard / resign first responder, and open external URLs.
///
/// macOS is NOT a blanket no-op — each site gets a real AppKit replacement
/// (iOS `overrideUserInterfaceStyle` → app-global `NSApp.appearance`;
/// `resignFirstResponder` → `makeFirstResponder(nil)`;
/// `UIApplication.open` → `NSWorkspace.open`).
@MainActor enum PlatformAppearance {
    enum Style: Equatable { case light, dark, unspecified }

    /// Force the app to a light/dark appearance so presented sheets and system
    /// chrome match the rendered theme. On iOS this sets every window's
    /// `overrideUserInterfaceStyle`; on macOS `NSApp.appearance` is app-global.
    static func forceInterfaceStyle(_ style: Style) {
        #if canImport(UIKit)
        let ui: UIUserInterfaceStyle =
            switch style { case .light: .light; case .dark: .dark; case .unspecified: .unspecified }
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach { $0.overrideUserInterfaceStyle = ui }
        }
        #elseif canImport(AppKit)
        NSApp?.appearance =
            switch style {
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            case .unspecified: nil
            }
        #endif
    }

    /// `forceInterfaceStyle` reaches only the windows connected at call time. A
    /// window that attaches later — a scene connecting after launch, a
    /// sheet-hosting window, a cold launch where the root's `onAppear` beat the
    /// scene — keeps following the DEVICE appearance: the app renders its light
    /// theme on dark system chrome until the next theme mutation happens to
    /// re-apply. Watch every window as it becomes visible and re-apply then.
    /// Idempotent install; macOS needs none of this (`NSApp.appearance` is
    /// app-global, new windows inherit it).
    static func reapplyOnNewWindows(_ apply: @escaping @MainActor () -> Void) {
        #if canImport(UIKit)
        guard !windowObserverInstalled else { return }
        windowObserverInstalled = true
        NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeVisibleNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { apply() }
        }
        #endif
    }

    private static var windowObserverInstalled = false

    /// Dismiss the software keyboard / resign the current first responder.
    static func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #elseif canImport(AppKit)
        NSApp?.keyWindow?.makeFirstResponder(nil)
        #endif
    }

    /// Open an external URL in the user's browser / default handler.
    static func open(_ url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    /// Jump straight to this app's notification settings — after a denial the
    /// OS never re-prompts, so a "try again" without this is a dead end.
    static func openNotificationSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

// MARK: - Cross-platform system colors

extension Color {
    /// `UIColor.systemBackground` on iOS, the window background on macOS —
    /// the adaptive plain page color the brand surfaces flood.
    static var platformBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    /// `UIColor.systemGray` / `NSColor.systemGray`.
    static var platformSystemGray: Color {
        #if os(macOS)
        Color(nsColor: .systemGray)
        #else
        Color(uiColor: .systemGray)
        #endif
    }
}
