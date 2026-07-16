import Foundation

/// Maps a device's raw hardware identifier (`hw.machine`, e.g. "iPhone17,2") to its Apple
/// marketing name (e.g. "iPhone 16 Pro Max"). `UIDevice.current.model` only ever returns the
/// generic "iPhone"/"iPad", and `UIDevice.current.name` is the user's own device name (also
/// generic since iOS 16) — neither says WHICH iPhone/iPad this actually is.
/// `DeviceRegistryService` reads the raw identifier itself (`hw.machine` via `uname`, with a
/// Simulator fallback) and looks it up here so the Profile Devices list can show a real model
/// name instead.
///
/// `table` is current through the iPhone 17 / iPhone Air lineup (Sep 2025) and iPad Pro/Air
/// (M5, 2025). Pure lookup, no I/O — trivially testable and shareable across the app + AutoFill
/// extension. A device identifier missing from `table` (released after this table was last
/// updated) never crashes and never returns an empty string: `marketingName(forIdentifier:)`
/// falls back to a generic name derived from the family prefix ("iPhone19,1" → "iPhone"), or,
/// if even the prefix is unrecognized, the raw identifier itself — always something sensible.
nonisolated enum DeviceModelNames {

    /// Marketing name for a raw hardware identifier. Pure lookup — see `DeviceRegistryService`
    /// for how the identifier itself is read off the device.
    static func marketingName(forIdentifier identifier: String) -> String {
        if let known = table[identifier] { return known }
        return genericFallback(forIdentifier: identifier)
    }

    // MARK: Fallback

    /// A device newer than `table` still gets a sensible generic name from its family prefix
    /// (checked most-specific-first, mirroring `DeviceIconMapping`'s own ordering discipline).
    /// If even the prefix is unrecognized, the raw identifier is returned verbatim — still
    /// informative (e.g. "PearPhone9,9" still reads as a phone) and never empty.
    private static func genericFallback(forIdentifier identifier: String) -> String {
        let normalized = identifier.lowercased()
        if normalized.hasPrefix("iphone") { return "iPhone" }
        if normalized.hasPrefix("ipad") { return "iPad" }
        if normalized.hasPrefix("watch") { return "Apple Watch" }
        if normalized.hasPrefix("realitydevice") { return "Apple Vision Pro" }
        // Most-specific Mac families first — "imac"/"macbook" both also contain "mac" and must
        // be checked before the generic Mac fallback below (same ordering trap documented in
        // `DeviceIconMapping`).
        if normalized.hasPrefix("imac") { return "iMac" }
        if normalized.hasPrefix("macbook") { return "MacBook" }
        if normalized.hasPrefix("mac") || normalized == "arm64" || normalized == "x86_64" || normalized == "i386" {
            return "Mac"
        }
        // Truly empty only happens if a caller passes "" directly (the real hardware reader in
        // `DeviceRegistryService` never returns an empty string) — still must never surface a
        // blank row title, so this is the one place that needs a translated string rather than
        // an English proper noun; reuses the catalog key already shipped for the CloudKit
        // "missing name" fallback rather than adding a new one.
        guard !identifier.isEmpty else { return appString("Unknown device") }
        return identifier
    }

    // MARK: Table

    private static let table: [String: String] = [
        // MARK: iPhone (XS/XR, the oldest iOS 17-capable models, through iPhone 17 / iPhone Air)
        "iPhone11,2": "iPhone XS",
        "iPhone11,4": "iPhone XS Max",
        "iPhone11,6": "iPhone XS Max",
        "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd generation)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro",
        "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,3": "iPhone 17",
        "iPhone18,4": "iPhone Air",
        "iPhone18,5": "iPhone 17e",

        // MARK: iPad — base
        "iPad7,5": "iPad (6th generation)",
        "iPad7,6": "iPad (6th generation)",
        "iPad7,11": "iPad (7th generation)",
        "iPad7,12": "iPad (7th generation)",
        "iPad11,6": "iPad (8th generation)",
        "iPad11,7": "iPad (8th generation)",
        "iPad12,1": "iPad (9th generation)",
        "iPad12,2": "iPad (9th generation)",
        "iPad13,18": "iPad (10th generation)",
        "iPad13,19": "iPad (10th generation)",
        "iPad15,7": "iPad (A16)",
        "iPad15,8": "iPad (A16)",

        // MARK: iPad mini
        "iPad11,1": "iPad mini (5th generation)",
        "iPad11,2": "iPad mini (5th generation)",
        "iPad14,1": "iPad mini (6th generation)",
        "iPad14,2": "iPad mini (6th generation)",
        "iPad16,1": "iPad mini (A17 Pro)",
        "iPad16,2": "iPad mini (A17 Pro)",

        // MARK: iPad Air
        "iPad11,3": "iPad Air (3rd generation)",
        "iPad11,4": "iPad Air (3rd generation)",
        "iPad13,1": "iPad Air (4th generation)",
        "iPad13,2": "iPad Air (4th generation)",
        "iPad13,16": "iPad Air (5th generation)",
        "iPad13,17": "iPad Air (5th generation)",
        "iPad14,8": "iPad Air 11-inch (M2)",
        "iPad14,9": "iPad Air 11-inch (M2)",
        "iPad14,10": "iPad Air 13-inch (M2)",
        "iPad14,11": "iPad Air 13-inch (M2)",
        "iPad15,3": "iPad Air 11-inch (M3)",
        "iPad15,4": "iPad Air 11-inch (M3)",
        "iPad15,5": "iPad Air 13-inch (M3)",
        "iPad15,6": "iPad Air 13-inch (M3)",

        // MARK: iPad Pro
        "iPad8,1": "iPad Pro 11-inch (1st generation)",
        "iPad8,2": "iPad Pro 11-inch (1st generation)",
        "iPad8,3": "iPad Pro 11-inch (1st generation)",
        "iPad8,4": "iPad Pro 11-inch (1st generation)",
        "iPad8,5": "iPad Pro 12.9-inch (3rd generation)",
        "iPad8,6": "iPad Pro 12.9-inch (3rd generation)",
        "iPad8,7": "iPad Pro 12.9-inch (3rd generation)",
        "iPad8,8": "iPad Pro 12.9-inch (3rd generation)",
        "iPad8,9": "iPad Pro 11-inch (2nd generation)",
        "iPad8,10": "iPad Pro 11-inch (2nd generation)",
        "iPad8,11": "iPad Pro 12.9-inch (4th generation)",
        "iPad8,12": "iPad Pro 12.9-inch (4th generation)",
        "iPad13,4": "iPad Pro 11-inch (3rd generation)",
        "iPad13,5": "iPad Pro 11-inch (3rd generation)",
        "iPad13,6": "iPad Pro 11-inch (3rd generation)",
        "iPad13,7": "iPad Pro 11-inch (3rd generation)",
        "iPad13,8": "iPad Pro 12.9-inch (5th generation)",
        "iPad13,9": "iPad Pro 12.9-inch (5th generation)",
        "iPad13,10": "iPad Pro 12.9-inch (5th generation)",
        "iPad13,11": "iPad Pro 12.9-inch (5th generation)",
        "iPad14,3": "iPad Pro 11-inch (4th generation)",
        "iPad14,4": "iPad Pro 11-inch (4th generation)",
        "iPad14,5": "iPad Pro 12.9-inch (6th generation)",
        "iPad14,6": "iPad Pro 12.9-inch (6th generation)",
        "iPad16,3": "iPad Pro 11-inch (M4)",
        "iPad16,4": "iPad Pro 11-inch (M4)",
        "iPad16,5": "iPad Pro 13-inch (M4)",
        "iPad16,6": "iPad Pro 13-inch (M4)",
        "iPad17,1": "iPad Pro 11-inch (M5)",
        "iPad17,2": "iPad Pro 11-inch (M5)",
        "iPad17,3": "iPad Pro 13-inch (M5)",
        "iPad17,4": "iPad Pro 13-inch (M5)",

        // MARK: Apple Watch
        "Watch1,1": "Apple Watch (1st generation)",
        "Watch1,2": "Apple Watch (1st generation)",
        "Watch2,3": "Apple Watch Series 2",
        "Watch2,4": "Apple Watch Series 2",
        "Watch2,6": "Apple Watch Series 1",
        "Watch2,7": "Apple Watch Series 1",
        "Watch3,1": "Apple Watch Series 3",
        "Watch3,2": "Apple Watch Series 3",
        "Watch3,3": "Apple Watch Series 3",
        "Watch3,4": "Apple Watch Series 3",
        "Watch4,1": "Apple Watch Series 4",
        "Watch4,2": "Apple Watch Series 4",
        "Watch4,3": "Apple Watch Series 4",
        "Watch4,4": "Apple Watch Series 4",
        "Watch5,1": "Apple Watch Series 5",
        "Watch5,2": "Apple Watch Series 5",
        "Watch5,3": "Apple Watch Series 5",
        "Watch5,4": "Apple Watch Series 5",
        "Watch5,9": "Apple Watch SE",
        "Watch5,10": "Apple Watch SE",
        "Watch5,11": "Apple Watch SE",
        "Watch5,12": "Apple Watch SE",
        "Watch6,1": "Apple Watch Series 6",
        "Watch6,2": "Apple Watch Series 6",
        "Watch6,3": "Apple Watch Series 6",
        "Watch6,4": "Apple Watch Series 6",
        "Watch6,6": "Apple Watch Series 7",
        "Watch6,7": "Apple Watch Series 7",
        "Watch6,8": "Apple Watch Series 7",
        "Watch6,9": "Apple Watch Series 7",
        "Watch6,10": "Apple Watch SE (2nd generation)",
        "Watch6,11": "Apple Watch SE (2nd generation)",
        "Watch6,12": "Apple Watch SE (2nd generation)",
        "Watch6,13": "Apple Watch SE (2nd generation)",
        "Watch6,14": "Apple Watch Series 8",
        "Watch6,15": "Apple Watch Series 8",
        "Watch6,16": "Apple Watch Series 8",
        "Watch6,17": "Apple Watch Series 8",
        "Watch6,18": "Apple Watch Ultra",
        "Watch7,1": "Apple Watch Series 9",
        "Watch7,2": "Apple Watch Series 9",
        "Watch7,3": "Apple Watch Series 9",
        "Watch7,4": "Apple Watch Series 9",
        "Watch7,5": "Apple Watch Ultra 2",
        "Watch7,8": "Apple Watch Series 10",
        "Watch7,9": "Apple Watch Series 10",
        "Watch7,10": "Apple Watch Series 10",
        "Watch7,11": "Apple Watch Series 10",
        "Watch7,12": "Apple Watch Ultra 3",
        "Watch7,13": "Apple Watch SE (3rd generation)",
        "Watch7,14": "Apple Watch SE (3rd generation)",
        "Watch7,15": "Apple Watch SE (3rd generation)",
        "Watch7,16": "Apple Watch SE (3rd generation)",
        "Watch7,17": "Apple Watch Series 11",
        "Watch7,18": "Apple Watch Series 11",
        "Watch7,19": "Apple Watch Series 11",
        "Watch7,20": "Apple Watch Series 11",

        // MARK: Apple Vision Pro
        "RealityDevice14,1": "Apple Vision Pro",

        // MARK: Mac — future companions (not a shipping destination today; a modest,
        // high-confidence sample across the product families rather than the full unified
        // "MacXX,Y" catalog Apple moved to from 2023 onward, which reuses the same numeric
        // family across unrelated products and isn't reliably distinguishable without a much
        // larger verified table. Anything missing here still resolves to "Mac" via the generic
        // fallback below.
        "MacBookAir10,1": "MacBook Air (M1, 2020)",
        "MacBookPro17,1": "MacBook Pro (13-inch, M1, 2020)",
        "MacBookPro18,1": "MacBook Pro (16-inch, M1 Pro/Max, 2021)",
        "MacBookPro18,2": "MacBook Pro (16-inch, M1 Pro/Max, 2021)",
        "MacBookPro18,3": "MacBook Pro (14-inch, M1 Pro/Max, 2021)",
        "MacBookPro18,4": "MacBook Pro (14-inch, M1 Pro/Max, 2021)",
        "Macmini9,1": "Mac mini (M1, 2020)",
        "iMac21,1": "iMac (24-inch, M1, 2021)",
        "iMac21,2": "iMac (24-inch, M1, 2021)",
        "Mac13,1": "Mac Studio (M1 Max, 2022)",
        "Mac13,2": "Mac Studio (M1 Ultra, 2022)",
        "Mac14,2": "MacBook Air (M2, 2022)",
    ]
}
