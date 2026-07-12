//
//  WelcomeLandingView.swift
//  Vaultify
//
//  First-run landing in the spirit of the iCloud sign-in page: a looping Loox
//  brand animation, the wordmark, a primary CTA that plays the circle-burst
//  launch transition before handing off to vault creation, a one-line value
//  proposition, a restore link, and a peek carousel of capability cards (16:9
//  art placeholders, still in design).
//
//  Layout is sized off the container width so it reads the same on a compact
//  phone (iPhone 11 / SE) as on a Pro Max: the logo and cards scale with width,
//  vertical spacing uses tokens, and the flanking spacers center the stack when
//  it fits (never clipping — the ScrollView takes over on very short screens).
//

import SwiftUI

struct WelcomeLandingView: View {
    /// Advance into vault creation. Called as the launch bloom floods the screen,
    /// so the create step crossfades in from behind the flood.
    let onContinue: () -> Void
    /// Present when this build can restore/join an existing vault over iCloud.
    var onRestore: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var launch = LooxLaunchController()
    /// Text, CTA, and carousel step aside for the launch; the animation stays.
    @State private var contentHidden = false

    var body: some View {
        GeometryReader { proxy in
            // Brand mark scales with width but is capped so it never dominates a
            // wide screen; height is trimmed (0.82) to keep the stack compact.
            let logoSide = min(proxy.size.width * 0.56, 252)

            ZStack {
                // Plain white page (adaptive: black in dark mode). Also the color
                // the launch bloom floods, so the hand-off is seamless.
                Color(.systemBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: Space.s7)

                        // Left out of the fading `content` group so it keeps
                        // performing through the launch burst.
                        LooxCloudAnimationView(controller: launch)
                            .frame(width: logoSide, height: logoSide * 0.82)

                        landingContent(width: proxy.size.width)
                            .opacity(contentHidden ? 0 : 1)

                        Spacer(minLength: Space.s6)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: Landing content (fades out on launch)

    private func landingContent(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Fixed brand wordmark — identical in every language, so rendered
            // verbatim (not a localized string).
            Text(verbatim: "Loox Password")
                .vaultType(.screenTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .themedForeground(.primary)
                .padding(.top, Space.s5)

            startButton
                .padding(.top, Space.s5)

            Text(appString("The safest home for your passwords, passkeys, cards and notes."))
                .vaultType(.callout)
                .themedForeground(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, Space.s7)
                .padding(.horizontal, Space.s7)

            restoreLink
                .padding(.top, Space.s3)

            CapabilityCarousel(containerWidth: width)
                .padding(.top, Space.s6)
        }
    }

    // MARK: Primary CTA (black pill, matches the demo)

    private var startButton: some View {
        Button(action: press) {
            Text(appString("Get Started"))
                .vaultType(.headline)
                .fontWeight(.semibold)
                // Deliberate adaptive black/white pill (the demo look the user
                // asked for): label sits on the primary fill, so it uses the
                // background color rather than a themed text token.
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, Space.s6)
                .padding(.vertical, Space.s3)
                .background(Capsule().fill(Color.primary))
        }
        .buttonStyle(.plain)
        .disabled(launch.phase != .idle)
        .accessibilityLabel(Text(appString("Get Started")))
    }

    // MARK: Restore link (directly under the value proposition)

    @ViewBuilder private var restoreLink: some View {
        if let onRestore {
            Button(action: onRestore) {
                Text(appString("Restore data?"))
                    .vaultType(.subhead)
                    .fontWeight(.semibold)
                    .themedForeground(.accent)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Launch choreography

    private func press() {
        guard launch.phase == .idle else { return }

        // Reduce Motion: skip the circle-burst; a plain crossfade hands off.
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.25)) { contentHidden = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { onContinue() }
            return
        }

        launch.press()
        // Text and CTA step aside just before the spiral; the animation keeps
        // going and blooms into a full-screen flood.
        withAnimation(.easeOut(duration: 0.25).delay(0.35)) { contentHidden = true }
        // Hand off while the bloom covers the screen, so the create step
        // crossfades in unseen behind the flood.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { onContinue() }
    }
}

// MARK: - Capability carousel

/// Horizontal peek carousel of what the vault holds. One card snaps into place
/// per swipe (page-by-page); each leads with a 16:9 art placeholder (dashed
/// frame — the real illustrations are still in design) above a title and line.
private struct CapabilityCarousel: View {
    let containerWidth: CGFloat

    private struct Slide: Identifiable {
        let id = UUID()
        let image: String
        let title: LocalizedStringResource
        let detail: LocalizedStringResource
    }

    private let slides: [Slide] = [
        .init(image: "welcome-card-encryption",
              title: "End-to-end encryption",
              detail: "Argon2id + AES-256-GCM, keys stay only on this device."),
        .init(image: "welcome-card-store",
              title: "Passwords, cards, notes & more",
              detail: "Store essentials, generate strong passwords, and use one-time codes."),
        .init(image: "welcome-card-unlock",
              title: "Unlock with Face ID / Touch ID",
              detail: "Fast biometric access protected by the Secure Enclave.")
    ]

    /// ~72% of the viewport (capped): one card per page, next card peeking in.
    private var cardWidth: CGFloat { min(containerWidth * 0.72, 320) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s4) {
                ForEach(slides) { slide in
                    CapabilitySlide(image: slide.image, title: slide.title, detail: slide.detail, width: cardWidth)
                }
            }
            // Equal-height cards: the row takes the tallest card's height and the
            // shorter ones stretch to match (each card caps its height to the
            // row via maxHeight). Locale-safe — the longest label sets the bar.
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
            .padding(.horizontal, Space.gutter)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }
}

private struct CapabilitySlide: View {
    let image: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let width: CGFloat

    /// The whole card — 16:9 art region plus its caption — is one surface lifted
    /// by a soft drop shadow (no border), gently rounded on all four corners.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artRegion
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title.inAppLocalized)
                    .vaultType(.callout).fontWeight(.semibold)
                Text(detail.inAppLocalized)
                    .vaultType(.subhead).themedForeground(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s4)
            // Fill any extra height (top-aligned) so short-caption cards match
            // the tallest card instead of shrinking.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(VaultColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .elevation(.level2)
    }

    /// Art inside the card: a 16:9 illustration filling the top edge-to-edge
    /// (top corners clipped by the card). Explicit height so it never stretches
    /// inside the vertical scroll; a gray backing shows if the asset is missing.
    private var artRegion: some View {
        Image(image)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: width * 9.0 / 16.0)
            .background(VaultColors.fill)
            .clipped()
    }
}
