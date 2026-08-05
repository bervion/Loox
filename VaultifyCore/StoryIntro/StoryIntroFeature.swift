import Foundation

/// Master switch for the one-time story intro (the post-onboarding cinematic
/// shown before the first Home visit).
///
/// Off restores the pre-story flow exactly: RootView routes straight from
/// unlock to the app, nothing is rendered or persisted. Same release-train
/// decoupling `TutorialFeature` uses — the story's polish schedule never
/// holds a release hostage.
nonisolated enum StoryIntroFeature {
    static let enabled = true
}
