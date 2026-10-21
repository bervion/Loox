import SwiftUI
import StoreKit

/// Intro free-trial pill on a plan card ("1 year free"), on Max-identity
/// liquid glass (only Max products carry a trial). Solid identity fill below
/// iOS 26 or under Reduce Transparency; the on-tint label follows the identity
/// convention. Caption-sized: never bigger than the card's `.body` price (3.1.2).
struct LooxTrialPill: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let period: Product.SubscriptionPeriod

    var body: some View {
        let label = Text(verbatim: appString("\(LooxTrialCopy.length(period)) free"))
            .vaultType(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(LooxMaxTint.onTint)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s1)
        #if compiler(>=6.2)
        if #available(iOS 26, macOS 26, *), !reduceTransparency {
            label.glassEffect(.regular.tint(LooxMaxTint.pillTint), in: Capsule())
        } else {
            label.background(LooxMaxTint.pillTint, in: Capsule())
        }
        #else
        label.background(LooxMaxTint.pillTint, in: Capsule())
        #endif
    }
}
