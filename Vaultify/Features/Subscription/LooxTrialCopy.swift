import Foundation
import StoreKit

/// Commerce copy helpers shared by the paywall surfaces.
///
/// `length` is the human length of an intro-offer period built from its UNIT
/// ("1 year", not "365 days"), localized EN/VI/JA. The day unit has its OWN key:
/// "%lld days" is the rotation label (JA 日, not 日間) and must not be reused.
nonisolated enum LooxTrialCopy {
    static func length(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .week: appString("\(period.value) weeks")
        case .month: appString("\(period.value) months")
        case .year: appString("\(period.value) years")
        // `.day` (App Store Connect offers 3 days) and any future unit.
        default: appString("\(period.value) days (trial)")
        }
    }

    /// An end date ("Free until", "Free trial ends") in the in-app language,
    /// not the device one, so the sentence and its date never mix languages.
    static func endDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(appResourceLocale))
    }
}
