import SwiftUI

/// Success screen after a quick link is minted: the link (the ONLY place the
/// decryption key exists once this screen closes), copy/share actions, and
/// the honesty notes (bearer semantics + device-local revoke).
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
        VStack(spacing: Space.s5) {
            PolarisIcon(Icons.checkCircle, size: Metric.iconTile)
                .themedForeground(.success)
            Text("Link ready")
                .vaultType(.section).themedForeground()

            // Truncated middle: enough to recognize, never the full secret on
            // screen — Copy/Share carry the real thing.
            Text(verbatim: activeURL.absoluteString)
                .font(.vaultCode(.footnote))
                .themedForeground(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .padding(Space.s4)
                .frame(maxWidth: .infinity)
                .background(VaultColors.surface)
                .vaultCornerRadius(Radius.md)

            Text("Anyone with this link can view the shared fields until it expires or you revoke it. Send it over a channel you trust.")
                .vaultType(.callout).themedForeground(.secondary)
                .multilineTextAlignment(.center)

            // One lifetime story each: one-time links lead with burn-on-open
            // (the 24h fallback stays in the config footer); timed links show
            // their expiry.
            if link.record.oneTime {
                Text("This link disappears after it's opened once.")
                    .vaultType(.footnote).themedForeground(.warning)
                    .multilineTextAlignment(.center)
            } else {
                Text("Expires \(link.record.expiresAt.formatted(Date.RelativeFormatStyle(presentation: .named).locale(appResourceLocale)))")
                    .vaultType(.footnote).themedForeground(.secondary)
            }

            Button {
                // Sensitive: the URL fragment IS the decryption key — expiring
                // clipboard semantics apply, and the value is never logged.
                env.clipboard.copy(activeURL.absoluteString, sensitive: true)
                copied = true
            } label: {
                Label { Text(copied ? "Link Copied" : "Copy Link") }
                    icon: { PolarisIcon(copied ? Icons.copyDone : Icons.copy) }
                    .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
            }
            .buttonStyle(.themedProminent)

            ShareLink(item: activeURL) {
                Label { Text("Share Link") } icon: { PolarisIcon(Icons.share) }
                    .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
            }

            // Optional prettifier, only while this screen holds the working
            // link (no retroactive shorten from history — by design). The
            // button exists only once the backend hands out shorten tokens.
            if link.shortenToken != nil, shortURL == nil, !shortenUnavailable {
                Button { shorten() } label: {
                    Label { Text(shortening ? "Creating short link…" : "Shorten Link") }
                        icon: { PolarisIcon(Icons.magic) }
                        .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
                }
                .disabled(shortening)
            }
            if shortenUnavailable {
                // Shortening is presentation sugar: its outage never makes the
                // created share read as failed.
                Text("Short links are temporarily unavailable. Your share link is ready to use.")
                    .vaultType(.footnote).themedForeground(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text("This link can only be revoked from this device.")
                .vaultType(.footnote).themedForeground(.secondary)
                .multilineTextAlignment(.center)

            Button { onDone() } label: {
                Text("Done").frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
            }
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shorten() {
        shortening = true
        Task {
            defer { shortening = false }
            do {
                let short = try await env.looxLinks.shorten(link)
                shortURL = short
                copied = false   // the copy button now carries the short form
                Haptics.success()
            } catch {
                shortenUnavailable = true
            }
        }
    }
}
