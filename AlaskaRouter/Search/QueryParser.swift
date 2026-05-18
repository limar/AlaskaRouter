// Natural-language → structured query parsing for AlaskaRouter search.
//
// Algorithm (ported from Spike B.5 main.swift):
//   1. Greedy multi-word phrase scan against a hand-curated map of category
//      surface forms ("visitor center", "ranger", "fuel", "hot spring", …)
//      → emits category hints; consumed words are stripped from the query.
//   2. Remaining tokens become name tokens.
//
// Category hints are applied as a SOFT BOOST in scoring, not a hard WHERE
// filter — "Fairbanks ranger" still returns Fairbanks-named places when no
// actual ranger_station row matches. See SPIKE_FINDINGS.md.

import Foundation

struct StructuredQuery: Equatable {
    var nameTokens: [String]
    var categoryHints: [String]

    var isEmpty: Bool { nameTokens.isEmpty && categoryHints.isEmpty }
}

enum QueryParser {

    /// Multi-word phrases first (longest-match wins), then single words.
    /// Values are the canonical category strings stored in place_meta.category.
    private static let categoryPhrases: [(phrase: String, category: String)] = [
        ("visitor center",    "visitor_center"),
        ("visitor centre",    "visitor_center"),
        ("ranger station",    "ranger_station"),
        ("river crossing",    "river_crossing"),
        ("hot spring",        "spring"),
        ("hot springs",       "spring"),
        ("gas station",       "fuel"),
        ("post office",       "post"),
        ("ranger",            "ranger_station"),
        ("fuel",              "fuel"),
        ("gas",               "fuel"),
        ("petrol",            "fuel"),
        ("diesel",            "fuel"),
        ("camping",           "camping"),
        ("campsite",          "camping"),
        ("campground",        "camping"),
        ("camp",              "camping"),
        ("information",       "visitor_center"),
        ("info",              "visitor_center"),
        ("viewpoint",         "viewpoint"),
        ("overlook",          "viewpoint"),
        ("hut",               "hut"),
        ("shelter",           "hut"),
        ("cabin",             "hut"),
        ("hotel",             "lodging"),
        ("motel",             "lodging"),
        ("lodge",             "lodging"),
        ("lodging",           "lodging"),
        ("hostel",            "lodging"),
        ("peak",              "peak"),
        ("mountain",          "peak"),
        ("glacier",           "glacier"),
        ("spring",            "spring"),
        ("waterfall",         "waterfall"),
        ("airport",           "airfield"),
        ("airfield",          "airfield"),
        ("airstrip",          "airfield"),
        ("lighthouse",        "lighthouse"),
        ("ford",              "river_crossing"),
        ("pharmacy",          "pharmacy"),
        ("hospital",          "medical"),
        ("medical",           "medical"),
        ("clinic",            "medical"),
        ("food",              "food"),
        ("cafe",              "food"),
        ("restaurant",        "food"),
    ]

    static func parse(_ raw: String) -> StructuredQuery {
        var remaining = raw.lowercased()
        var hints: [String] = []

        for (phrase, cat) in categoryPhrases {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b"
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(remaining.startIndex..., in: remaining)
            if re.firstMatch(in: remaining, range: range) != nil {
                hints.append(cat)
                remaining = re.stringByReplacingMatches(in: remaining,
                                                       range: range,
                                                       withTemplate: " ")
            }
        }

        let tokens = remaining
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        let uniqueHints = hints.filter { seen.insert($0).inserted }

        return StructuredQuery(nameTokens: tokens, categoryHints: uniqueHints)
    }
}

// MARK: - Edit-distance (Levenshtein, iterative)

enum EditDistance {

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }
        var prev = Array(0...bChars.count)
        var curr = [Int](repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            curr[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[bChars.count]
    }

    /// For a query token and a name string, find the minimum edit distance
    /// to any single word in the name. Prefix matches count as distance 0.
    static func minTokenDistance(qToken: String, against text: String) -> Int {
        let qLower = qToken.lowercased()
        var best = Int.max
        for word in text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        where !word.isEmpty {
            if word.hasPrefix(qLower) { return 0 }
            let d = levenshtein(qLower, word)
            if d < best { best = d }
            if best == 0 { break }
        }
        return best == Int.max ? qLower.count : best
    }
}
