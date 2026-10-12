import Foundation

/// Screens names other players will see (player names, design names). The game is rated 13+
/// and shows names to strangers, so anything rude, hateful or link-like is refused. Letters are
/// normalised first so look-alike spellings ("sh1t", "a.s.s") are caught too.
public enum ContentFilter {
    /// Kept short and obvious on purpose. Matched against the normalised name.
    static let blocked: [String] = [
        "fuck", "fuk", "shit", "bitch", "cunt", "pussy", "slut", "whore", "bastard",
        "asshole", "wanker", "twat", "porn", "nude", "naked", "nazi", "hitler",
        "nigg", "faggot", "retard", "killyourself", "tranny", "chink",
        "kike", "gook", "wetback", "penis", "vagina", "boob", "jizz",
        "molest", "kkk", "cocaine"
    ]

    /// Words that are only rude on their own (so "Cassidy", "Peacock" and "Raccoon" are fine).
    static let blockedWhole: [String] = ["ass", "hoe", "fag", "cum", "cock", "dick", "sex", "coon", "spic",
                                         "tits", "kys", "dyke", "meth", "weed", "isis",
                                         "rape", "pedo", "wank", "heroin"]

    /// Lower case, look-alike digits and symbols turned into letters, everything else dropped.
    public static func normalize(_ s: String) -> String {
        let swaps: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
                                             "8": "b", "@": "a", "$": "s", "!": "i", "|": "i", "+": "t"]
        var out = ""
        for ch in s.lowercased().folding(options: .diacriticInsensitive, locale: nil) {
            if let swap = swaps[ch] { out.append(swap) } else if ch.isLetter { out.append(ch) }
        }
        return out
    }

    /// Words as typed (lower case, letters and look-alikes only), for whole-word checks.
    static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { normalize(String($0)) }
    }

    public static func isClean(_ s: String) -> Bool {
        let flat = normalize(s)
        if blocked.contains(where: { flat.contains($0) }) { return false }
        // Squeezed repeats ("shiiit") too.
        let squeezed = String(flat.reduce(into: [Character]()) { if $0.last != $1 { $0.append($1) } })
        if blocked.contains(where: { squeezed.contains($0) }) { return false }
        if words(s).contains(where: { blockedWhole.contains($0) }) { return false }
        return true
    }

    /// No web addresses or handles in names shown to others.
    public static func looksLikeLink(_ s: String) -> Bool {
        let l = s.lowercased()
        return ["http", "www", ".com", ".net", ".org", ".gg", ".io", "@", "discord", "snap", "insta", "tiktok"]
            .contains { l.contains($0) }
    }

    /// Fit to show to other players.
    public static func isAllowedPublicName(_ s: String) -> Bool {
        isClean(s) && !looksLikeLink(s)
    }
}
