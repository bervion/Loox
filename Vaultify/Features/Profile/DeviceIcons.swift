import Foundation

/// FontAwesome6 Duotone device-type glyphs for the Profile Devices list — imported into
/// `Assets.xcassets/DeviceIcons` (an `fa_` prefix keeps them out of `PolarisIconCatalog`'s
/// item-icon picker, a separate namespace from the Polaris set). Rendered through the same
/// template-vector pipeline as Polaris icons (`PolarisIcon`, `.renderingMode(.template)`): the
/// source SVGs keep FontAwesome's original two-layer opacity styling (the "secondary" shape at
/// 40% opacity, "primary" at 100%), which Xcode's SVG asset pipeline preserves per pixel — so a
/// single `.foregroundStyle` tint reproduces the duotone shading at both opacities with no
/// flattening or manual re-drawing (verified via an `actool` compile of the raw SVGs, which
/// produced a non-opaque template rendition, plus a direct SVG render confirming the two
/// opacity tiers survive).
enum DeviceIcons {
    static let iphone = "fa_mobile_notch"
    static let ipad = "fa_tablet_screen"
    static let laptop = "fa_laptop"
    static let speaker = "fa_computer_speaker"
    static let desktopClassic = "fa_computer_classic"
    static let display = "fa_display"
    static let watch = "fa_watch_apple"
    static let visionPro = "fa_glasses"
}

/// Maps a `VaultDevice.model` (from `DeviceRegistryService`, ultimately a marketing name
/// resolved by `DeviceModelNames` off the device's hardware identifier — e.g. "iPhone 16 Pro
/// Max", "iPad Pro 11-inch (M4)", or a future non-UIKit "Mac") to the closest `DeviceIcons`
/// glyph via substring matching. Falls back to the iPhone glyph for anything unrecognized: this
/// app currently ships iPhone-only (see `CLAUDE.md`), so an unrecognized `model` string is
/// still overwhelmingly likely to BE an iPhone; the fuller mapping stays ready for a future
/// Mac/iPad/Watch companion that publishes its own `OwnerDevice` record.
enum DeviceIconMapping {
    static func icon(forModel model: String) -> String {
        let normalized = model.lowercased()
        if normalized.contains("vision") { return DeviceIcons.visionPro }
        if normalized.contains("watch") { return DeviceIcons.watch }
        if normalized.contains("ipad") { return DeviceIcons.ipad }
        if normalized.contains("homepod") || normalized.contains("speaker") { return DeviceIcons.speaker }
        if normalized.contains("imac") { return DeviceIcons.display }
        if normalized.contains("macbook") { return DeviceIcons.laptop }
        // Order matters: these all contain "mac" and must be checked before the generic
        // Mac fallback below.
        if normalized.contains("mac mini") || normalized.contains("macmini")
            || normalized.contains("mac studio") || normalized.contains("macstudio") {
            return DeviceIcons.desktopClassic
        }
        if normalized.contains("mac") { return DeviceIcons.laptop }
        if normalized.contains("iphone") { return DeviceIcons.iphone }
        return DeviceIcons.iphone // iPhone-only app today (CLAUDE.md) — unrecognized models default here too.
    }
}
