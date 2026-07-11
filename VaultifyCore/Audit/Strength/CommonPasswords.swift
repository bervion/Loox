import Foundation

/// Curated top common passwords (breach-derived popularity order, best-known
/// public lists). Rank drives the guess estimate: rank 1 ≈ first thing tried.
/// Lookup happens on l33t-NORMALIZED lowercase strings, so entries are plain.
nonisolated enum CommonPasswords {

    static let rank: [String: Int] = {
        var out: [String: Int] = [:]
        out.reserveCapacity(ordered.count)
        for (index, word) in ordered.enumerated() where out[word] == nil {
            out[word] = index + 1
        }
        return out
    }()

    private static let ordered: [String] = [
        "123456", "password", "123456789", "12345678", "12345", "qwerty",
        "1234567", "111111", "1234567890", "123123", "abc123", "1234",
        "password1", "iloveyou", "1q2w3e4r", "000000", "qwerty123", "zaq12wsx",
        "dragon", "sunshine", "princess", "letmein", "654321", "monkey",
        "27653", "1qaz2wsx", "123321", "qwertyuiop", "superman", "asdfghjkl",
        "trustno1", "jordan23", "welcome", "shadow", "ashley", "football",
        "jesus", "michael", "ninja", "mustang", "password123", "master",
        "hello", "charlie", "aa123456", "donald", "freedom", "whatever",
        "qazwsx", "666666", "121212", "flower", "passw0rd", "baseball",
        "555555", "lovely", "7777777", "888888", "fuckyou", "159753",
        "222222", "michelle", "jennifer", "asdfgh", "harley", "999999",
        "112233", "hunter", "696969", "batman", "biteme", "starwars",
        "cheese", "computer", "soccer", "secret", "buster", "pepper",
        "killer", "george", "summer", "banana", "thomas", "taylor",
        "matrix", "hockey", "ranger", "daniel", "amanda", "andrew",
        "joshua", "robert", "silver", "tigger", "purple", "ginger",
        "cookie", "maggie", "nicole", "hannah", "sparky", "yankees",
        "diamond", "orange", "mickey", "peanut", "junior", "chelsea",
        "pokemon", "jessica", "austin", "chicken", "pussy", "corvette",
        "ferrari", "matthew", "golfer", "cowboy", "falcon", "gandalf",
        "winter", "spring", "bigdog", "cameron", "dallas", "eagles",
        "chester", "melissa", "yellow", "phoenix", "camaro", "tennis",
        "internet", "london", "iceman", "sierra", "212121", "toyota",
        "florida", "132435", "abcdef", "abcd1234", "a123456", "samsung",
        "access", "pass123", "admin", "admin123", "root", "login",
        "welcome1", "welcome123", "changeme", "letmein1", "test", "test123",
        "user", "guest", "default", "secret123", "temp123", "demo123",
        "google", "facebook", "linkedin", "twitter", "myspace", "windows",
        "apple", "iphone", "android", "nokia", "gmail", "hotmail",
        "monkey123", "dragon123", "shadow123", "master123", "jordan",
        "liverpool", "arsenal", "chelsea1", "manutd", "barcelona",
        "realmadrid", "juventus", "ronaldo", "messi", "neymar",
        "pokemon123", "naruto", "sasuke", "goku", "onepiece", "deathnote",
        "minecraft", "fortnite", "callofduty", "halo", "zelda", "mario",
        "qwe123", "qweasd", "qweasdzxc", "asdf1234", "zxcvbnm", "zxcvbn",
        "1q2w3e", "1qazxsw2", "q1w2e3r4", "q1w2e3r4t5", "zaq1zaq1",
        "0987654321", "987654321", "87654321", "7654321", "543210",
        "102030", "112211", "445566", "778899", "252525", "232323",
        "12341234", "12344321", "11223344", "1234qwer", "1234abcd",
        "a1b2c3", "abc12345", "aaa111", "abcabc", "asdasd", "qweqwe",
        "monday", "friday", "january", "december", "america", "canada",
        "mexico", "brazil", "russia", "china", "japan", "india",
        "scorpio", "taurus", "gemini", "leo123", "aquarius", "pisces",
        "midnight", "rainbow", "butterfly", "angel", "angels", "lovers",
        "forever", "family", "friends", "money", "dollar", "richie",
        "casino", "poker", "vegas", "lucky", "lucky7", "bingo",
        "cricket", "rugby", "boxing", "karate", "fishing", "hunting",
        "batman123", "spiderman", "ironman", "avengers", "wolverine",
        "startrek", "skywalker", "vader", "yoda123", "chewbacca",
        "slipknot", "metallica", "nirvana", "beatles", "eminem",
        "blink182", "linkinpark", "greenday", "rammstein", "acdc123",
        "whocares", "nothing", "anything", "something", "cocacola",
        "pepsi", "snickers", "chocolate", "vanilla", "coffee",
        "marlboro", "corona", "heineken", "guinness", "whiskey",
        "porsche", "mercedes", "bmw2024", "honda", "yamaha", "suzuki",
        "kawasaki", "harley1", "mustang1", "camaro1", "chevy",
        // Vietnamese common picks (breach-derived VN lists + local habits)
        "matkhau", "anhyeuem", "emyeuanh", "yeuem", "vietnam", "hanoi",
        "saigon", "danang", "bongda", "doremon", "conheo", "cuchuoi",
        "khongbiet", "khongco", "matkhau123", "123456a", "123456aa",
        "a12345678", "0123456789", "0123456", "098765", "matkhaucuatoi",
        "trung123", "nguyen123", "iloveyou123", "chipchip", "meocon",
        "cuncon", "susu123", "bexinh", "codon", "buonqua", "nhoem",
    ]
}
