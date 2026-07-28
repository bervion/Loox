import Foundation

/// Master switch for the in-app tutorial layer (spotlight tours and the
/// sheet-embedded guides).
///
/// Off means the app behaves exactly as it did before the tutorial existed:
/// no overlay is built, no flow is evaluated, and nothing is persisted. That
/// keeps the release train independent of the tutorial's own polish schedule —
/// the same arrangement `WallpaperFeature` uses for decorative backgrounds.
nonisolated enum TutorialFeature {
    static let enabled = true
}
