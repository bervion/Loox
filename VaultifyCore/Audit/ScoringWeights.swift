import Foundation

/// Every constant behind the 1000-point score, in one place. Deterministic and
/// explainable by design: no constant may be derived at runtime, and any change
/// here must update the golden scoring tests.
nonisolated enum ScoringWeights {

    // MARK: Pillar maxima (sum = 1000)

    static let exposureMax = 300
    static let qualityMax = 220
    static let reuseMax = 180
    static let authMax = 140
    static let integrityMax = 100
    static let maintenanceMax = 60

    // MARK: Exposure

    /// Per UNIQUE leaked password (group-based, never per item).
    static let leakedPasswordPenalty = 60
    /// Extra when the leaked password is shared by 2-3 items / 4+ items.
    static let leakedReusedSmallExtra = 20
    static let leakedReusedLargeExtra = 40

    // MARK: Quality — value share per grade (weighted distribution)

    static let gradeValue: [PasswordGrade: Double] = [
        .veryWeak: 0.0, .weak: 0.25, .fair: 0.7, .strong: 0.9, .excellent: 1.0,
    ]

    // MARK: Reuse

    /// Per extra item in a reuse group, scaled by the group's category weight.
    static let reusePerExtraItem = 20.0
    /// Cap per group so one giant import cannot zero the pillar alone.
    static let reuseGroupCap = 60.0

    // MARK: Authentication readiness

    /// Confirmed protection floor: even 0% coverage keeps 75% of the pillar —
    /// "no code saved in Loox" is an opportunity, not a confirmed weakness.
    static let authCoverageFloor = 0.75

    // MARK: Integrity deductions

    static let conflictPenalty = 15
    static let exactDuplicatePenalty = 5
    static let invalidOTPPenalty = 8
    static let incompleteItemPenalty = 5
    static let urlMediumPenalty = 5
    static let urlLowPenalty = 2

    // MARK: Maintenance deductions

    static let stalePenalty = 2
    static let staleCap = 20
    static let missingMetadataPenalty = 1
    static let missingMetadataCap = 10
    static let auditOverdue30Penalty = 10
    static let auditOverdue90Penalty = 20

    /// Below this many analyzed items the score is real but low-confidence —
    /// the UI shows "Based on N items" instead of pretending statistical weight.
    static let lowConfidenceItemCount = 5

    // MARK: Category weights (reuse blast radius; static, no AI)

    /// Registrable-domain → weight. Email, finance, and identity anchors weigh
    /// most: a breach there cascades into everything else.
    static func categoryWeight(forHost host: String) -> Double {
        for (suffixes, weight) in weightTable {
            if suffixes.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                return weight
            }
        }
        return 1.0
    }

    private static let weightTable: [([String], Double)] = [
        // Primary email + identity
        (["gmail.com", "google.com", "outlook.com", "hotmail.com", "live.com",
          "yahoo.com", "proton.me", "protonmail.com", "icloud.com", "apple.com"], 1.5),
        // Finance / payment
        (["paypal.com", "stripe.com", "coinbase.com", "binance.com", "wise.com",
          "vietcombank.com.vn", "techcombank.com.vn", "mbbank.com.vn", "vpbank.com.vn",
          "bidv.com.vn", "agribank.com.vn", "momo.vn", "zalopay.vn"], 1.5),
        // Cloud / dev
        (["github.com", "gitlab.com", "bitbucket.org", "aws.amazon.com",
          "cloudflare.com", "digitalocean.com", "vercel.com", "netlify.com",
          "microsoft.com", "azure.com"], 1.3),
        // Social
        (["facebook.com", "instagram.com", "x.com", "twitter.com", "tiktok.com",
          "linkedin.com", "reddit.com", "discord.com", "telegram.org"], 1.1),
        // Entertainment
        (["netflix.com", "spotify.com", "twitch.tv", "steampowered.com"], 0.8),
    ]
}
