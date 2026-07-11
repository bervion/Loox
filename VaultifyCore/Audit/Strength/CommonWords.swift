import Foundation

/// Common dictionary words and names that appear inside passwords (English
/// high-frequency + given names + Vietnamese names/words). Ranked AFTER the
/// common-password list in attack order — the matcher offsets these ranks.
nonisolated enum CommonWords {

    static let rank: [String: Int] = {
        var out: [String: Int] = [:]
        out.reserveCapacity(ordered.count)
        for (index, word) in ordered.enumerated() where out[word] == nil {
            out[word] = index + 1
        }
        return out
    }()

    private static let ordered: [String] = [
        // High-frequency English words seen in passwords
        "love", "baby", "life", "live", "time", "home", "house", "work",
        "play", "game", "games", "girl", "boys", "kids", "mama", "papa",
        "king", "queen", "prince", "star", "stars", "moon", "sun",
        "light", "dark", "darkness", "night", "day", "fire", "water",
        "earth", "wind", "storm", "thunder", "lightning", "rain", "snow",
        "cloud", "sky", "ocean", "river", "mountain", "forest", "nature",
        "happy", "smile", "laugh", "dream", "dreams", "hope", "faith",
        "peace", "power", "magic", "music", "dance", "party", "crazy",
        "sweet", "sugar", "honey", "candy", "cherry", "berry", "grape",
        "lemon", "melon", "mango", "peach", "kiwi", "olive",
        "tiger", "lion", "bear", "wolf", "fox", "cat", "dog", "puppy",
        "kitty", "bunny", "rabbit", "horse", "pony", "bird", "eagle",
        "hawk", "owl", "duck", "panda", "koala", "zebra", "giraffe",
        "snake", "cobra", "viper", "spider", "scorpion", "shark",
        "dolphin", "whale", "turtle", "penguin", "monster", "demon",
        "devil", "ghost", "zombie", "vampire", "wizard", "witch",
        "knight", "warrior", "hunter", "sniper", "soldier", "captain",
        "major", "general", "pilot", "doctor", "nurse", "teacher",
        "student", "school", "college", "university", "office",
        "black", "white", "red", "blue", "green", "pink", "brown",
        "golden", "silver", "bronze", "crystal", "pearl", "ruby",
        "emerald", "sapphire", "topaz", "amber", "ivory", "jade",
        "rock", "rocks", "metal", "steel", "iron", "stone", "brick",
        "beach", "island", "paradise", "heaven", "hell", "angel",
        "spirit", "soul", "heart", "hearts", "mind", "body",
        "north", "south", "east", "west", "central", "middle",
        "first", "last", "best", "great", "super", "mega", "ultra",
        "turbo", "speed", "racer", "racing", "rider", "driver",
        "january", "february", "march", "april", "june", "july",
        "august", "september", "october", "november", "december",
        "monday", "tuesday", "wednesday", "thursday", "friday",
        "saturday", "sunday", "spring", "summer", "autumn", "winter",
        // Common given names (EN)
        "james", "john", "robert", "michael", "william", "david",
        "richard", "joseph", "thomas", "charles", "chris", "christopher",
        "daniel", "matthew", "anthony", "mark", "donald", "steven",
        "paul", "andrew", "joshua", "kenneth", "kevin", "brian",
        "george", "edward", "ronald", "timothy", "jason", "jeffrey",
        "ryan", "jacob", "gary", "nicholas", "eric", "jonathan",
        "stephen", "larry", "justin", "scott", "brandon", "benjamin",
        "samuel", "gregory", "frank", "alexander", "raymond", "patrick",
        "jack", "dennis", "jerry", "tyler", "aaron", "jose", "adam",
        "nathan", "henry", "douglas", "zachary", "peter", "kyle",
        "mary", "patricia", "jennifer", "linda", "elizabeth", "barbara",
        "susan", "jessica", "sarah", "karen", "nancy", "lisa", "betty",
        "margaret", "sandra", "ashley", "kimberly", "emily", "donna",
        "michelle", "dorothy", "carol", "amanda", "melissa", "deborah",
        "stephanie", "rebecca", "sharon", "laura", "cynthia", "kathleen",
        "amy", "shirley", "angela", "helen", "anna", "brenda", "pamela",
        "nicole", "emma", "samantha", "katherine", "christine", "debra",
        "rachel", "catherine", "carolyn", "janet", "ruth", "maria",
        "heather", "diane", "virginia", "julie", "joyce", "victoria",
        "olivia", "kelly", "christina", "lauren", "joan", "evelyn",
        "judith", "megan", "cheryl", "andrea", "hannah", "martha",
        "jacqueline", "frances", "gloria", "ann", "teresa", "kathryn",
        "sara", "janice", "jean", "alice", "madison", "doris",
        "abigail", "julia", "judy", "grace", "denise", "amber",
        "marilyn", "beverly", "danielle", "theresa", "sophia", "marie",
        "diana", "brittany", "natalie", "isabella", "charlotte", "rose",
        "alexis", "kayla",
        // Vietnamese family/given names and common words
        "nguyen", "tran", "lele", "pham", "hoang", "huynh", "phan",
        "vuvu", "dang", "bui", "dodo", "hono", "ngo", "duong", "lyly",
        "minh", "tuan", "hung", "dung", "duc", "thanh", "trung",
        "hieu", "nam", "hai", "long", "quan", "khanh", "phuc", "thang",
        "son", "viet", "cuong", "binh", "tien", "toan", "dat", "khoa",
        "linh", "huong", "trang", "thao", "phuong", "lan", "mai",
        "hoa", "hanh", "ngoc", "yen", "nhung", "thu", "thuy", "hang",
        "van", "anh", "chau", "quynh", "nga", "diep", "loan", "tuyet",
        "kieu", "giang", "vietnam", "hanoi", "saigon", "hue", "dalat",
        "nhatrang", "vungtau", "cantho", "haiphong", "bienhoa",
        "anhyeu", "emyeu", "thuong", "nhonhieu", "maimai", "trondoi",
        "hanhphuc", "tinhyeu", "giadinh", "banthan", "truong", "lop",
    ]
}
