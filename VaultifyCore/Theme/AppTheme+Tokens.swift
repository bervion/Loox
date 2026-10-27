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
    /// Quiet idle surface for tiles nested inside a card. The dark control
    /// surface stays distinct from its parent without applying a pressed tint.
    var surfaceInset: UInt32 { isDark ? controlBackground : secondaryBackground }
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
    /// Normal-sized explanatory and status text on content surfaces. Opt-in
    /// roles keep the existing control/icon palette while meeting the body
    /// text contrast floor on cards, grouped canvas, inset tiles and pressed controls.
    var secondaryBodyText: UInt32 { bodyTextColor(secondaryText) }
    var successBodyText: UInt32 { bodyTextColor(success) }
    var warningBodyText: UInt32 { bodyTextColor(warning) }

    private func bodyTextColor(_ color: UInt32) -> UInt32 {
        [background, secondaryBackground, groupedBackground, elevatedBackground,
         controlBackground, surfacePressed].reduce(color) {
            RGBMath.ensureContrast($0, on: $1, floor: 4.5)
        }
    }

    // MARK: Accent
    /// Low-emphasis accent surface (banners, soft chips, secondary buttons).
    /// The raw `selection` tint is tuned for LIST-ROW selection and is so pale
    /// it sinks into the grouped background in light mode — pull it 15% toward
    /// the accent so soft surfaces read as deliberate tinted chips everywhere.
    var accentSoft: UInt32 { RGBMath.blend(selection, accent, 0.15) }
    /// Deepened accent for pressed filled controls.
    var accentPress: UInt32 { RGBMath.blend(accent, 0x000000, 0.16) }
    /// The accent as a FILLED CONTROL's background, paired with
    /// `accentForeground`. Identical to `accent` for every preset that already
    /// carries white; a hue that sits just under the floor (the brand blue
    /// measures 2.89:1) is darkened by the minimum that lets white pass, so a
    /// filled button reads white-on-colour instead of black-on-colour. Use it
    /// wherever the accent is PAINTED behind a label — `accent` itself stays
    /// the untouched brand hue for text, icons, rings, and strokes.
    var accentFill: UInt32 { RGBMath.controlFill(accent) }
    /// TEXT-rank accent (Controlled Contrast): the accent hue is tuned as a
    /// FILL — several presets sit at 3.0-4.4:1 as text on soft/control fills,
    /// below the 4.5:1 normal-text floor. This variant is the same hue nudged
    /// in luminance until it clears 4.5:1 on BOTH tinted-control surfaces
    /// (controlBackground and accentSoft). Use it for links, tinted-button
    /// labels, and any accent-colored text or interactive glyph; keep raw
    /// `accent` for fills only. Passing presets come through byte-identical.
    /// Both guards blend the same direction (toward the mode's on-color), so
    /// the sequential application preserves the first constraint.
    var accentText: UInt32 {
        // Brand pairing first: the brand blue ships a dedicated link hue
        // (#0065F4, ~5:1 on white). Derived presets keep the guarded accent.
        // Floor 3.0 (AA-large / UI-component) per the user-locked 260713 call.
        let base = linkAccent ?? accent
        let onControl = RGBMath.ensureContrast(base, on: controlBackground, floor: 3.0)
        return RGBMath.ensureContrast(onControl, on: accentSoft, floor: 3.0)
    }

    // MARK: Separators
    /// Opaque hairline variant (for surfaces where a translucent separator is invisible).
    var separatorOpaque: UInt32 { border }

    // MARK: Status — on-color + soft surface pairs
    /// The destructive hue as a FILLED CONTROL's background, paired with
    /// `onDestructive`: darkened by the minimum that lets a white label clear
    /// 4.5:1 (normal-text AA, so it holds under Increase Contrast as well).
    /// The raw hue is tuned to sit on surfaces; under a label it measured
    /// 2.8 to 3.9:1 against white, and the max-contrast answer was BLACK text
    /// on a red button. Same budgeted darkening as the error banner fill, so
    /// the two reds match. Keep raw `destructive` for text, icons and strokes.
    var destructiveFill: UInt32 { RGBMath.controlFill(destructive, floor: 4.5, maxDarken: 0.25) }
    /// Label on `destructiveFill`: white wherever it clears the control floor.
    var onDestructive: UInt32 { RGBMath.onAccent(destructiveFill) }
    var onSuccess: UInt32 { RGBMath.onColor(success) }
    var onWarning: UInt32 { RGBMath.onColor(warning) }
    var destructiveSoft: UInt32 { RGBMath.blend(destructive, background, isDark ? 0.82 : 0.90) }
    var successSoft: UInt32 { RGBMath.blend(success, background, isDark ? 0.82 : 0.90) }
    var warningSoft: UInt32 { RGBMath.blend(warning, background, isDark ? 0.82 : 0.90) }

    // MARK: Status — text rank
    /// TEXT-rank warning, the `accentText` idiom applied to the warning hue: the
    /// stored `warning` is tuned as a FILL, so a glyph or label drawn in it can
    /// sink into `warningSoft` (Day Classic measures 3.25:1 raw). Guarded on both
    /// tinted surfaces it can sit on, at the same user-locked 3.0 floor
    /// (AA-large / UI-component) as `accentText`; passing themes come through
    /// byte-identical. Use for warning glyphs and warning text-link labels.
    var warningText: UInt32 {
        let onControl = RGBMath.ensureContrast(warning, on: controlBackground, floor: 3.0)
        return RGBMath.ensureContrast(onControl, on: warningSoft, floor: 3.0)
    }
    /// TEXT-rank destructive, derived exactly like `warningText`. Use for
    /// destructive glyphs and text-link labels; keep raw `destructive` for fills.
    var destructiveText: UInt32 {
        let onControl = RGBMath.ensureContrast(destructive, on: controlBackground, floor: 3.0)
        return RGBMath.ensureContrast(onControl, on: destructiveSoft, floor: 3.0)
    }
}
