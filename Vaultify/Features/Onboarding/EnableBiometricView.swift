import SwiftUI

/// Optional step offering biometric unlock when the device supports it.
///
/// `onEnable` returns a localized failure reason, or nil when enrolment really succeeded
/// and the caller has already moved on. The step used to fire and forget: a cancelled or
/// failed Face ID prompt still advanced to the done screen, which then congratulated the
/// user on a protection they did not have.
struct EnableBiometricView: View {
    let onEnable: () async -> String?
    let onSkip: () -> Void
    @Environment(AppEnvironment.self) private var env

    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        // Scroll-safe: a fixed Spacer-centered VStack clips at large Dynamic Type /
        // on SE, since neither header ever scrolls (see OnboardingScrollingStep).
        OnboardingScrollingStep {
            VStack(spacing: 0) {
                Spacer(minLength: Space.s8)
                // Brand dots mark looping the spark against the system biometry
                // glyph (Face ID / Touch ID), like the profile avatar invitation.
                LooxDotsAvatar(size: 120, animatesCamera: true,
                               loopSystemGlyph: BiometricAuth.systemImage)
                    .padding(.bottom, Space.s4)
                OnboardingStepHeader(
                    "Enable \(BiometricAuth.displayName)",
                    subtitle: "Unlock your vault quickly with \(BiometricAuth.displayName). Your master password still works anytime.")

                if let failure {
                    VaultInfoBanner(.error,
                                    title: "\(BiometricAuth.displayName) was not turned on",
                                    verbatimText: failure)
                        .padding(.horizontal, Space.s6)
                        .padding(.top, Space.s5)
                }

                Spacer(minLength: Space.s6)
                // Action hierarchy: ONE filled primary, and a quiet text-only
                // secondary. `BrandCapsuleCTA` carries its own horizontal /
                // bottom padding, so its bottom inset is the gap to "Not now".
                VStack(spacing: 0) {
                    // Retry keeps the same button: the step is still "enable it",
                    // and a second label would rank the failure above the action.
                    BrandCapsuleCTA(title: "Enable \(BiometricAuth.displayName)",
                                    enabled: !busy, busy: busy, action: enable)

                    // Deliberately unfilled: skipping is the low-emphasis path,
                    // so it reads as a text button, not a second capsule. It still
                    // takes the TEXT-LINK colour, not `.secondary` — this is the
                    // only way past a step that has no back and no toolbar skip,
                    // and grey body copy does not read as something you can tap.
                    // The explicit frame keeps the 44pt hit target a bare `Button`
                    // label would not guarantee.
                    Button(action: onSkip) {
                        Text(skipLabel)
                            .vaultType(.body).fontWeight(.medium)
                            .themedForeground(.accentText)
                            .frame(maxWidth: .infinity, minHeight: Metric.hitMin)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .padding(.horizontal, Space.s6)
                }
                .padding(.bottom, Space.s6)
            }
        }
        // No form fields or grouped cards on this step — plain white canvas
        // per the design convention (gray is reserved for form screens).
        .background(Color(rgb: env.theme.active.background).ignoresSafeArea())
    }

    /// Explicitly a `LocalizedStringKey`: a bare ternary of two literals inside `Text` can
    /// resolve to the verbatim `StringProtocol` overload, which skips the catalog entirely.
    private var skipLabel: LocalizedStringKey {
        failure == nil ? "Not now" : "Continue without it"
    }

    private func enable() {
        guard !busy else { return }
        busy = true
        failure = nil
        Task {
            let reason = await onEnable()
            busy = false
            failure = reason
            if reason != nil { Haptics.error() }
        }
    }
}
