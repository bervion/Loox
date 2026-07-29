import Foundation

/// The icon library the pickers browse: the FontAwesome duotone set bundled in
/// `Assets.xcassets/PolarisIcons`. Names are asset names, rendered as two-tone template glyphs —
/// that duotone look is the product's visual language for Spaces and item avatars, so these are
/// deliberately NOT SF Symbols (app chrome is, via `Icons`).
///
/// `dt_house`, `dt_coins` and `dt_shield` ship as EMPTY SVGs (no path data) and are therefore
/// omitted: they render as blank tiles. They stay in the asset catalog so a vault that already
/// holds one keeps resolving, but they must not be offered until re-exported from source.
///
/// Category titles use source strings that do NOT collide with existing catalog keys: the String
/// Catalog keys ARE the English source, so a header of "General", "Health" or "Home" would
/// silently inherit the Settings/gauge/tab translations instead of its own.
enum IconCatalogData {
    static let sections: [IconCatalogSection] = [
        IconCatalogSection(key: "general", title: "Everyday", icons: [
            CatalogIcon(name: "dt_folder", keywords: "folder directory space group"),
            CatalogIcon(name: "dt_folder_open", keywords: "folder open open directory"),
            CatalogIcon(name: "dt_box", keywords: "box package parcel storage"),
            CatalogIcon(name: "dt_boxes", keywords: "boxes packages storage inventory"),
            CatalogIcon(name: "dt_layers", keywords: "layers stack layers group"),
            CatalogIcon(name: "dt_vault", keywords: "vault safe secure storage"),
            CatalogIcon(name: "dt_archive", keywords: "archive storage old backup"),
            CatalogIcon(name: "dt_shapes", keywords: "shapes shapes geometry misc"),
            CatalogIcon(name: "dt_square_plus", keywords: "square plus add new create"),
        ]),
        IconCatalogSection(key: "people", title: "People", icons: [
            CatalogIcon(name: "dt_user", keywords: "user person profile account"),
            CatalogIcon(name: "dt_users", keywords: "users people group team family"),
            CatalogIcon(name: "dt_heart", keywords: "heart love favorite personal"),
            CatalogIcon(name: "dt_paw", keywords: "paw pet animal dog cat"),
            CatalogIcon(name: "dt_baby", keywords: "baby child kid family"),
        ]),
        IconCatalogSection(key: "work", title: "Work", icons: [
            CatalogIcon(name: "dt_briefcase", keywords: "briefcase work business job"),
            CatalogIcon(name: "dt_building", keywords: "building office company work"),
            CatalogIcon(name: "dt_sitemap", keywords: "sitemap hierarchy structure org chart"),
            CatalogIcon(name: "dt_sliders_up", keywords: "sliders up settings custom controls"),
        ]),
        IconCatalogSection(key: "finance", title: "Finance", icons: [
            CatalogIcon(name: "dt_bank", keywords: "bank banking finance money"),
            CatalogIcon(name: "dt_landmark", keywords: "landmark government institution"),
            CatalogIcon(name: "dt_wallet", keywords: "wallet money cash payment"),
            CatalogIcon(name: "dt_credit_card", keywords: "credit card card payment bank"),
            CatalogIcon(name: "dt_chart", keywords: "chart finance stats analytics"),
            CatalogIcon(name: "dt_bitcoin", keywords: "bitcoin crypto currency btc"),
            CatalogIcon(name: "dt_piggy_bank", keywords: "piggy bank savings money"),
            CatalogIcon(name: "dt_receipt", keywords: "receipt invoice bill expense"),
        ]),
        IconCatalogSection(key: "shopping", title: "Shopping", icons: [
            CatalogIcon(name: "dt_cart", keywords: "cart shopping store buy"),
            CatalogIcon(name: "dt_bag", keywords: "bag shopping store purchase"),
            CatalogIcon(name: "dt_gift", keywords: "gift present birthday reward"),
            CatalogIcon(name: "dt_tag", keywords: "tag label price tag"),
        ]),
        IconCatalogSection(key: "communication", title: "Communication", icons: [
            CatalogIcon(name: "dt_envelope", keywords: "envelope mail email message"),
            CatalogIcon(name: "dt_comments", keywords: "comments chat message talk"),
            CatalogIcon(name: "dt_phone", keywords: "phone call mobile contact"),
            CatalogIcon(name: "dt_at", keywords: "at email address handle"),
            CatalogIcon(name: "dt_share", keywords: "share send share social"),
        ]),
        IconCatalogSection(key: "travel", title: "Travel", icons: [
            CatalogIcon(name: "dt_plane", keywords: "plane flight travel airline"),
            CatalogIcon(name: "dt_car", keywords: "car auto vehicle drive"),
            CatalogIcon(name: "dt_map", keywords: "map location travel navigation"),
            CatalogIcon(name: "dt_globe", keywords: "globe web internet world site"),
        ]),
        IconCatalogSection(key: "health", title: "Wellbeing", icons: [
            CatalogIcon(name: "dt_heart_pulse", keywords: "heart pulse health medical fitness"),
            CatalogIcon(name: "dt_pills", keywords: "pills medicine pharmacy health"),
            CatalogIcon(name: "dt_dumbbell", keywords: "dumbbell gym fitness workout"),
            CatalogIcon(name: "dt_life_ring", keywords: "life ring support help recovery rescue"),
        ]),
        IconCatalogSection(key: "education", title: "Education", icons: [
            CatalogIcon(name: "dt_book", keywords: "book reading library study"),
            CatalogIcon(name: "dt_graduation", keywords: "graduation school university education"),
            CatalogIcon(name: "dt_note", keywords: "note notes text memo"),
            CatalogIcon(name: "dt_question", keywords: "question help faq unknown security question"),
        ]),
        IconCatalogSection(key: "technology", title: "Technology", icons: [
            CatalogIcon(name: "dt_server", keywords: "server hosting infrastructure backend"),
            CatalogIcon(name: "dt_database", keywords: "database data storage sql"),
            CatalogIcon(name: "dt_code", keywords: "code developer programming git"),
            CatalogIcon(name: "dt_cloud", keywords: "cloud storage sync online"),
            CatalogIcon(name: "dt_wifi", keywords: "wifi network router internet"),
            CatalogIcon(name: "dt_terminal", keywords: "terminal console shell ssh"),
        ]),
        IconCatalogSection(key: "security", title: "Security", icons: [
            CatalogIcon(name: "dt_key", keywords: "key password secret ssh access"),
            CatalogIcon(name: "dt_lock", keywords: "lock secure private password"),
            CatalogIcon(name: "dt_fingerprint", keywords: "fingerprint biometric identity touch id"),
            CatalogIcon(name: "dt_shield_keyhole", keywords: "shield keyhole security protection vault"),
        ]),
        IconCatalogSection(key: "entertainment", title: "Entertainment", icons: [
            CatalogIcon(name: "dt_gamepad", keywords: "gamepad game gaming console"),
            CatalogIcon(name: "dt_music", keywords: "music audio songs streaming"),
            CatalogIcon(name: "dt_film", keywords: "film movie video streaming"),
            CatalogIcon(name: "dt_camera", keywords: "camera photo picture media"),
            CatalogIcon(name: "dt_ticket", keywords: "ticket event booking pass"),
        ]),
        IconCatalogSection(key: "food", title: "Food", icons: [
            CatalogIcon(name: "dt_utensils", keywords: "utensils food restaurant dining"),
            CatalogIcon(name: "dt_mug", keywords: "mug coffee drink cafe"),
        ]),
        IconCatalogSection(key: "misc", title: "Symbols", icons: [
            CatalogIcon(name: "dt_star", keywords: "star favorite important rating"),
            CatalogIcon(name: "dt_bookmark", keywords: "bookmark saved favorite reading"),
            CatalogIcon(name: "dt_calendar", keywords: "calendar date schedule events"),
            CatalogIcon(name: "dt_clock", keywords: "clock time reminder 2fa codes"),
            CatalogIcon(name: "dt_id_card", keywords: "id card identity licence passport"),
            CatalogIcon(name: "dt_gem", keywords: "gem premium valuable jewel"),
            CatalogIcon(name: "dt_crown", keywords: "crown premium vip king"),
        ]),
    ]
}
