import Foundation

/// Curated subset of the Polaris icon set offered when choosing a folder
/// ("Space") icon. Every name is verified present in
/// `Assets.xcassets/PolarisIcons` so the picker never shows a blank tile.
enum CuratedFolderIcons {
    static let all: [String] = [
        "ic_folder", "ic_work", "ic_organization", "ic_team",
        "ic_bank", "ic_globe", "ic_home", "ic_person",
        "ic_wallet", "ic_money", "ic_credit_card", "ic_product",
        "ic_wrench", "ic_database_connect", "ic_book_open", "ic_target",
        "ic_chart_line", "ic_food", "ic_phone", "ic_mail",
        "ic_calendar", "ic_channels", "ic_key", "ic_shield_check_mark",
    ]
}
