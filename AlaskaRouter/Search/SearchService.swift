// Multi-stage retrieval search service for AlaskaRouter (ported from Spike B.5,
// extended for AlaskaRouter-22h7 milestone 2 with the loose-matcher pipeline).
//
// Stage `.strict`        — prefix-AND on name tokens, category hints as a SOFT
//                          BOOST (not a hard WHERE filter). Cheap, ~1–3 ms.
// Stage `.synonyms`      — (loose-mode only) same as strict but each token also
//                          ORs in known synonyms. "bike Whittier" expands to
//                          "(bike* OR bicycle* OR motorcycle*) whittier*",
//                          "Arctic Circle Sign" picks up "Arctic Circle Wayside"
//                          via sign↔wayside. Strictly broader; never narrows.
// Stage `.droppedTokens` — (loose-mode only) drop descriptor tokens that don't
//                          typically appear in proper names (ferry, sign, the,
//                          of, …) and retry. Catches "Ferry Whittier" → "Alaska
//                          Marine Highway - Whittier Terminal".
// Stage `.editDistance`  — final fallback: relaxed prefix-OR of first 3 chars
//                          per token, candidates re-ranked in Swift by
//                          Levenshtein against name + alt_names. Catches typos.
//
// The two new stages between strict and edit-distance are gated by
// `TweaksStore.useLooseMatcher` so we can A/B compare them live.
//
// Wraps the result in @Observable so SwiftUI can bind a TextField to a query
// string and a List to results. Debounced per-keystroke (~150 ms).

import Foundation
import Observation
import SQLite3
import CoreLocation

enum SearchStage: Int {
    case strict        = 1   // prefix-AND, original behavior
    case editDistance  = 2   // Levenshtein fallback. Note: kept at int 2 for
                             //   backward compatibility with the existing
                             //   SearchResultsView "fuzzy ±X" indicator.
    case synonyms      = 3   // loose-mode: token∪{synonyms}
    case droppedTokens = 4   // loose-mode: synonyms + descriptor-token drop
}

struct SearchResult: Identifiable, Hashable {
    let id: Int64                  // place_meta rowid
    let name: String
    let altNames: String
    let category: String
    let coord: CLLocationCoordinate2D
    let importance: Double
    let stage: Int                 // see SearchStage
    let editDistance: Int          // 0 except for .editDistance hits
    /// Stripped borough / census-area name from the places-DB schema v4
    /// (AlaskaRouter-b7g0). Empty when no GNIS donor within 30 km. The
    /// search-results row renders "{adminArea}, AK, USA" or just "AK, USA"
    /// when empty.
    let adminArea: String

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@Observable
@MainActor
final class SearchService {
    private let db: PlacesDB
    private(set) var query: String = ""
    private(set) var parsed: StructuredQuery = StructuredQuery(nameTokens: [], categoryHints: [])
    private(set) var results: [SearchResult] = []

    private var pendingTask: Task<Void, Never>?
    private let debounceNs: UInt64 = 150_000_000   // 150 ms

    init(db: PlacesDB) {
        self.db = db
    }

    /// Drive the search from a TextField binding. Updates `query`, debounces,
    /// then runs stage1/stage2 off the main actor.
    func setQuery(_ q: String) {
        query = q
        pendingTask?.cancel()
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            parsed = StructuredQuery(nameTokens: [], categoryHints: [])
            results = []
            return
        }
        let parsedQ = QueryParser.parse(trimmed)
        parsed = parsedQ
        if parsedQ.isEmpty {
            results = []
            return
        }
        let dbRef = db
        // Snapshot the matcher tweak on the MainActor; pass it through to the
        // background search so the nonisolated query path stays MainActor-free.
        let looseMode = TweaksStore.shared.useLooseMatcher
        pendingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceNsValue)
            guard !Task.isCancelled else { return }
            let hits = await Self.runSearch(handle: dbRef.handle, query: parsedQ, looseMode: looseMode)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.results = hits }
        }
    }

    private static let debounceNsValue: UInt64 = 150_000_000

    // MARK: - Off-main-actor query

    nonisolated private static func runSearch(
        handle: OpaquePointer,
        query: StructuredQuery,
        looseMode: Bool
    ) async -> [SearchResult] {
        let limit = 12

        // (1) Strict — original behavior, identical regardless of looseMode.
        let strict = stage1Query(handle: handle, query: query, limit: limit,
                                 stage: .strict,
                                 expandSynonyms: false, dropDroppable: false)
        if !strict.isEmpty { return strict }

        // (2) Synonyms — only when loose mode is on. Pure expansion (never
        //     narrows), so safe to try before drop-token.
        if looseMode {
            let withSyns = stage1Query(handle: handle, query: query, limit: limit,
                                       stage: .synonyms,
                                       expandSynonyms: true, dropDroppable: false)
            if !withSyns.isEmpty { return withSyns }

            // (3) Drop descriptor tokens AND keep synonyms. Only fires when at
            //     least one droppable token is present.
            let hasDroppable = query.nameTokens.contains {
                droppableDescriptors.contains($0.lowercased())
            }
            if hasDroppable {
                let dropped = stage1Query(handle: handle, query: query, limit: limit,
                                          stage: .droppedTokens,
                                          expandSynonyms: true, dropDroppable: true)
                if !dropped.isEmpty { return dropped }
            }
        }

        // (4) Final fallback — edit distance (existing behavior).
        return stage2Query(handle: handle, query: query, limit: limit)
    }

    // MARK: - Loose-matcher dictionaries

    /// Bidirectional synonym groups. If the user's token matches any member
    /// of a group, the FTS query expands to OR all members. Keep groups to
    /// linguistic equivalents (bike↔motorcycle), not loose associations
    /// (rental↔adventures) — broad groups erode precision.
    nonisolated static let synonymGroups: [Set<String>] = [
        ["bike", "bicycle", "motorcycle", "motorbike"],
        ["mountain", "mount", "mtn"],
        ["camp", "campsite", "campground", "camping"],
        ["airport", "airfield", "airstrip"],
        ["sign", "marker", "monument", "wayside", "memorial"],
        ["rental", "rentals", "rent", "hire"],
        ["ferry", "ferries"],
        ["peak", "summit"],
        ["gas", "fuel", "petrol", "diesel"],
        ["lodge", "inn", "hostel", "motel", "hotel"],
        ["store", "shop", "market"],
        ["bay", "cove"],                          // intentional partial: coastal coves
                                                  // are often labeled "Bay" in OSM
    ]

    /// Lookup table: token → its synonym group (including itself).
    nonisolated static let synonymsByToken: [String: Set<String>] = {
        var m: [String: Set<String>] = [:]
        for group in synonymGroups {
            for t in group { m[t] = group }
        }
        return m
    }()

    /// Tokens that typically describe a place's category rather than its
    /// proper name. Dropped at stage `.droppedTokens` when strict + synonyms
    /// both yielded nothing.
    nonisolated static let droppableDescriptors: Set<String> = [
        "ferry", "ferries",
        "sign", "marker",
        "rental", "rentals", "rent", "hire",
        "the", "of", "at", "in", "and", "to", "a", "an",
    ]

    nonisolated private static func stage1Query(
        handle: OpaquePointer,
        query: StructuredQuery,
        limit: Int,
        stage: SearchStage,
        expandSynonyms: Bool,
        dropDroppable: Bool
    ) -> [SearchResult] {
        guard !query.nameTokens.isEmpty || !query.categoryHints.isEmpty else { return [] }

        let ftsArg = buildFTSExpression(
            tokens: query.nameTokens,
            expandSynonyms: expandSynonyms,
            dropDroppable: dropDroppable
        )
        var whereClauses: [String] = []
        if ftsArg != nil {
            whereClauses.append("places_word MATCH ?")
        }
        let catBoost: String
        var catParams: [String] = []
        if !query.categoryHints.isEmpty {
            let placeholders = query.categoryHints.map { _ in "?" }.joined(separator: ",")
            catBoost = "CASE WHEN m.category IN (\(placeholders)) THEN 3.0 ELSE 0.0 END"
            catParams = query.categoryHints
        } else {
            catBoost = "0.0"
        }
        // AlaskaRouter-ezt0: exact-name and name-prefix boost.
        //
        // BM25 alone misranks a major city below smaller same-prefix places
        // because cities carry huge multilingual `alt_names` (Fairbanks has
        // 226 chars of transliterations; Anchorage has 369). FTS5 treats the
        // combined name+alt_names+… as one document, so longer alt_names
        // = longer doc = worse BM25 even though the user's query is a 100%
        // match for the city's NAME.
        //
        // We bind the user's full query string (lowercased, name-tokens
        // joined by space) and add:
        //   - exact match  (lower(name) == query) → big boost (-50)
        //   - prefix-word match (lower(name) LIKE 'query %') → smaller (-15)
        // Magnitudes chosen to dominate the BM25 range (~ -2 to -10) and the
        // importance term (max 5.0), so an exact name match always wins.
        //
        // The bm25() call also gets per-column weights so name dominates
        // alt_names/category/region (10.0 vs 1.0 each).
        let joinedQuery: String? = query.nameTokens.isEmpty
            ? nil
            : query.nameTokens.map { $0.lowercased() }.joined(separator: " ")
        let nameBoost: String
        if joinedQuery != nil {
            nameBoost = """
            CASE
                WHEN LOWER(m.name) = ? THEN 50.0
                WHEN LOWER(m.name) LIKE ? THEN 15.0
                ELSE 0.0
            END
            """
        } else {
            nameBoost = "0.0"
        }
        let baseFrom: String
        let scoreExpr: String
        if ftsArg != nil {
            baseFrom = "places_word JOIN place_meta AS m ON m.rowid = places_word.rowid"
            scoreExpr = "bm25(places_word, 10.0, 1.0, 1.0, 1.0) - m.importance * 5.0 - (\(catBoost)) - (\(nameBoost))"
        } else {
            baseFrom = "place_meta AS m"
            scoreExpr = "(-m.importance * 5.0) - (\(catBoost)) - (\(nameBoost))"
        }
        let whereSql = whereClauses.isEmpty ? "1=1" : whereClauses.joined(separator: " AND ")
        let sql = """
        SELECT m.rowid, m.name, m.alt_names, m.category, m.lat, m.lon, m.importance, m.admin_area,
               (\(scoreExpr)) AS final_score
        FROM \(baseFrom)
        WHERE \(whereSql)
        ORDER BY final_score ASC
        LIMIT ?;
        """
        return runRowidSQL(handle: handle, sql: sql,
                           catParams: catParams, ftsArg: ftsArg,
                           nameBoostQuery: joinedQuery,
                           limit: limit,
                           stage: stage.rawValue)
    }

    /// Build the FTS5 MATCH expression for a list of tokens.
    /// - With both flags off: bare "tok1* tok2* …" (implicit AND — fast path).
    /// - With `expandSynonyms`: each token in a synonym group expands to
    ///   "(tok* OR syn1* OR syn2* …)" and the joiner becomes explicit `AND`
    ///   (FTS5's implicit-AND only works for bare token sequences; once any
    ///   parenthesized group is involved, every join must spell out AND).
    /// - With `dropDroppable`: descriptor tokens are skipped entirely.
    /// Returns nil if all tokens get dropped or the input is empty.
    nonisolated private static func buildFTSExpression(
        tokens: [String],
        expandSynonyms: Bool,
        dropDroppable: Bool
    ) -> String? {
        guard !tokens.isEmpty else { return nil }
        var parts: [String] = []
        var anyExpanded = false
        for raw in tokens {
            let tok = raw.lowercased()
            if dropDroppable && droppableDescriptors.contains(tok) { continue }
            if expandSynonyms, let group = synonymsByToken[tok], group.count > 1 {
                let expanded = group.sorted().map { "\($0)*" }.joined(separator: " OR ")
                parts.append("(\(expanded))")
                anyExpanded = true
            } else {
                parts.append("\(tok)*")
            }
        }
        if parts.isEmpty { return nil }
        let sep = anyExpanded ? " AND " : " "
        return parts.joined(separator: sep)
    }

    nonisolated private static func stage2Query(handle: OpaquePointer, query: StructuredQuery, limit: Int) -> [SearchResult] {
        guard !query.nameTokens.isEmpty else { return [] }
        let prefixes = query.nameTokens.filter { $0.count >= 3 }.map { String($0.prefix(3)) + "*" }
        guard !prefixes.isEmpty else { return [] }
        let ftsArg = prefixes.joined(separator: " OR ")

        let sql = """
        SELECT m.rowid, m.name, m.alt_names, m.category, m.lat, m.lon, m.importance, m.admin_area,
               bm25(places_word) AS bm
        FROM places_word JOIN place_meta AS m ON m.rowid = places_word.rowid
        WHERE places_word MATCH ?
        ORDER BY bm ASC
        LIMIT 400;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, ftsArg, -1, SQLITE_TRANSIENT)

        var raw: [SearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let r = readRow(stmt: stmt, stage: SearchStage.editDistance.rawValue, editDistance: 0)
            raw.append(r)
        }

        // In-Swift Levenshtein rerank.
        let qTokens = query.nameTokens.map { $0.lowercased() }
        let catHints = Set(query.categoryHints)
        var scored: [(SearchResult, Double)] = raw.map { r in
            let target = r.name + " | " + r.altNames
            var total = 0
            for qt in qTokens {
                total += EditDistance.minTokenDistance(qToken: qt, against: target)
            }
            let catBoost: Double = catHints.contains(r.category) ? 0.7 : 0.0
            let score = Double(total) - r.importance * 0.5 - catBoost
            var updated = r
            updated = SearchResult(
                id: r.id, name: r.name, altNames: r.altNames, category: r.category,
                coord: r.coord, importance: r.importance,
                stage: SearchStage.editDistance.rawValue, editDistance: total,
                adminArea: r.adminArea
            )
            return (updated, score)
        }
        scored = scored.filter { (r, _) in
            let target = r.name + " | " + r.altNames
            return qTokens.allSatisfy { EditDistance.minTokenDistance(qToken: $0, against: target) <= 3 }
        }
        scored.sort { $0.1 < $1.1 }
        return Array(scored.prefix(limit)).map(\.0)
    }

    nonisolated private static func runRowidSQL(
        handle: OpaquePointer,
        sql: String,
        catParams: [String],
        ftsArg: String?,
        nameBoostQuery: String?,
        limit: Int,
        stage: Int
    ) -> [SearchResult] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        // Bind order is TEXTUAL order of `?` in SQL:
        //   1. category-hint params in SELECT's CASE expression
        //   2. name-boost params: exact-match query, then prefix-LIKE pattern
        //   3. FTS MATCH in WHERE
        //   4. LIMIT
        var idx: Int32 = 1
        for c in catParams {
            sqlite3_bind_text(stmt, idx, c, -1, SQLITE_TRANSIENT); idx += 1
        }
        if let q = nameBoostQuery {
            sqlite3_bind_text(stmt, idx, q, -1, SQLITE_TRANSIENT); idx += 1
            // " %" suffix == "query followed by a space and at least one char".
            // Combined with the equality branch above this gives a word-boundary
            // prefix match: "anchorage" matches "Anchorage" (exact) and
            // "Anchorage Museum" (prefix-word), but not "Anchorages".
            let likePattern = q + " %"
            sqlite3_bind_text(stmt, idx, likePattern, -1, SQLITE_TRANSIENT); idx += 1
        }
        if let fts = ftsArg {
            sqlite3_bind_text(stmt, idx, fts, -1, SQLITE_TRANSIENT); idx += 1
        }
        sqlite3_bind_int(stmt, idx, Int32(limit))

        var hits: [SearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            hits.append(readRow(stmt: stmt, stage: stage, editDistance: 0))
        }
        return hits
    }

    nonisolated private static func readRow(stmt: OpaquePointer?, stage: Int, editDistance: Int) -> SearchResult {
        let rowid = sqlite3_column_int64(stmt, 0)
        let name = String(cString: sqlite3_column_text(stmt, 1))
        let altn = String(cString: sqlite3_column_text(stmt, 2))
        let cat = String(cString: sqlite3_column_text(stmt, 3))
        let lat = sqlite3_column_double(stmt, 4)
        let lon = sqlite3_column_double(stmt, 5)
        let imp = sqlite3_column_double(stmt, 6)
        // admin_area lives in column 7 across both SQL paths (stage 1 + 2)
        // since both query strings now SELECT m.admin_area at index 7.
        let admin = String(cString: sqlite3_column_text(stmt, 7))
        return SearchResult(
            id: rowid, name: name, altNames: altn, category: cat,
            coord: .init(latitude: lat, longitude: lon),
            importance: imp, stage: stage, editDistance: editDistance,
            adminArea: admin
        )
    }
}
