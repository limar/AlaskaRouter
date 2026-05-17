// FTS5 places-DB query quality spike — v2 (Spike B.5).
//
// Adds:
//   1. CategoryFacetParser — pulls category-hint tokens out of the query ("ranger", "fuel",
//      "visitor center"...) and treats them as a SQL filter, not a name match.
//   2. Two-stage retrieval:
//        Stage 1: strict FTS5 prefix-AND query on name tokens (cheap, high precision).
//        Stage 2 (fallback when stage 1 returns < minHits): relaxed prefix-OR FTS5 query,
//                 followed by an in-Swift edit-distance rerank against name + alt_names.
//      Stage 2 fixes the typo cases that stage 1 misses.
//
// Goal: take the spike from 8/12 to 12/12 on the same battery.

import Foundation
import SQLite3

let DB_PATH = "../data/pois.sqlite"

nonisolated(unsafe) let SQLITE_TRANSIENT = unsafeBitCast(
    OpaquePointer(bitPattern: -1),
    to: sqlite3_destructor_type.self
)

// MARK: - SQLite handle

final class DB {
    let handle: OpaquePointer
    init(path: String) {
        var h: OpaquePointer?
        guard sqlite3_open_v2(path, &h, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let h else {
            fatalError("can't open \(path)")
        }
        self.handle = h
    }
    deinit { sqlite3_close(handle) }
}

// MARK: - Models

struct Hit {
    var name: String
    var altNames: String
    var category: String
    var lat: Double
    var lon: Double
    var importance: Double
    var bm25: Double
    var stage: Int          // 1 = strict prefix-AND, 2 = relaxed + edit-distance rerank
    var editDistance: Int   // 0 for stage-1 hits
    var score: Double
}

// MARK: - Category facet parser

/// Maps category-hint surface forms to the canonical category strings stored in place_meta.category.
/// Order matters for multi-word forms: scan longer phrases first.
private let CATEGORY_PHRASES: [(phrase: String, category: String)] = [
    // multi-word — checked first
    ("visitor center",    "visitor_center"),
    ("visitor centre",    "visitor_center"),
    ("ranger station",    "ranger_station"),
    ("river crossing",    "river_crossing"),
    ("hot spring",        "spring"),
    ("hot springs",       "spring"),
    ("gas station",       "fuel"),
    ("post office",       "post"),
    // single-word
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

struct StructuredQuery {
    var nameTokens: [String]
    var categoryHints: [String]   // canonical category values
}

func parseQuery(_ raw: String) -> StructuredQuery {
    let lower = raw.lowercased()
    var remaining = lower
    var hints: [String] = []

    // Greedy multi-word phrase matching first.
    for (phrase, cat) in CATEGORY_PHRASES {
        // word-boundary aware: phrase must match a whole word/phrase, not a substring.
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b"
        if let re = try? NSRegularExpression(pattern: pattern),
           re.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)) != nil {
            hints.append(cat)
            remaining = re.stringByReplacingMatches(in: remaining,
                                                    range: NSRange(remaining.startIndex..., in: remaining),
                                                    withTemplate: " ")
        }
    }

    // Whatever's left becomes name tokens.
    let nameTokens = remaining
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    // Dedupe category hints, preserve insertion order.
    var seen = Set<String>()
    let uniqueHints = hints.filter { seen.insert($0).inserted }

    return StructuredQuery(nameTokens: nameTokens, categoryHints: uniqueHints)
}

// MARK: - Edit-distance (Levenshtein, iterative)

func editDistance(_ a: String, _ b: String) -> Int {
    let aChars = Array(a)
    let bChars = Array(b)
    if aChars.isEmpty { return bChars.count }
    if bChars.isEmpty { return aChars.count }
    var prev = Array(0...bChars.count)
    var curr = [Int](repeating: 0, count: bChars.count + 1)
    for i in 1...aChars.count {
        curr[0] = i
        for j in 1...bChars.count {
            let cost = aChars[i-1] == bChars[j-1] ? 0 : 1
            curr[j] = min(prev[j] + 1, curr[j-1] + 1, prev[j-1] + cost)
        }
        swap(&prev, &curr)
    }
    return prev[bChars.count]
}

/// For a query token and a name string, find the minimum edit distance to any single word in the name.
func minTokenDistance(qToken: String, against text: String) -> Int {
    let qLower = qToken.lowercased()
    var best = Int.max
    for word in text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted) where !word.isEmpty {
        // Cheap shortcut: if the candidate word starts with qToken, distance is 0 by prefix-match semantics.
        if word.hasPrefix(qLower) {
            return 0
        }
        let d = editDistance(qLower, word)
        if d < best { best = d }
        if best == 0 { break }
    }
    return best == Int.max ? qLower.count : best
}

// MARK: - Stage 1: strict prefix-AND FTS5

func stage1Query(_ q: StructuredQuery, db: DB, limit: Int = 20) -> [Hit] {
    guard !q.nameTokens.isEmpty || !q.categoryHints.isEmpty else { return [] }

    // Name tokens are AND-prefix-matched.
    // Category hints are a SOFT boost in ORDER BY, not a hard WHERE filter, so that a query
    // like "Fairbanks ranger" still returns Fairbanks-named places even if no row has
    // category=ranger_station in the actual data.
    var ftsArg: String? = nil
    var whereClauses: [String] = []
    if !q.nameTokens.isEmpty {
        ftsArg = q.nameTokens.map { "\($0)*" }.joined(separator: " ")
        whereClauses.append("places_word MATCH ?")
    }

    // Build the category-boost CASE expression.
    let catBoost: String
    var catParams: [String] = []
    if !q.categoryHints.isEmpty {
        let placeholders = q.categoryHints.map { _ in "?" }.joined(separator: ",")
        catBoost = "CASE WHEN m.category IN (\(placeholders)) THEN 3.0 ELSE 0.0 END"
        catParams = q.categoryHints
    } else {
        catBoost = "0.0"
    }

    let baseFrom: String
    let scoreExpr: String
    if ftsArg != nil {
        baseFrom = "places_word JOIN place_meta AS m ON m.rowid = places_word.rowid"
        scoreExpr = "bm25(places_word) - m.importance * 5.0 - (\(catBoost))"
    } else {
        // Category-only query: no name tokens. Rank by importance + category match.
        baseFrom = "place_meta AS m"
        scoreExpr = "(-m.importance * 5.0) - (\(catBoost))"
    }

    let whereSql = whereClauses.isEmpty ? "1=1" : whereClauses.joined(separator: " AND ")
    let sql = """
    SELECT m.name, m.alt_names, m.category, m.lat, m.lon, m.importance,
           \(ftsArg != nil ? "bm25(places_word)" : "0.0") AS bm25,
           (\(scoreExpr)) AS final_score
    FROM \(baseFrom)
    WHERE \(whereSql)
    ORDER BY final_score ASC
    LIMIT ?;
    """

    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db.handle, sql, -1, &stmt, nil) == SQLITE_OK else {
        print("  [stage1 prepare error] \(String(cString: sqlite3_errmsg(db.handle)))  sql=\(sql)")
        return []
    }
    defer { sqlite3_finalize(stmt) }

    // Bind in TEXTUAL ORDER of `?` placeholders:
    //   1) category-hint params in the SELECT's CASE expression (if any)
    //   2) FTS MATCH in WHERE (if name tokens were present)
    //   3) LIMIT
    var bindIndex: Int32 = 1
    for c in catParams {
        sqlite3_bind_text(stmt, bindIndex, c, -1, SQLITE_TRANSIENT); bindIndex += 1
    }
    if let fts = ftsArg {
        sqlite3_bind_text(stmt, bindIndex, fts, -1, SQLITE_TRANSIENT); bindIndex += 1
    }
    sqlite3_bind_int(stmt, bindIndex, Int32(limit))

    var hits: [Hit] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        let name = String(cString: sqlite3_column_text(stmt, 0))
        let altn = String(cString: sqlite3_column_text(stmt, 1))
        let cat = String(cString: sqlite3_column_text(stmt, 2))
        let lat = sqlite3_column_double(stmt, 3)
        let lon = sqlite3_column_double(stmt, 4)
        let imp = sqlite3_column_double(stmt, 5)
        let bm25 = sqlite3_column_double(stmt, 6)
        hits.append(Hit(name: name, altNames: altn, category: cat, lat: lat, lon: lon,
                        importance: imp, bm25: bm25, stage: 1, editDistance: 0,
                        score: bm25 - imp * 5.0))
    }
    return hits
}

// MARK: - Stage 2: relaxed OR-of-3-char-prefixes + edit-distance rerank

func stage2Query(_ q: StructuredQuery, db: DB, limit: Int = 20, candidateCap: Int = 400) -> [Hit] {
    guard !q.nameTokens.isEmpty else { return [] }

    // For each token, use a 3-char prefix. Stopwords-ish: skip tokens shorter than 3 chars.
    let prefixes = q.nameTokens
        .filter { $0.count >= 3 }
        .map { String($0.prefix(3)) + "*" }
    guard !prefixes.isEmpty else { return [] }

    let ftsArg = prefixes.joined(separator: " OR ")

    let sql = """
    SELECT m.name, m.alt_names, m.category, m.lat, m.lon, m.importance, bm25(places_word)
    FROM places_word JOIN place_meta AS m ON m.rowid = places_word.rowid
    WHERE places_word MATCH ?
    ORDER BY bm25(places_word) ASC
    LIMIT ?;
    """

    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db.handle, sql, -1, &stmt, nil) == SQLITE_OK else {
        print("  [stage2 prepare error] \(String(cString: sqlite3_errmsg(db.handle)))")
        return []
    }
    defer { sqlite3_finalize(stmt) }

    sqlite3_bind_text(stmt, 1, ftsArg, -1, SQLITE_TRANSIENT)
    sqlite3_bind_int(stmt, 2, Int32(candidateCap))

    var raw: [Hit] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        let name = String(cString: sqlite3_column_text(stmt, 0))
        let altn = String(cString: sqlite3_column_text(stmt, 1))
        let cat = String(cString: sqlite3_column_text(stmt, 2))
        let lat = sqlite3_column_double(stmt, 3)
        let lon = sqlite3_column_double(stmt, 4)
        let imp = sqlite3_column_double(stmt, 5)
        let bm25 = sqlite3_column_double(stmt, 6)
        raw.append(Hit(name: name, altNames: altn, category: cat, lat: lat, lon: lon,
                       importance: imp, bm25: bm25, stage: 2, editDistance: 0,
                       score: 0))
    }

    // Edit-distance rerank: for each candidate, sum (over query tokens) the min distance to
    // any word in name + alt_names. Lower is better. Subtract importance for tie-break,
    // and subtract a small boost when the candidate's category matches a hint.
    let qTokens = q.nameTokens.map { $0.lowercased() }
    let catHintSet = Set(q.categoryHints)
    var scored: [Hit] = raw.map { h in
        let target = h.name + " | " + h.altNames
        var totalDist = 0
        for qt in qTokens {
            totalDist += minTokenDistance(qToken: qt, against: target)
        }
        let catBoost = catHintSet.contains(h.category) ? 0.7 : 0.0
        var copy = h
        copy.editDistance = totalDist
        copy.score = Double(totalDist) - h.importance * 0.5 - catBoost
        return copy
    }
    // Hard filter: drop candidates where any single-token distance exceeds 3 (too far).
    scored = scored.filter { h in
        let target = h.name + " | " + h.altNames
        return qTokens.allSatisfy { minTokenDistance(qToken: $0, against: target) <= 3 }
    }
    scored.sort { $0.score < $1.score }
    return Array(scored.prefix(limit))
}

// MARK: - Two-stage orchestrator

func search(_ raw: String, db: DB, limit: Int = 10, minHitsForStage1: Int = 1) -> (parsed: StructuredQuery, hits: [Hit]) {
    let parsed = parseQuery(raw)
    let stage1 = stage1Query(parsed, db: db, limit: limit)
    if stage1.count >= minHitsForStage1 {
        return (parsed, stage1)
    }
    let stage2 = stage2Query(parsed, db: db, limit: limit)
    return (parsed, stage2)
}

// MARK: - Formatting

extension String {
    func padded(_ w: Int) -> String {
        if count >= w { return String(prefix(w)) }
        return self + String(repeating: " ", count: w - count)
    }
}

func format(_ hit: Hit, idx: Int) -> String {
    let n = String(format: "%2d.", idx)
    let coord = String(format: "%.3f,%.3f", hit.lat, hit.lon)
    let extra = hit.stage == 1
        ? String(format: "[s1] bm25=%6.2f imp=%.2f", hit.bm25, hit.importance)
        : String(format: "[s2] edit=%d imp=%.2f", hit.editDistance, hit.importance)
    return "  \(n) \(hit.name.padded(40)) \(hit.category.padded(18)) \(coord.padded(17)) \(extra)"
}

// MARK: - Test battery (same as v1)

struct TestCase {
    let label: String
    let query: String
    let mustContainAny: [String]
}

let cases: [TestCase] = [
    .init(label: "exact, two words",  query: "Wrangell visitor center",
          mustContainAny: ["wrangell"]),
    .init(label: "place + feature",   query: "Tok junction",
          mustContainAny: ["tok"]),
    .init(label: "famous pass",        query: "Atigun pass",
          mustContainAny: ["atigun"]),
    .init(label: "place + category",   query: "Coldfoot fuel",
          mustContainAny: ["coldfoot"]),
    .init(label: "single word",        query: "Denali",
          mustContainAny: ["denali"]),
    .init(label: "city name",          query: "Anchorage",
          mustContainAny: ["anchorage"]),
    .init(label: "city + category",    query: "Fairbanks ranger",
          mustContainAny: ["fairbanks"]),
    .init(label: "typo of Wrangell",   query: "Wrangle visitor center",
          mustContainAny: ["wrangell"]),
    .init(label: "typo of Atigun",     query: "Atagun pas",
          mustContainAny: ["atigun"]),
    .init(label: "altsp 'Glaciar'",    query: "Glaciar bay",
          mustContainAny: ["glacier bay", "glaciar"]),
    .init(label: "Dalton highway",     query: "Dalton",
          mustContainAny: ["dalton"]),
    .init(label: "Chena hot spring",   query: "Chena hot spring",
          mustContainAny: ["chena"]),
]

print("Opening \(DB_PATH)…")
print("SQLite version: \(String(cString: sqlite3_libversion()))")
print("cwd: \(FileManager.default.currentDirectoryPath)")
print("DB exists: \(FileManager.default.fileExists(atPath: DB_PATH))")
let db = DB(path: DB_PATH)

// Smoke test: simple SELECT
do {
    var stmt: OpaquePointer?
    let rc = sqlite3_prepare_v2(db.handle, "SELECT COUNT(*) FROM places_word WHERE places_word MATCH 'denali*'", -1, &stmt, nil)
    print("smoke prepare rc=\(rc) (\(String(cString: sqlite3_errmsg(db.handle))))")
    if rc == SQLITE_OK {
        if sqlite3_step(stmt) == SQLITE_ROW {
            print("smoke count: \(sqlite3_column_int(stmt, 0))")
        }
    }
    sqlite3_finalize(stmt)
}

var summary: [(label: String, pass: Bool, stage: Int)] = []

for c in cases {
    print("\n=== \(c.label):  \"\(c.query)\" ===")
    let (parsed, hits) = search(c.query, db: db, limit: 10)
    print("  parsed: nameTokens=\(parsed.nameTokens)  catHints=\(parsed.categoryHints)")
    for (i, h) in hits.enumerated() {
        print(format(h, idx: i + 1))
    }
    if hits.isEmpty {
        print("  (no hits)")
    }
    let pass = hits.contains { h in
        let lower = h.name.lowercased()
        return c.mustContainAny.contains { lower.contains($0) }
    }
    let stage = hits.first?.stage ?? 0
    summary.append((c.label, pass, stage))
}

print("\n========================================")
print("SUMMARY  (✓ = expected hit appeared in top-10)")
print("========================================")
print("case".padded(30) + " result    stage")
for s in summary {
    let mark = s.pass ? "✓" : "✗"
    let stageStr = s.stage == 0 ? "—" : "s\(s.stage)"
    print(s.label.padded(30) + " \(mark)         \(stageStr)")
}
let passed = summary.filter(\.pass).count
print("\ntotal: \(passed)/\(summary.count)")
