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
    enum Style { case light, dark, unspecified }

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
}
