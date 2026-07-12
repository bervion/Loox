//
//  LooxAnimationThemes.swift
//  Vaultify
//
//  Orbit "personas" for the landing animation. Each theme mirrors an
//  iCloud-style cluster: a pastel identity disc in the middle surrounded
//  by six floating capability bubbles. Slot i is the cluster counterpart
//  of logo circle i, so burst/converge morphs stay spatially coherent.
//

import SwiftUI

enum LooxBubbleStyle {
    /// Colored gradient disc with a white glyph.
    case solid([Color])
    /// White disc with a colored glyph.
    case glyphOnWhite(Color)
}

struct LooxOrbitSpec {
    /// Degrees, 0 = right, positive = clockwise (y-down).
    let angle: Double
    /// Distance from cluster center, in canvas units.
    let distance: CGFloat
    let diameter: CGFloat
    let symbol: String
    let style: LooxBubbleStyle

    var point: CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(
            x: LooxCanvas.center.x + cos(radians) * distance,
            y: LooxCanvas.center.y + sin(radians) * distance
        )
    }
}

/// System-style bubble palette, hoisted so theme literals type-check fast.
private enum LooxIconColor {
    static let yellow = Color(looxHex: 0xFFC531)
    static let orange = Color(looxHex: 0xFF9F0A)
    static let deepOrange = Color(looxHex: 0xFF6B00)
    static let green = Color(looxHex: 0x34C759)
    static let deepGreen = Color(looxHex: 0x248A3D)
    static let blue = Color(looxHex: 0x0A84FF)
    static let deepBlue = Color(looxHex: 0x0060DF)
    static let teal = Color(looxHex: 0x30B0C7)
    static let indigo = Color(looxHex: 0x5E5CE6)
    static let deepIndigo = Color(looxHex: 0x3634A3)
    static let pink = Color(looxHex: 0xFF375F)
    static let deepPink = Color(looxHex: 0xFF2D55)
    static let red = Color(looxHex: 0xFF3B30)
    static let purple = Color(looxHex: 0xBF5AF2)
    static let deepPurple = Color(looxHex: 0x8944AB)
    static let ink = Color(looxHex: 0x1C1C1E)
}

struct LooxTheme {
    /// Pastel fill of the central identity disc.
    let tint: Color
    /// Bundle resource of the transparent Memoji clip shown on the disc.
    let memoji: String
    /// Per-clip framing inside the disc: heads occupy different portions
    /// of their recordings, so each needs its own zoom and vertical nudge
    /// (both relative to the disc diameter) to sit optically centered.
    let memojiZoom: CGFloat
    let memojiDrop: CGFloat
    /// Six bubbles, index-matched to the six logo circles.
    let slots: [LooxOrbitSpec]

    static let centerDiameter: CGFloat = 170
    static let centerStarDiameter: CGFloat = 94

    /// Vault essentials — passwords, Face ID, cards.
    static let vault: LooxTheme = {
        var slots: [LooxOrbitSpec] = []
        slots.append(LooxOrbitSpec(angle: 138, distance: 108, diameter: 82, symbol: "key.fill", style: .solid([LooxIconColor.yellow, LooxIconColor.orange])))
        slots.append(LooxOrbitSpec(angle: 188, distance: 116, diameter: 60, symbol: "wifi", style: .glyphOnWhite(LooxIconColor.blue)))
        slots.append(LooxOrbitSpec(angle: 76, distance: 110, diameter: 74, symbol: "faceid", style: .solid([LooxIconColor.green, LooxIconColor.deepGreen])))
        slots.append(LooxOrbitSpec(angle: -136, distance: 114, diameter: 68, symbol: "creditcard.fill", style: .solid([LooxIconColor.blue, LooxIconColor.deepBlue])))
        slots.append(LooxOrbitSpec(angle: -76, distance: 122, diameter: 60, symbol: "lock.shield.fill", style: .glyphOnWhite(LooxIconColor.indigo)))
        slots.append(LooxOrbitSpec(angle: -4, distance: 118, diameter: 96, symbol: "ellipsis.rectangle.fill", style: .solid([Color.looxRoyal, Color.looxDeep])))
        return LooxTheme(tint: Color(looxHex: 0xE3D6FF), memoji: "memoji-wink", memojiZoom: 1.06, memojiDrop: 0.05, slots: slots)
    }()

    /// Sign-in everywhere — web logins, OTP codes, alerts.
    static let signIn: LooxTheme = {
        var slots: [LooxOrbitSpec] = []
        slots.append(LooxOrbitSpec(angle: 130, distance: 112, diameter: 76, symbol: "globe", style: .solid([LooxIconColor.teal, LooxIconColor.blue])))
        slots.append(LooxOrbitSpec(angle: 182, distance: 112, diameter: 64, symbol: "doc.text.fill", style: .glyphOnWhite(LooxIconColor.orange)))
        slots.append(LooxOrbitSpec(angle: 82, distance: 114, diameter: 66, symbol: "touchid", style: .solid([LooxIconColor.pink, LooxIconColor.deepPink])))
        slots.append(LooxOrbitSpec(angle: -142, distance: 110, diameter: 74, symbol: "123.rectangle.fill", style: .solid([LooxIconColor.indigo, LooxIconColor.deepIndigo])))
        slots.append(LooxOrbitSpec(angle: -70, distance: 118, diameter: 64, symbol: "bell.badge.fill", style: .glyphOnWhite(LooxIconColor.red)))
        slots.append(LooxOrbitSpec(angle: 2, distance: 120, diameter: 90, symbol: "envelope.fill", style: .solid([LooxIconColor.blue, Color.looxRoyal])))
        return LooxTheme(tint: Color(looxHex: 0xCDEFDB), memoji: "memoji-gray", memojiZoom: 1.10, memojiDrop: 0.05, slots: slots)
    }()

    /// Sharing & identity — QR, wallet, verified profile.
    static let identity: LooxTheme = {
        var slots: [LooxOrbitSpec] = []
        slots.append(LooxOrbitSpec(angle: 142, distance: 106, diameter: 70, symbol: "qrcode", style: .glyphOnWhite(LooxIconColor.ink)))
        slots.append(LooxOrbitSpec(angle: 192, distance: 114, diameter: 62, symbol: "note.text", style: .glyphOnWhite(LooxIconColor.orange)))
        slots.append(LooxOrbitSpec(angle: 74, distance: 112, diameter: 78, symbol: "checkmark.shield.fill", style: .solid([LooxIconColor.green, LooxIconColor.deepGreen])))
        slots.append(LooxOrbitSpec(angle: -132, distance: 112, diameter: 64, symbol: "wallet.pass.fill", style: .solid([LooxIconColor.orange, LooxIconColor.deepOrange])))
        slots.append(LooxOrbitSpec(angle: -80, distance: 120, diameter: 62, symbol: "at", style: .solid([LooxIconColor.purple, LooxIconColor.deepPurple])))
        slots.append(LooxOrbitSpec(angle: -8, distance: 116, diameter: 92, symbol: "person.badge.key.fill", style: .solid([Color.looxRoyal, Color.looxDeep])))
        return LooxTheme(tint: Color(looxHex: 0xFFE4C4), memoji: "memoji-blond", memojiZoom: 0.98, memojiDrop: 0.03, slots: slots)
    }()

    static let all: [LooxTheme] = [.vault, .signIn, .identity]
}
