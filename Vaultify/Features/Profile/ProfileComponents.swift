import SwiftUI

/// Shared building blocks for the Profile hub (Apple-Account-style grouped nav rows).
/// Kept in one place so `ProfileScreen` and its detail screens compose identical chrome.

/// Grouped, elevated card wrapping a run of Profile rows.
struct ProfileGroupCard<Content: View>: View {
    @Environment(AppEnvironment.self) private var env
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(rgb: env.theme.active.elevatedBackground))
            .vaultCornerRadius(Radius.lg)
            .elevation(.level1)
    }
}

/// A glyph source for a `.colored` Profile row tile — either an SF Symbol (Profile-only
/// exception, see `ProfileScreen`) or a template vector asset (a Polaris icon, or one of the
/// FontAwesome device glyphs in `Assets.xcassets/DeviceIcons`).
enum ProfileGlyphSource {
    case sfSymbol(String)
    case templateAsset(String)
}

/// Visual style for a Profile row's leading icon tile. `.polaris` (the default, via
/// `ProfileRowTile.init(icon:)`) is the original tinted-glyph look; the other cases back the
/// Profile-only SF Symbol redesign (Personal Information, Payment, Loox, Family, Devices) — an
/// owner-approved exception to the Polaris-only icon rule, scoped to the Profile screen only
/// (260715).
enum ProfileTileStyle {
    /// Polaris glyph, `.iconSecondary` tint, neutral fill — the original Profile-row look.
    case polaris(String)
    /// SF Symbol, WHITE glyph, solid neutral-gray tile — the iOS-Settings "system row" look
    /// (Personal Information, Payment).
    case system(String)
    /// Glyph, COLORED, on a WHITE tile + hairline border (Family).
    case colored(ProfileGlyphSource, Color)
    /// Glyph, COLORED, NO tile — icon only, still laid out in the same `Metric.badgeTile` frame
    /// so the row title stays aligned with every other row (device rows: the owner wants the
    /// device-type glyph without a badge background, 260715). `tint` is a packed `0xRRGGBB`
    /// rather than `Color`: unlike `.colored`'s fixed-white backdrop, a `.plain` glyph draws
    /// directly on the active THEME's elevated surface, so `ProfileRowTile` re-checks it for
    /// WCAG contrast against that surface at draw time (`RGBMath.ensureContrast`) — `Color`
    /// can't be cheaply read back into that math, so the raw value passes straight through.
    case plain(ProfileGlyphSource, UInt32)
    /// The full-colour Loox brand mark on a WHITE tile + hairline border.
    case brandMark
}

/// 30pt rounded tile holding a Profile row's leading art. `.polaris` (default) keeps the
/// original tinted-glyph look for every row this redesign doesn't touch (Family, Loox Hub,
/// Payment Cards, Approval Mode, …); the other `ProfileTileStyle` cases render the Profile-only
/// SF Symbol redesign.
struct ProfileRowTile: View {
    @Environment(AppEnvironment.self) private var env
    private let style: ProfileTileStyle
    /// Per-call optical size for template-asset glyphs. The 18pt default fits
    /// square-ish art (fa_users); tall NARROW glyphs (the device icons — a phone
    /// is ~3:4) render visually smaller at the same point size and pass a larger
    /// value to sit at the same optical weight in the tile.
    private let assetGlyphOverride: CGFloat?
    /// The tile's side. Rows whose art should span their whole two-line text
    /// block (the Devices list) pass a taller tile than the 30pt default.
    private let tileSize: CGFloat

    /// Original call shape — a Polaris asset name.
    init(icon: String) {
        self.style = .polaris(icon)
        self.assetGlyphOverride = nil
        self.tileSize = Metric.badgeTile
    }

    init(style: ProfileTileStyle, assetGlyphSize: CGFloat? = nil,
         tileSize: CGFloat = Metric.badgeTile) {
        self.style = style
        self.assetGlyphOverride = assetGlyphSize
        self.tileSize = tileSize
    }

    var body: some View {
        Group {
            switch style {
            case .polaris(let icon):
                // Corner radius intentionally stays the pre-redesign literal `8` (not
                // `Radius.sm`/10): this case is still reused by every OTHER screen
                // (Family, Loox Hub, Payment Cards, …), which this redesign doesn't touch —
                // snapping it to a token would visually shift their tiles too.
                VaultIcon(icon, size: 18)
                    .themedForeground(.iconSecondary)
                    .frame(width: tileSize, height: tileSize)
                    .background(VaultColors.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            case .system(let symbol):
                // Profile-only SF Symbols: owner-approved exception to the Polaris-only rule (260715).
                Image(systemName: symbol)
                    .font(.system(size: Self.sfGlyphSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: tileSize, height: tileSize)
                    .background(systemGrayTile, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            case .colored(let source, let tint):
                glyph(source)
                    .foregroundStyle(tint)
                    .frame(width: tileSize, height: tileSize)
                    .background(whiteBadgeBackground)
            case .plain(let source, let tintHex):
                // No fixed backdrop here (that's the point), so the tint must hold contrast
                // against whatever the active THEME actually puts behind it — `ensureContrast`
                // returns `tintHex` byte-identical whenever it already clears the 3:1 non-text
                // floor (true for every built-in theme except `nightTinted`'s navy elevated
                // surface, ~2.65:1 unadjusted) and otherwise nudges it toward black/white by the
                // minimal amount needed, the same non-destructive mechanism `AppTheme` already
                // uses for the accent color.
                glyph(source)
                    .foregroundStyle(Color(rgb: RGBMath.ensureContrast(
                        tintHex, on: env.theme.active.elevatedBackground, floor: 3.0)))
                    .frame(width: tileSize, height: tileSize)
            case .brandMark:
                Image("BrandSymbol")
                    .resizable()
                    .scaledToFit()
                    .padding(Space.s1)
                    .frame(width: tileSize, height: tileSize)
                    .background(whiteBadgeBackground)
            }
        }
        .accessibilityHidden(true)   // the row's title text labels the control
    }

    @ViewBuilder private func glyph(_ source: ProfileGlyphSource) -> some View {
        switch source {
        case .sfSymbol(let name):
            // Profile-only SF Symbols: owner-approved exception to the Polaris-only rule (260715).
            Image(systemName: name).font(.system(size: Self.sfGlyphSize, weight: .semibold))
        case .templateAsset(let name):
            // `VaultIcon` is a generic template-vector renderer (name + size), not literally
            // limited to the Polaris SVG set — reused as-is for the FontAwesome device glyphs.
            VaultIcon(name, size: assetGlyphOverride ?? Self.assetGlyphSize)
        }
    }

    /// SF glyphs read heavier than Polaris/FontAwesome vector strokes at the same point size —
    /// sized down from the 18pt vector-asset glyph so every glyph family sits at the same
    /// optical weight in the same 30pt tile (mirrors `SettingsIconBadge`'s identical,
    /// empirically-tuned note: "SF glyphs carry larger optical bounds than Polaris strokes").
    private static let sfGlyphSize: CGFloat = 14
    private static let assetGlyphSize: CGFloat = 18

    /// Fixed neutral gray (mirrors Apple's `systemGray` / the existing Settings-row system
    /// tint) rather than a text-secondary role: `iconSecondary` tracks `secondaryText`, which
    /// INVERTS value between light/dark (dark gray text in light mode becomes light gray text
    /// in dark mode) and would wash out a white glyph in dark mode.
    private var systemGrayTile: Color { VaultColors.dynamic(light: 0x8E8E93, dark: 0x98989D) }

    /// WHITE tile + hairline border — the Loox/Family/Devices treatment. A literal white fill
    /// (not the themed elevated surface) so brand/coloured art always sits on the same fixed
    /// backdrop in both light and dark, the same class of documented fixed-tile exemption as
    /// `SettingsIconBadge`'s white-on-tint badges (`docs/design-dna-standard.md`); the border
    /// keeps the tile from blending into a near-white light-mode card.
    private var whiteBadgeBackground: some View {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(Color(rgb: 0xFFFFFF))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.75)
            )
    }
}

/// Fixed decorative tints for glyphs drawn on the ALWAYS-WHITE `.colored` badge tile (see
/// `ProfileRowTile.whiteBadgeBackground`). Deliberately fixed rather than a theme role:
/// `success`/`iconSecondary` are tuned against the THEME's own light- or dark-appropriate
/// background and invert value between appearances (paler in dark mode, for legibility on a
/// dark surface) — drawn on a tile that stays white in both modes, the dark-mode variant of
/// either role nearly vanishes (verified: `iconSecondary`'s dark value is ~1.7:1 against white,
/// `success`'s dark value is ~2:1; both fail the 3:1 WCAG floor for non-text UI). These fixed
/// tones hold ≥4:1 against white in both appearances since the backdrop never changes.
enum ProfileBadgeTint {
    /// Family — a calm, family-appropriate green with solid contrast on white (~4.1:1). Used on
    /// the fixed-white `.colored` badge tile only, per the doc comment above.
    static let family = Color(rgb: 0x1A8E5F)
    /// Device-row glyphs — a neutral dark gray, distinct from the colored badges above it
    /// (~5.1:1 on white). Device rows use `.plain` (no fixed white backdrop — see
    /// `ProfileTileStyle.plain`), so `ProfileRowTile` reads `deviceHex` and re-derives contrast
    /// against the active theme's actual surface instead of assuming white.
    static let device = Color(rgb: 0x6E6E73)
    static let deviceHex: UInt32 = 0x6E6E73
}

/// A Profile nav row: leading tile + title + optional trailing value + chevron, pushing
/// `destination` onto the enclosing (navigator-hosted) stack.
struct ProfileNavRow<Destination: View>: View {
    private let titleView: AnyView
    private let tileStyle: ProfileTileStyle
    private let value: String?
    private let destination: () -> Destination

    /// `icon` is a Polaris asset name (the original tile look); `tile` overrides it with the
    /// Profile-only SF Symbol redesign (see `ProfileTileStyle`).
    init(title: LocalizedStringResource, icon: String? = nil, tile: ProfileTileStyle? = nil,
         value: String? = nil, @ViewBuilder destination: @escaping () -> Destination) {
        self.titleView = AnyView(Text(title))
        self.tileStyle = tile ?? .polaris(icon ?? Icons.info)
        self.value = value
        self.destination = destination
    }

    /// Verbatim title for locale-invariant brand nouns.
    init(verbatimTitle: String, icon: String? = nil, tile: ProfileTileStyle? = nil,
         value: String? = nil, @ViewBuilder destination: @escaping () -> Destination) {
        self.titleView = AnyView(Text(verbatim: verbatimTitle))
        self.tileStyle = tile ?? .polaris(icon ?? Icons.info)
        self.value = value
        self.destination = destination
    }

    /// Custom title content (the Loox row renders the tier lockup — "Loox"
    /// plus the MAX badge). The view inherits the row's font and foreground.
    init(titleView: some View, icon: String? = nil, tile: ProfileTileStyle? = nil,
         value: String? = nil, @ViewBuilder destination: @escaping () -> Destination) {
        self.titleView = AnyView(titleView)
        self.tileStyle = tile ?? .polaris(icon ?? Icons.info)
        self.value = value
        self.destination = destination
    }

    var body: some View {
        NavigationLink { destination() } label: {
            HStack(spacing: Space.s3) {
                ProfileRowTile(style: tileStyle)
                titleView.vaultType(.body).themedForeground()
                Spacer(minLength: Space.s2)
                if let value {
                    Text(verbatim: value).vaultType(.subhead).themedForeground(.secondary)
                }
                VaultIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
            }
            .padding(.horizontal, Space.s4)
            .frame(minHeight: Metric.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Leading-inset hairline between two Profile rows (aligns under the title, past the tile).
struct ProfileRowDivider: View {
    @Environment(AppEnvironment.self) private var env
    /// nil = the default inset, aligned with the text after a row tile.
    var leadingInset: CGFloat? = nil

    var body: some View {
        Rectangle()
            .fill(Color(rgb: env.theme.active.separator))
            .frame(height: 0.5)
            .padding(.leading, leadingInset ?? Space.s4 + Metric.badgeTile + Space.s3)
    }
}

/// One row in a devices list — a device-type glyph tile, name + last-seen subtitle, and an
/// "Active" badge for this device. Shared by the Profile hub's inline Devices card
/// (`ProfileDevicesCard`) and `DevicesScreen`, so the two never drift apart.
struct DeviceRow: View {
    @Environment(AppEnvironment.self) private var env
    let device: VaultDevice

    var body: some View {
        HStack(spacing: Space.s3) {
            // A 44pt tile so the device art spans the row's whole two-line text
            // block (the Home avatar's size), with the glyph scaled up to match;
            // the FA device glyphs are tall and narrow (a phone is ~3:4), so the
            // glyph runs bigger than a square asset would at the same weight.
            ProfileRowTile(style: .plain(
                .templateAsset(DeviceIconMapping.icon(forModel: device.model)),
                ProfileBadgeTint.deviceHex), assetGlyphSize: 32, tileSize: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).vaultType(.body).themedForeground().lineLimit(1)
                Text(verbatim: subtitle).vaultType(.subhead).themedForeground(.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            if device.isCurrent { activeBadge }
            VaultIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
        }
        .padding(.horizontal, Space.s4)
        .frame(minHeight: Metric.rowHeight)
        .contentShape(.rect)
    }

    /// The marketing model name ("iPhone 16 Pro Max") rather than `device.name`, which is
    /// generic on iOS 16+ (`UIDevice.current.name` no longer reflects the user's chosen device
    /// name). Falls back to `device.name` only for a legacy CloudKit record published before
    /// `model` carried the marketing name (empty string).
    private var title: String { device.model.isEmpty ? device.name : device.model }

    private var subtitle: String {
        if device.isCurrent { return appString("This device") }
        // Locale-aware relative time ("2 hours ago" / "2 giờ trước") — no catalog strings.
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = appResourceLocale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: device.lastSeenAt, relativeTo: .now)
    }

    /// One line, always. The Vietnamese label ("Đang hoạt động") is more than
    /// twice the English one, so on a 375-414pt phone it wrapped inside the
    /// capsule and pushed the pill to two lines beside a full-width model name.
    /// The badge is a fixed chip: it never wraps, and it never gives up its
    /// width — the model name above it truncates instead, which is the right
    /// thing to lose since the same row already says "This device".
    private var activeBadge: some View {
        Text("Active")
            .vaultType(.caption)
            .themedForeground(.success)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .background(env.theme.active.color(.success).opacity(0.14), in: Capsule())
            .layoutPriority(1)
    }
}

/// Inline Devices card for the Profile hub — the device list itself now lives directly on
/// Profile instead of behind a nav row that pushed `DevicesScreen`. Owns its own load so
/// `ProfileScreen` doesn't need extra state for it; mirrors `DevicesScreen`'s load sequence
/// (kept duplicated there — five lines, no shared-logic risk — rather than reaching into
/// `DeviceRegistryService`, which is outside this redesign's file scope).
struct ProfileDevicesCard: View {
    @Environment(AppEnvironment.self) private var env
    @State private var devices: [VaultDevice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Devices").vaultType(.sectionLabel).themedForeground(.secondary)
            ProfileGroupCard {
                ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                    NavigationLink { DeviceDetailScreen(device: device) } label: {
                        DeviceRow(device: device)
                    }
                    .buttonStyle(.plain)
                    if index < devices.count - 1 { ProfileRowDivider() }
                }
            }
            if devices.count <= 1 {
                Text("Other devices you pair with this vault will appear here.")
                    .vaultType(.footnote).themedForeground(.tertiary)
                    .padding(.horizontal, Space.s2)
            }
        }
        .task { await load() }
        // A sign-out issued from the detail screen filters that device out at once.
        .onReceive(NotificationCenter.default.publisher(for: .vaultDevicesChanged)) { _ in
            Task { await load() }
        }
    }

    private func load() async {
        let service = DeviceRegistryService(settings: env.settings)
        // Show this device immediately (no network), then publish + refresh the mirror.
        if devices.isEmpty { devices = [service.thisDevice] }
        await service.publish()
        let fetched = await service.fetchDevices()
        if !fetched.isEmpty { devices = fetched }
    }
}
