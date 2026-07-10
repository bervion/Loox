import SwiftUI

/// Success screen after a quick link is minted: the link (the ONLY place the
/// decryption key exists once this screen closes), copy/share actions, and
/// the honesty notes (bearer semantics + device-local revoke).
///
/// Action hierarchy: Copy is the one thing almost everyone does next, so it's
/// the only filled primary. Done is the quiet secondary. Share and the
/// optional Shorten step are occasional extras — they live in a small
/// utility row, the same shape as the system share sheet's own quick-action
/// row, so this screen never reads as a wall of equal-weight buttons.
struct QuickLinkResultView: View {
    let link: LooxLinkService.CreatedLink
    let onDone: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var copied = false
    /// In-memory only, like the fragment it carries — the working short link
    /// exists exactly as long as this screen; history keeps a fragment-free
    /// note that shortening happened, never a usable URL.
    @State private var shortURL: URL?
    @State private var shortening = false
    @State private var shortenUnavailable = false

    /// What Copy/Share hand out — the short form once minted.
    private var activeURL: URL { shortURL ?? link.url }

    var body: some View {
        // Left-aligned, top-anchored (DNA: typography is architecture — bold and
        // leading at key moments, not a centered float). Content reads top-down;
        // the action pair sits at the bottom of the sheet where the thumb is.
        VStack(alignment: .leading, spacing: Space.s5) {
            HStack(spacing: Space.s2) {
                PolarisIcon(Icons.checkCircle, size: Metric.iconUtility)
                    .themedForeground(.success)
                Text("Link ready")
                    .vaultType(.screenTitle).themedForeground()
            }

            // Truncated middle: enough to recognize, never the full secret on
            // screen — Copy/Share carry the real thing.
            Text(verbatim: activeURL.absoluteString)
                .font(.vaultCode(.footnote))
                .themedForeground(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VaultColors.surface)
                .vaultCornerRadius(Radius.md)

            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Anyone with this link can view the shared fields until it expires or you revoke it. Send it over a channel you trust.")
                    .vaultType(.callout).themedForeground(.secondary)

                // One lifetime story each: one-time links lead with burn-on-open
                // (the 24h fallback stays in the config footer); timed links show
                // their expiry.
                if link.record.oneTime {
                    Text("This link disappears after it's opened once.")
                        .vaultType(.footnote).themedForeground(.warning)
                } else {
                    Text("Expires \(link.record.expiresAt.formatted(Date.RelativeFormatStyle(presentation: .named).locale(appResourceLocale)))")
                        .vaultType(.footnote).themedForeground(.secondary)
                }
            }

            Spacer(minLength: Space.s4)

            // ONE filled primary + one quiet secondary — the only two actions
            // most people need right after a link is created.
            VStack(spacing: Space.s3) {
                Button {
                    // Sensitive: the URL fragment IS the decryption key — expiring
                    // clipboard semantics apply, and the value is never logged.
                    env.clipboard.copy(activeURL.absoluteString, sensitive: true)
                    copied = true
                } label: {
                    Label { Text(copied ? "Link Copied" : "Copy Link") }
                        icon: { PolarisIcon(copied ? Icons.copyDone : Icons.copy) }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)

                Button { onDone() } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedTinted)
            }

            // Occasional extras, demoted below the primary/secondary pair —
            // same shape as the system share sheet's own small action row.
            HStack(spacing: Space.s6) {
                ShareLink(item: activeURL) {
                    utilityAction(icon: Icons.share, title: "Share Link")
                }
                // Optional prettifier, only while this screen holds the working
                // link (no retroactive shorten from history — by design). The
                // action exists only once the backend hands out shorten tokens.
                if link.shortenToken != nil, shortURL == nil, !shortenUnavailable {
                    Button { shorten() } label: {
                        utilityAction(icon: Icons.magic,
                                      title: shortening ? "Creating short link…" : "Shorten Link")
                    }
                    .disabled(shortening)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Group {
                if shortenUnavailable {
                    // Shortening is presentation sugar: its outage never makes the
                    // created share read as failed.
                    Text("Short links are temporarily unavailable. Your share link is ready to use.")
                } else {
                    Text("This link can only be revoked from this device.")
                }
            }
            .vaultType(.footnote).themedForeground(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Small icon-over-label control for the demoted extras row. Still a
    /// full ≥44pt hit target even though it reads visually light.
    private func utilityAction(icon: String, title: LocalizedStringResource) -> some View {
        VStack(spacing: Space.s1) {
            PolarisIcon(icon, size: Metric.iconInline).themedForeground(.accent)
            Text(title)
                .vaultType(.footnote).themedForeground(.accent)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(minWidth: Metric.hitMin, minHeight: Metric.hitMin)
    }

    private func shorten() {
        shortening = true
        Task {
            defer { shortening = false }
            do {
                let short = try await env.looxLinks.shorten(link)
                shortURL = short
                copied = false   // the copy button now carries the short form
                Haptics.tap()    // minor cosmetic change, not a success/copy event
            } catch {
                shortenUnavailable = true
            }
        }
    }
}
