import Foundation

/// Centralised icon tokens for app chrome. Categories, Spaces and item avatars carry their
/// own stored `iconAsset` and do not come through here.
///
/// Values are `sf:`-prefixed SF Symbol names resolved by `IconResolver`, so every
/// `VaultIcon(Icons.x)` call site migrated without an edit. Names are pinned to the symbols
/// available on the iOS 17.3 deployment floor — `IconCatalogTests` fails the build if one is not.
enum Icons {
    static let home = IconResolver.token("house")
    static let homeFill = IconResolver.token("house.fill")
    static let search = IconResolver.token("magnifyingglass")
    static let watchtower = IconResolver.token("checkmark.shield")
    /// The Security (Watchtower) tab. Deliberately NOT `organization`: that token means
    /// people, and the tab must not read as a group-of-people glyph.
    static let securityTab = IconResolver.token("checkmark.shield")
    /// Selected state of the Security tab.
    static let securityTabFill = IconResolver.token("checkmark.shield.fill")
    static let settings = IconResolver.token("gearshape")
    static let settingsFill = IconResolver.token("gearshape.fill")
    static let notification = IconResolver.token("bell")
    static let add = IconResolver.token("plus")
    static let addCircle = IconResolver.token("plus.circle")
    static let edit = IconResolver.token("pencil")
    static let delete = IconResolver.token("trash")
    static let trash = IconResolver.token("trash")
    static let copy = IconResolver.token("doc.on.doc")
    static let copyDone = IconResolver.token("checkmark.circle")
    static let reveal = IconResolver.token("eye")
    static let hide = IconResolver.token("eye.slash")
    static let star = IconResolver.token("star")
    static let starFill = IconResolver.token("star.fill")
    static let check = IconResolver.token("checkmark")
    static let checkCircle = IconResolver.token("checkmark.circle")
    static let layoutSection = IconResolver.token("arrow.up.arrow.down")
    static let enter = IconResolver.token("tray.and.arrow.down")
    static let close = IconResolver.token("xmark")
    static let closeCircle = IconResolver.token("xmark.circle")
    static let chevronLeft = IconResolver.token("chevron.left")
    static let chevronRight = IconResolver.token("chevron.right")
    static let chevronDown = IconResolver.token("chevron.down")
    static let arrowRight = IconResolver.token("arrow.right")
    static let lock = IconResolver.token("lock")
    static let lockFill = IconResolver.token("lock.fill")
    static let key = IconResolver.token("key")
    static let creditCard = IconResolver.token("creditcard")
    static let shield = IconResolver.token("checkmark.shield")
    static let shieldAlert = IconResolver.token("exclamationmark.shield")
    /// Shield with a person silhouette — the Vault Audit action glyph.
    static let shieldPerson = IconResolver.token("person.badge.shield.checkmark")
    static let passkey = IconResolver.token("person.badge.key")
    static let personLockFilled = IconResolver.token("person.badge.key.fill")
    /// A protected/anonymous identity — the anonymous persona kind, a paired-device
    /// status, and the shared-access gate. Distinct from `passkey`: a key badge would
    /// claim these are passkeys.
    static let identityShielded = IconResolver.token("lock.circle.fill")
    static let alert = IconResolver.token("exclamationmark.triangle")
    static let refresh = IconResolver.token("arrow.triangle.2.circlepath")
    static let replay = IconResolver.token("arrow.clockwise")
    static let sync = IconResolver.token("arrow.triangle.2.circlepath")
    static let magic = IconResolver.token("sparkles")
    static let clock = IconResolver.token("clock")
    static let globe = IconResolver.token("globe")
    static let share = IconResolver.token("square.and.arrow.up")
    static let info = IconResolver.token("info.circle")
    static let folder = IconResolver.token("folder")
    static let identityCard = IconResolver.token("person.text.rectangle")
    static let orderRepeat = IconResolver.token("arrow.left.arrow.right")
    /// The Recently Used home section. A swap arrow (`orderRepeat`) does not say "recent".
    static let recentlyUsed = IconResolver.token("clock.arrow.circlepath")
    static let inventory = IconResolver.token("tray.full")
    static let hashtag = IconResolver.token("number")
    static let plan = IconResolver.token("flag")
    static let planFill = IconResolver.token("flag.fill")
    static let organization = IconResolver.token("person.2")
    static let organizationFill = IconResolver.token("person.2.fill")
    static let apps = IconResolver.token("square.grid.2x2")
    static let appsFill = IconResolver.token("square.grid.2x2.fill")
    /// The Appearance settings pane. Kept off `appsFill` so the macOS sidebar does not
    /// label Appearance with the All Items glyph.
    static let appearance = IconResolver.token("paintpalette")
    static let pin = IconResolver.token("pin")
    static let pinFill = IconResolver.token("pin.fill")
    static let archive = IconResolver.token("archivebox")
    static let calendar = IconResolver.token("calendar")
    static let chartFill = IconResolver.token("chart.bar.fill")
    static let importData = IconResolver.token("arrow.down.doc")
    static let exportData = IconResolver.token("square.and.arrow.down")
    static let language = IconResolver.token("character.bubble")
    static let scanCode = IconResolver.token("qrcode")
    static let person = IconResolver.token("person")
    /// The canonical email glyph app-wide.
    static let mail = IconResolver.token("envelope")
    static let camera = IconResolver.token("camera")
    static let image = IconResolver.token("photo")
    /// A single device (phone) — used in the Profile Devices list.
    static let device = IconResolver.token("iphone")
    /// Document with a plus badge — used on the Add quick-action tile and header cluster.
    static let pageAdd = IconResolver.token("doc.badge.plus")
    /// Horizontal three-dot overflow — used in the header action cluster.
    static let moreHorizontal = IconResolver.token("ellipsis")
    /// The Reduce Motion accessibility row. Not `reveal`: an eye there reads as "show the secret".
    static let reduceMotion = IconResolver.token("figure.walk.motion")
    /// Suspending something that keeps running (alias forwarding). Not `hide`, which conceals a value.
    static let pause = IconResolver.token("pause.circle")
    /// Reorder / sort control.
    static let sort = IconResolver.token("arrow.up.arrow.down")
    /// Plain-text / large-type affordance.
    static let text = IconResolver.token("textformat")
    /// File attachment.
    static let attachment = IconResolver.token("paperclip")
}
