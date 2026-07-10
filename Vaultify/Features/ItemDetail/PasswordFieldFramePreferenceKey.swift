import SwiftUI

/// Frame of the password row within the item-detail scroll view's named
/// coordinate space. `ItemDetailScreen` reads this to fade in the bottom
/// "Copy Password" cluster (T3) once the row has scrolled out of the
/// viewport — an iOS-17-safe preference-key bounds check, not an
/// iOS-18-only scroll-position API.
struct PasswordFieldFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
