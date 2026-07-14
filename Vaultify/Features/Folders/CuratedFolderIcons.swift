import Foundation

/// Curated FontAwesome-6 **duotone** icon set offered when choosing a Space
/// (folder) icon. Each asset is a two-layer glyph (a full-opacity primary path
/// plus a 40%-opacity secondary path) imported as a template image, so it tints
/// to the Space's chosen color as a single-hue duotone — the modern iOS look —
/// and stays theme-aware. Every name is verified present in
/// `Assets.xcassets/PolarisIcons` so the picker never shows a blank tile.
///
/// Grouped by theme so any kind of vault / Space has a fitting glyph.
enum CuratedFolderIcons {
    static let all: [String] = [
        // General / organization
        "dt_folder", "dt_folder_open", "dt_box", "dt_boxes", "dt_layers", "dt_vault", "dt_archive",
        // People / personal
        "dt_user", "dt_users", "dt_house", "dt_heart", "dt_paw", "dt_baby",
        // Work / business
        "dt_briefcase", "dt_building", "dt_sitemap",
        // Finance
        "dt_bank", "dt_landmark", "dt_wallet", "dt_credit_card", "dt_coins",
        "dt_chart", "dt_bitcoin", "dt_piggy_bank", "dt_receipt",
        // Shopping
        "dt_cart", "dt_bag", "dt_gift", "dt_tag",
        // Communication
        "dt_envelope", "dt_comments", "dt_phone", "dt_at", "dt_share",
        // Travel
        "dt_plane", "dt_car", "dt_map", "dt_globe",
        // Health
        "dt_heart_pulse", "dt_pills", "dt_dumbbell",
        // Education
        "dt_book", "dt_graduation",
        // Tech / security
        "dt_server", "dt_database", "dt_code", "dt_cloud", "dt_wifi",
        "dt_key", "dt_lock", "dt_shield", "dt_fingerprint", "dt_terminal",
        // Entertainment
        "dt_gamepad", "dt_music", "dt_film", "dt_camera", "dt_ticket",
        // Food
        "dt_utensils", "dt_mug",
        // Misc
        "dt_star", "dt_bookmark", "dt_calendar", "dt_id_card", "dt_gem", "dt_crown",
    ]

    /// Default Space glyph — the first, general folder icon.
    static let defaultIcon = "dt_folder"
}
