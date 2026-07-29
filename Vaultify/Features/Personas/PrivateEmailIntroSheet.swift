import SwiftUI

/// Explains private email, and gets the one prerequisite out of the way.
///
/// The relay refuses to forward to an address whose owner has not confirmed it,
/// and nothing said so: tapping "Create private email" in the item editor sent
/// the command, got refused, and reported a connection problem. This is what
/// that tap opens instead — what the feature does, then the confirmation step,
/// with the send button right here so the answer is not "go somewhere else".
///
/// Same shape as `ItemTypePickerSheet` (plain canvas, dots ring, rows on the
/// secondary surface, brand blue glyphs); the ring fronts an envelope.
struct PrivateEmailIntroSheet: View {
    /// The inbox awaiting confirmation, as it stood when the sheet opened. Nil
    /// when the destination is already verified — the sheet is then purely an
    /// explainer.
    let inbox: ForwardingInbox?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var verification = ForwardingInboxVerification()

    /// Re-read from the vault every render. The value handed in is a snapshot,
    /// so sending or confirming from this sheet would leave the card describing
    /// the state the user arrived in rather than the one they just reached.
    private var live: ForwardingInbox? {
        guard let inbox else { return nil }
        return env.repository.forwardingInboxes.first { $0.id == inbox.id } ?? inbox
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(rgb: env.theme.active.background).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Space.s5) {
                        LooxDotsAvatar(size: 104, revealsOnAppear: true,
                                       centerSystemIcon: "envelope.fill")
                            .padding(.top, Space.s4)

                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text("Private email")
                                .vaultType(.screenTitle)
                                .themedForeground(.primary)
                            Text("Give a site its own address instead of your real one. Mail still reaches your inbox, and the site never learns where.")
                                .vaultType(.subhead)
                                .themedForeground(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.gutter)

                        VStack(spacing: Space.s3) {
                            explainerRow(icon: Icons.mail,
                                         title: "A different address for each site",
                                         blurb: "Each site gets its own address, so a leak at one of them never points at you.")
                            explainerRow(icon: Icons.enter,
                                         title: "Mail arrives as usual",
                                         blurb: "Messages forward to your real inbox. Only you can see which address they came through.")
                            explainerRow(icon: Icons.hide,
                                         title: "Turn one off and the mail stops",
                                         blurb: "If an address starts getting spam, pause or delete it. Every other one keeps working.")
                        }
                        .padding(.horizontal, Space.gutter)

                        if let live { confirmationCard(live) }
                    }
                    .padding(.bottom, Space.s8)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("")
            .platformNavigationBarTitleDisplayMode(.inline)
            .platformHiddenNavigationBarBackground()
            .toolbar {
                ToolbarItem(placement: .platformTopBarLeading) {
                    Button { dismiss() } label: {
                        VaultIcon(Icons.close, size: Metric.iconInline)
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
            .alert(Text(verbatim: verification.outcome?.title ?? ""),
                   isPresented: outcomeBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: verification.outcome?.body ?? "")
            }
        }
        .platformPresentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func explainerRow(icon: String, title: LocalizedStringKey,
                              blurb: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VaultIcon(icon, size: 24)
                .foregroundStyle(Color.looxBlue)
                .frame(width: Metric.controlSmall, alignment: .top)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .vaultType(.headline)
                    .themedForeground(.primary)
                Text(blurb)
                    .vaultType(.subhead)
                    .themedForeground(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(rgb: env.theme.active.secondaryBackground),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// The prerequisite, stated plainly and actionable on the spot. Sending is
    /// what puts the link in the user's inbox, so it carries the same busy state
    /// and resend cooldown as the inbox screens — one tap, one email.
    @ViewBuilder
    private func confirmationCard(_ inbox: ForwardingInbox) -> some View {
        if inbox.verificationStatus == .verified {
            // Confirmed while the sheet was open: say so and stop offering a
            // step that is already done.
            HStack(alignment: .top, spacing: Space.s3) {
                VaultIcon(Icons.checkCircle, size: 24).themedForeground(.success)
                Text("This address is verified. Private addresses can forward to it now.")
                    .vaultType(.subhead)
                    .themedForeground(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(rgb: env.theme.active.secondaryBackground),
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .padding(.horizontal, Space.gutter)
        } else {
            pendingConfirmationCard(inbox)
        }
    }

    private func pendingConfirmationCard(_ inbox: ForwardingInbox) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("One step first")
                .vaultType(.headline)
                .themedForeground(.primary)
            Text("Private addresses forward to \(EmailMask.masked(inbox.email)). Confirm that inbox is yours and you can start creating addresses. You can manage all of this later in Private Email.")
                .vaultType(.subhead)
                .themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task {
                    if inbox.verificationStatus == .pending, verification.resendWait(for: inbox) > 0 {
                        await verification.check(inbox, relay: env.relay)
                    } else {
                        await verification.send(to: inbox, relay: env.relay)
                    }
                }
            } label: {
                HStack(spacing: Space.s2) {
                    if verification.isBusy(inbox) {
                        ProgressView().controlSize(.small)
                    }
                    Text(verbatim: actionTitle(inbox))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
            .disabled(verification.isBusy(inbox))

            if inbox.verificationStatus == .pending {
                Text("Already opened the link? Tap again to check.")
                    .vaultType(.caption)
                    .themedForeground(.tertiary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(rgb: env.theme.active.secondaryBackground),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .padding(.horizontal, Space.gutter)
    }

    /// One button, three jobs — send, wait, then check — so the card never shows
    /// an action the relay would refuse.
    private func actionTitle(_ inbox: ForwardingInbox) -> String {
        let wait = verification.resendWait(for: inbox)
        if wait > 0 {
            return inbox.verificationStatus == .pending
                ? appString("Check confirmation")
                : appString("Send again in \(wait)s")
        }
        return inbox.verificationStatus == .pending
            ? appString("Send the email again")
            : appString("Send confirmation email")
    }

    private var outcomeBinding: Binding<Bool> {
        Binding(get: { verification.outcome != nil },
                set: { if !$0 { verification.outcome = nil } })
    }
}
