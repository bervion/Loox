import SwiftUI

/// The single layout for a full-surface STATE: loading, blocked, outcome, error,
/// or a ceremony step that owns the whole sheet.
///
/// Why this exists: every sharing/pairing sheet used to hand-roll its states as
/// `VStack { glyph; Text(...).secondary.multilineTextAlignment(.center) }` closed
/// with `.frame(maxWidth: .infinity, maxHeight: .infinity)`. That produces the
/// "grey paragraph floating in an empty screen" shape, and it pushes the primary
/// action into the vertical middle, out of the thumb zone (DNA rule 6).
///
/// The contract here, matching `QuickLinkResultView` and the onboarding/Level-2
/// screens:
/// - **Top-anchored, left-aligned.** Content reads top-down. Nothing is centred
///   except a deliberately centred `feature` block (a code card, a QR).
/// - **Title carries the rank, not the body.** The headline is `.screenTitle` at
///   PRIMARY; body copy is `.body` at SECONDARY and stays short. A state whose
///   only content is secondary text has no hierarchy at all.
/// - **The CTA is anchored to the bottom edge**, never floated mid-screen, and it
///   holds that edge when the keyboard opens.
/// - **Always scrollable.** VI copy runs ~1.5-2.3x English; at Dynamic Type XL a
///   fixed stack clips.
///
///     VaultStatusScreen(icon: Icons.checkCircle, tint: .success,
///                       title: "Access shared",
///                       message: "They can use the fields you chose.",
///                       primary: .init(title: "Done") { dismiss() })
///
/// For a busy state pass `busy: true` and omit the icon — the spinner takes the
/// glyph slot, so loading and outcome states share one silhouette instead of
/// jumping between two layouts. Note the parameter ORDER when doing so:
/// `busy` follows `message`, matching the visual order of the parts.
///
///     VaultStatusScreen(title: "Sharing your Space", busy: true)
struct VaultStatusScreen<Feature: View>: View {
    @Environment(AppEnvironment.self) private var env
    /// A bottom-anchored action. `enabled: false` paints the opaque disabled
    /// surface (never `.opacity`) via `BrandCapsuleCTA`.
    struct Action {
        let title: LocalizedStringKey
        var enabled: Bool = true
        var busy: Bool = false
        let action: () -> Void

        init(title: LocalizedStringKey, enabled: Bool = true, busy: Bool = false,
             action: @escaping () -> Void) {
            self.title = title
            self.enabled = enabled
            self.busy = busy
            self.action = action
        }
    }

    /// Body copy: a catalog key, or a runtime string (a service error) that the
    /// caller has already localized. Separate cases so a `String` can never
    /// silently bypass the catalog.
    enum Message {
        case key(LocalizedStringKey)
        case verbatim(String)

        fileprivate var resolved: Text {
            switch self {
            case .key(let key): return Text(key)
            case .verbatim(let value): return Text(verbatim: value)
            }
        }
    }

    /// Polaris asset name. Omit when `busy` — the loading swirl occupies the slot.
    var icon: String?
    /// SF Symbol shown inside the loading swirl, naming what is being waited
    /// on (e.g. "link" while a share link is created). Nil keeps the brand mark.
    var busySystemImage: String?
    var tint: ThemeRole = .accent
    var title: LocalizedStringKey?
    var message: Message?
    var busy: Bool = false
    /// Optional block under the copy: a safety-code card, a QR, a field list.
    @ViewBuilder var feature: () -> Feature
    var primary: Action?
    /// Quiet second action, rendered as a text button under the primary. Keep it
    /// at most one (DNA rule 7: no button walls).
    var secondary: Action?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                glyph
                copyBlock
                feature()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s7)
            .padding(.bottom, Space.s5)
            .vaultContentWidth(.form)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom) { actionStack }
    }

    @ViewBuilder
    private var glyph: some View {
        if busy {
            // The brand swirl rather than a system spinner: these waits are
            // seconds of encryption and network, and the looping dots say the
            // app is working on something of its own. The centre names the
            // operation when the caller supplies a symbol.
            LooxSwirlAnimationView(mode: .loop,
                                   logoFraction: 0.30,
                                   centerSystemImage: busySystemImage,
                                   centerTint: Color(rgb: env.theme.active.accent))
                // The swirl needs room for its rings; the static glyph slot
                // would render them as a smudge.
                .frame(width: 132, height: 132)
                .accessibilityHidden(true)
        } else if let icon {
            PolarisIcon(icon, size: Metric.iconTileLarge)
                .themedForeground(tint)
        }
    }

    @ViewBuilder
    private var copyBlock: some View {
        if title != nil || message != nil {
            VStack(alignment: .leading, spacing: Space.s2) {
                if let title {
                    Text(title)
                        .vaultType(.screenTitle)
                        .themedForeground(.primary)
                }
                if let message {
                    message.resolved
                        .vaultType(.body)
                        .themedForeground(.secondary)
                        // Let the paragraph grow instead of truncating: VI is the
                        // long locale and this is often the only explanation on
                        // screen.
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var actionStack: some View {
        if primary != nil || secondary != nil {
            VStack(spacing: Space.s2) {
                if let primary {
                    BrandCapsuleCTA(title: primary.title, enabled: primary.enabled,
                                    busy: primary.busy, action: primary.action)
                }
                if let secondary {
                    Button(action: secondary.action) {
                        Text(secondary.title)
                            .vaultType(.body).fontWeight(.medium)
                            // accentText, not `.secondary`: secondary IS this
                            // app's inactive vocabulary, so a quiet action drawn
                            // in it reads as disabled.
                            .themedForeground(.accentText)
                            .frame(maxWidth: .infinity, minHeight: Metric.hitMin)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!secondary.enabled || secondary.busy)
                    .padding(.horizontal, Space.s6)
                    .padding(.bottom, Space.s4)
                    .vaultContentWidth(.form)
                }
            }
            // Only the actions ignore the keyboard: they hold the bottom edge
            // while the scroll view keeps its keyboard inset.
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }
}

extension VaultStatusScreen where Feature == EmptyView {
    /// The common case: glyph + copy + actions, no extra block.
    init(icon: String? = nil,
         busySystemImage: String? = nil,
         tint: ThemeRole = .accent,
         title: LocalizedStringKey? = nil,
         message: Message? = nil,
         busy: Bool = false,
         primary: Action? = nil,
         secondary: Action? = nil) {
        self.init(icon: icon, busySystemImage: busySystemImage, tint: tint, title: title,
                  message: message, busy: busy,
                  feature: { EmptyView() }, primary: primary, secondary: secondary)
    }
}
