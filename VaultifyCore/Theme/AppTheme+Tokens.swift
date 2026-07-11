import Foundation

/// Derived semantic color tokens that round out the Design System palette without
/// changing `AppTheme`'s stored fields — so every builtin and custom theme gets them
/// for free. All are computed from the resolved base tokens + accent via `RGBMath`,
/// keeping a single source of truth and staying pure / off-main safe.
nonisolated extension AppTheme {
    // MARK: Surfaces
    /// Standard card / panel surface.
    var surfaceBase: UInt32 { elevatedBackground }
    /// Raised cards, sheets, menus.
    var surfaceElevated: UInt32 { elevatedBackground }
    /// Solid fallback for the floating control layer (tab bar, toolbars) when Liquid
    /// Glass / translucency is unavailable or Reduce Transparency is on.
    var surfaceFloatingSolid: UInt32 { barBackground }
    /// Subtle pressed / touch state drawn over a surface.
    var surfacePressed: UInt32 { RGBMath.blend(controlBackground, primaryText, isDark ? 0.14 : 0.08) }

    // MARK: Icons (DS icon roles)
    var iconPrimary: UInt32 { primaryText }
    var iconSecondary: UInt32 { secondaryText }
    var iconDisabled: UInt32 { placeholderText }

    // MARK: Text
    var textDisabled: UInt32 { placeholderText }

    // MARK: Accent
    /// Low-emphasis accent surface (banners, soft chips, secondary buttons).
    /// The raw `selection` tint is tuned for LIST-ROW selection and is so pale
    /// it sinks into the grouped background in light mode — pull it 15% toward
    /// the accent so soft surfaces read as deliberate tinted chips everywhere.
    var accentSoft: UInt32 { RGBMath.blend(selection, accent, 0.15) }
    /// Deepened accent for pressed filled controls.
    var accentPress: UInt32 { RGBMath.blend(accent, 0x000000, 0.16) }

    // MARK: Separators
    /// Opaque hairline variant (for surfaces where a translucent separator is invisible).
    var separatorOpaque: UInt32 { border }

    // MARK: Status — on-color + soft surface pairs
    var onDestructive: UInt32 { RGBMath.onColor(destructive) }
    var onSuccess: UInt32 { RGBMath.onColor(success) }
    var onWarning: UInt32 { RGBMath.onColor(warning) }
    var destructiveSoft: UInt32 { RGBMath.blend(destructive, background, isDark ? 0.82 : 0.90) }
    var successSoft: UInt32 { RGBMath.blend(success, background, isDark ? 0.82 : 0.90) }
    var warningSoft: UInt32 { RGBMath.blend(warning, background, isDark ? 0.82 : 0.90) }
}
