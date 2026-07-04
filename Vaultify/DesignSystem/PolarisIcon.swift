import SwiftUI

/// Renders a Polaris icon from the vector-PDF template asset catalog.
/// Template assets tint to the current `foregroundStyle`, so icons adapt to
/// light/dark and accent colors automatically.
struct PolarisIcon: View {
    let name: String
    var size: CGFloat

    init(_ name: String, size: CGFloat = 26) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Centralised asset names for app-chrome icons (categories/fields expose their
/// own `iconAsset`). Keeps string literals out of view code.
enum Icons {
    static let home = "ic_home"
    static let homeFill = "ic_home_filled"
    static let search = "ic_search"
    static let watchtower = "ic_shield_check_mark"
    static let settings = "ic_settings"
    static let settingsFill = "ic_settings_filled"
    static let add = "ic_plus"
    static let addCircle = "ic_plus_circle"
    static let edit = "ic_edit"
    static let delete = "ic_delete"
    static let copy = "ic_duplicate"
    static let reveal = "ic_view"
    static let hide = "ic_hide"
    static let star = "ic_star"
    static let starFill = "ic_star_filled"
    static let check = "ic_check"
    static let checkCircle = "ic_check_circle"
    static let layoutSection = "ic_layout_section"
    static let enter = "ic_enter"
    static let close = "ic_x"
    static let chevronRight = "ic_chevron_right"
    static let chevronDown = "ic_chevron_down"
    static let arrowRight = "ic_arrow_right"
    static let lock = "ic_lock"
    static let lockFill = "ic_lock_filled"
    static let key = "ic_key"
    static let creditCard = "ic_credit_card"
    static let shield = "ic_shield_check_mark"
    static let shieldAlert = "ic_shield_none"
    static let alert = "ic_alert_triangle"
    static let refresh = "ic_refresh"
    static let magic = "ic_magic"
    static let clock = "ic_clock"
    static let globe = "ic_globe"
    static let share = "ic_share"
    static let info = "ic_info"
    static let folder = "ic_folder"
    static let inventory = "ic_inventory"
    static let hashtag = "ic_hashtag"
    static let plan = "ic_plan"
    static let planFill = "ic_plan_filled"
    static let organization = "ic_organization"
    static let organizationFill = "ic_organization_filled"
    static let apps = "ic_apps"
    static let appsFill = "ic_apps_filled"
    static let pin = "ic_pin"
    static let pinFill = "ic_pin_filled"
    static let archive = "ic_archive"
    static let calendar = "ic_calendar"
    static let chartFill = "ic_chart_vertical_filled"
    static let trash = "ic_delete"
    static let importData = "ic_import"
    static let exportData = "ic_export"
    static let language = "ic_language"
    static let passkey = "ic_passkey"
    static let sync = "ic_refresh"
    static let person = "ic_person"
    static let mail = "ic_mail"
    static let camera = "ic_camera"
    static let image = "ic_image"
    /// Document with a plus badge — used on the Add quick-action tile and header cluster.
    static let pageAdd = "ic_page_add"
    /// Horizontal three-dot overflow ("•••") — used in the header action cluster.
    static let moreHorizontal = "ic_menu_horizontal"
}
