import SwiftUI

/// Success screen after a quick link is minted: the link (the ONLY place the
/// decryption key exists once this screen closes), copy/share actions, and
/// the honesty notes (bearer semantics + device-local revoke).
struct QuickLinkResultView: View {
    let link: LooxLinkService.CreatedLink
    let onDone: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var copied = false

    var body: some View {
        VStack(spacing: Space.s5) {
            PolarisIcon(Icons.checkCircle, size: Metric.iconTile)
                .themedForeground(.success)
            Text("Link ready")
                .vaultType(.section).themedForeground()

            // Truncated middle: enough to recognize, never the full secret on
            // screen — Copy/Share carry the real thing.
            Text(verbatim: link.url.absoluteString)
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
                env.clipboard.copy(link.url.absoluteString, sensitive: true)
                copied = true
            } label: {
                Label { Text(copied ? "Link Copied" : "Copy Link") }
                    icon: { PolarisIcon(copied ? Icons.copyDone : Icons.copy) }
                    .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
            }
            .buttonStyle(.themedProminent)

            ShareLink(item: link.url) {
                Label { Text("Share Link") } icon: { PolarisIcon(Icons.share) }
                    .frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
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
}
