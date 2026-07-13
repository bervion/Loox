import SwiftUI
import Combine

/// Full-screen "Large Type" grid: each character sits in its own numbered cell
/// (digits / letters / symbols color-coded) so a long secret is easy to read out
/// or type elsewhere. Tap a cell to mark that character "entered" — it highlights
/// with a haptic, so you never lose your place in a long password. Scrolls when
/// the value is long. The X (top-right) dismisses.
struct LargeTypeView: View {
    let text: String
    /// The item's 2FA secret, if any — surfaced as a floating tap-to-copy code.
    var totpSecret: String? = nil
    /// When set, the displayed value ITSELF is this live 2FA code: the grid recomputes
    /// every second and the header shows a countdown ring next to Copy.
    var liveTOTPSecret: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @ScaledMetric(relativeTo: .largeTitle) private var fontSize: CGFloat = 30
    /// Indices the user has ticked off as already entered.
    @State private var entered: Set<Int> = []
    @State private var copied = false
    @State private var totpCopied = false
    /// Live 2FA code + seconds left, refreshed each tick when `liveTOTPSecret` is set.
    @State private var liveCode = ""
    @State private var liveRemaining = 30
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var theme: AppTheme { env.theme.active }
    private var isLiveTOTP: Bool { !(liveTOTPSecret ?? "").isEmpty }
    /// The value shown in the grid — the live code once available, else the initial `text`.
    private var displayText: String { isLiveTOTP && !liveCode.isEmpty ? liveCode : text }
    private var characters: [Character] { Array(displayText) }
    private var hasTOTP: Bool { !(totpSecret ?? "").isEmpty }
    private let columns = [GridItem(.adaptive(minimum: 46), spacing: Space.s2)]

    var body: some View {
        // Reuse the app's sheet scaffold so the header is the native, translucent
        // nav bar (iOS 26 liquid glass that reveals as content scrolls under it) —
        // matching every other bottom sheet. X (left), Copy (right), no title.
        VaultSheetScaffold(
            title: nil,
            leading: {
                Button { dismiss() } label: { PolarisIcon(Icons.close, size: Metric.iconInline) }
                    .accessibilityLabel(Text("Close"))
            },
            trailing: {
                HStack(spacing: Space.s2) {
                    // Countdown ring so you can see when a live 2FA code is about to rotate.
                    // Centred in a square the size of the pill's height so its left / top /
                    // bottom margins come out equal (padding-guessing never balanced cleanly).
                    if isLiveTOTP {
                        CountdownRing(remaining: liveRemaining, period: 30)
                            .frame(width: Metric.hitMin, height: Metric.hitMin)
                    }
                    copyButton
                }
            }
        ) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Space.s2) {
                    ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                        cell(index: index, character: character)
                    }
                }
                .padding(Space.gutter)
                // Clear the floating 2FA pill so the last row isn't hidden.
                .padding(.bottom, hasTOTP ? Space.s10 : 0)
            }
            .overlay(alignment: .bottom) {
                if let secret = totpSecret, hasTOTP {
                    totpPill(secret)
                }
            }
            .onAppear { refreshTOTP() }
            .onReceive(ticker) { _ in refreshTOTP() }
        }
    }

    /// Recompute the live 2FA code + seconds remaining (no-op unless `liveTOTPSecret` is set).
    private func refreshTOTP() {
        guard let secret = liveTOTPSecret, !secret.isEmpty else { return }
        liveCode = TOTPGenerator.code(forStoredValue: secret) ?? ""
        liveRemaining = TOTPGenerator.secondsRemaining(period: 30)
    }

    private var copyButton: some View {
        Button { copy() } label: {
            // Text only (no icon), in SF — not the MonoLisa code font.
            Text(copied ? "Copied" : "Copy")
                .vaultType(.body)
                .foregroundStyle(theme.color(copied ? .accent : .primary))
        }
        .accessibilityLabel(Text("Copy"))
    }

    private func copy() {
        env.clipboard.copy(displayText, label: isLiveTOTP ? appString("2FA code") : appString("password"))
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.3)) { copied = false }
        }
    }

    /// Floating 2FA code (center-bottom, liquid glass): live code + countdown ring,
    /// tap to copy. On copy the pill flashes its accent background with "Copied".
    /// Lets the user grab the OTP without leaving the password view.
    private func totpPill(_ secret: String) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let code = TOTPGenerator.code(forStoredValue: secret, date: context.date) ?? ""
            let remaining = TOTPGenerator.secondsRemaining(period: 30, date: context.date)
            Button { copyTOTP(code) } label: {
                Group {
                    if totpCopied {
                        Text("Copied")
                            .vaultType(.body).fontWeight(.semibold)
                            .foregroundStyle(theme.color(.onAccent))
                    } else {
                        HStack(spacing: Space.s3) {
                            // OTP is a typographic object (rule 4): same MonoLisa
                            // treatment as `TOTPCodeView`'s live code, not raw SF.
                            Text(TOTPCodeView.format(code))
                                .font(.vaultCode(.title3, weight: .semibold)).monospacedDigit()
                                .themedForeground(.primary)
                            CountdownRing(remaining: remaining, period: 30)
                        }
                    }
                }
                .frame(minWidth: 150)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .background { if totpCopied { Capsule().fill(theme.color(.accent)) } }
            .headerGlassCapsule()
            .animation(.easeOut(duration: 0.18), value: totpCopied)
        }
        .padding(.bottom, Space.s6)
    }

    private func copyTOTP(_ code: String) {
        guard !code.isEmpty else { return }
        env.clipboard.copy(code, label: "2FA code")
        totpCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.3)) { totpCopied = false }
        }
    }

    /// One character cell: the glyph, a 1-based index below, tap to toggle "entered".
    private func cell(index: Int, character: Character) -> some View {
        let isEntered = entered.contains(index)
        return VStack(spacing: 2) {
            Text(String(character))
                .font(.vaultCode(size: fontSize))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(isEntered ? theme.color(.onAccent)
                                           : SecretColoring.color(for: character, theme: theme))
                .frame(maxWidth: .infinity)
            Text("\(index + 1)")
                .vaultType(.caption)
                .foregroundStyle(isEntered ? theme.color(.onAccent).opacity(0.85)
                                           : theme.color(.secondary))
        }
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity)
        .background(isEntered ? AnyShapeStyle(theme.color(.accent))
                              : AnyShapeStyle(VaultColors.fill),
                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            if isEntered { entered.remove(index) } else { entered.insert(index) }
        }
        .animation(.easeOut(duration: 0.12), value: isEntered)
    }
}
