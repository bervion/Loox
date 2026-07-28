import SwiftUI

/// Publishes a view's on-screen frame under a stable id so a tutorial overlay
/// can cut a spotlight around it. Frames travel up as SwiftUI `Anchor` values
/// and are resolved in the overlay's own coordinate space, so scrolling,
/// rotation, and split-view resizes stay correct without any manual geometry
/// bookkeeping at the call site.
///
/// A screen only tags what it owns:
/// ```swift
/// QuickActionTile(...).tutorialAnchor(TutorialAnchorID.homeAddItem)
/// ```
struct TutorialAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        // Last writer wins: a screen re-entered by navigation republishes the
        // same ids, and the newest frame is the on-screen one.
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publish this view's frame for the tutorial overlay to spotlight.
    func tutorialAnchor(_ id: String) -> some View {
        anchorPreference(key: TutorialAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// Same, for data-driven rows whose anchor is optional — publishing an
    /// empty dictionary keeps untagged rows out of the preference entirely.
    @ViewBuilder
    func tutorialAnchorIfPresent(_ id: String?) -> some View {
        if let id { tutorialAnchor(id) } else { self }
    }
}

/// Anchor ids shared between the screens that publish frames and the flows
/// that reference them. String-based (not an enum) so a flow can name an
/// anchor a screen has not adopted yet without breaking the build — an
/// unresolved anchor degrades to a centered tooltip rather than a crash.
enum TutorialAnchorID {
    static let homeAddItem = "home.addItem"
    static let homeSearch = "home.search"
    static let homeSecurity = "home.security"
    static let settingsAutoFill = "settings.autofill"
    static let watchtowerScore = "watchtower.score"
    static let watchtowerRunAudit = "watchtower.runAudit"
    static let shareAccess = "item.shareAccess"
}
