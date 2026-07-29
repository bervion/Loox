import SwiftUI

/// The printable Loox Emergency Kit — a single A4 page laid out like a 1Password kit:
/// brand mark, account details (iCloud account + the recovery key as the focal block),
/// a scannable Setup Code, a security warning, and short instructions.
///
/// PRINT ARTIFACT: this view is rendered to PDF for printing, so it deliberately uses
/// fixed ink-on-paper colors instead of semantic theme tokens (the same exemption the
/// QR tile and favicon swatches take). It is fully self-contained — no `AppEnvironment`
/// or `appTheme` — so `ImageRenderer` can rasterise it off any screen.
struct EmergencyKitPDFPage: View {
    let info: EmergencyKitInfo

    // A4 at 72 dpi.
    static let pageSize = CGSize(width: 595.28, height: 841.89)
    private let margin: CGFloat = 44

    // Fixed print palette (dark ink on white; muted gray labels; hairline rules).
    private let ink = Color(white: 0.11)
    private let label = Color(white: 0.46)
    private let rule = Color(white: 0.86)
    private let paper = Color.white
    /// Loox brand blue — used to make the account email stand out on the page.
    private let accent = Color(red: 0.15, green: 0.40, blue: 0.93)

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            Divider().overlay(rule)
            detailsBlock
            setupCodeBlock
            warningBanner
            instructions
            Spacer(minLength: 0)
            footer
        }
        .padding(margin)
        .frame(width: Self.pageSize.width, height: Self.pageSize.height, alignment: .topLeading)
        .background(paper)
        // Force the light wordmark variant + light rendering regardless of app theme.
        .environment(\.colorScheme, .light)
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center) {
            BrandLogoMark(size: 30, shadowRadius: 0, shadowY: 0)
            Spacer()
            Text(appString("Emergency Kit"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(label)
                .textCase(.uppercase)
                .tracking(1.5)
        }
    }

    private var detailsBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(appString("Account Details"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ink)

            if !info.iCloudAccount.trimmingCharacters(in: .whitespaces).isEmpty {
                detailRow(icon: Icons.mail, label: appString("ICLOUD ACCOUNT"),
                          value: info.iCloudAccount, mono: false, valueColor: accent)
            }

            // The recovery key is the focal element — large monospaced block, like the
            // Secret Key on a 1Password kit.
            VStack(alignment: .leading, spacing: 8) {
                labelRow(icon: Icons.key, text: appString("RECOVERY KEY"))
                // One line, high fidelity: shrink-to-fit guarantees the whole key stays
                // inline on any key length instead of wrapping mid-code.
                Text(info.recoveryKey)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.97),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(rule, lineWidth: 1))
            }
        }
    }

    /// Setup Code — QR of the recovery key so a new device scans instead of types.
    private var setupCodeBlock: some View {
        HStack(alignment: .center, spacing: 18) {
            QRCodeView(payload: info.qrPayload)
                .frame(width: 128, height: 128)
            VStack(alignment: .leading, spacing: 6) {
                Text(appString("Setup Code"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
                Text(appString("On a new device, choose “Set up from another device” → “Use Recovery Key” and scan this code to restore your vault."))
                    .font(.system(size: 12))
                    .foregroundStyle(label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var warningBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            VaultIcon(Icons.alert, size: 18).foregroundStyle(Color(red: 0.72, green: 0.42, blue: 0.0))
            Text(appString("Anyone who has this kit and access to your iCloud can restore your vault, no master password needed. Keep it offline and private."))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(red: 0.5, green: 0.32, blue: 0.0))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 1.0, green: 0.97, blue: 0.90),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 10) {
            step(1, appString("Print this kit and keep the copy off your computer."))
            step(2, appString("Store it somewhere safe (with your passport, will, or a secure drawer)."))
            step(3, appString("To restore on a new device: install Loox, sign in to the same iCloud, then scan the Setup Code or type the recovery key."))
            Text(String(format: appString("Need help? Contact %@"), info.supportContact))
                .font(.system(size: 12))
                .foregroundStyle(label)
                .padding(.top, 4)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(rule)
            Text(info.createdLine)
                .font(.system(size: 11))
                .foregroundStyle(label)
                .padding(.top, 6)
        }
    }

    // MARK: Row helpers

    private func detailRow(icon: String, label labelText: String, value: String,
                           mono: Bool, valueColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            labelRow(icon: icon, text: labelText)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: mono ? .monospaced : .default))
                .foregroundStyle(valueColor ?? ink)
        }
    }

    private func labelRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            VaultIcon(icon, size: 13).foregroundStyle(label)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(label)
                .tracking(1)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(ink, in: Circle())
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
