// Two-stage retrieval search service for AlaskaRouter (ported from Spike B.5).
//
// Stage 1 — strict prefix-AND on name tokens, with category hints as a SOFT
//           BOOST in scoring (not a hard WHERE filter). Cheap, hits in ~1–3 ms.
// Stage 2 — fallback when stage 1 returns nothing: relaxed prefix-OR of first
//           3 chars per token, candidates re-ranked in Swift by Levenshtein
//           against the place name + alt_names. Catches typos.
//
// Wraps the result in @Observable so SwiftUI can bind a TextField to a query
// string and a List to results. Debounced per-keystroke (~150 ms).

import Foundation
import Observation
import SQLite3
import CoreLocation

struct SearchResult: Identifiable, Hashable {
    let id: Int64                  // place_meta rowid
    let name: String
    let altNames: String
    let category: String
    let coord: CLLocationCoordinate2D
    let importance: Double
    let stage: Int                 // 1 = strict, 2 = edit-distance rerank
    let editDistance: Int          // 0 for stage-1 hits

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
        pendingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceNsValue)
            guard !Task.isCancelled else { return }
            let hits = await Self.runSearch(handle: dbRef.handle, query: parsedQ)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.results = hits }
        }
    }

    private static let debounceNsValue: UInt64 = 150_000_000

    // MARK: - Off-main-actor query

    nonisolated private static func runSearch(handle: OpaquePointer, query: StructuredQuery) async -> [SearchResult] {
        let limit = 12
        let stage1 = stage1Query(handle: handle, query: query, limit: limit)
        if !stage1.isEmpty { return stage1 }
        return stage2Query(handle: handle, query: query, limit: limit)
    }

    nonisolated private static func stage1Query(handle: OpaquePointer, query: StructuredQuery, limit: Int) -> [SearchResult] {
        guard !query.nameTokens.isEmpty || !query.categoryHints.isEmpty else { return [] }

        var ftsArg: String? = nil
        var whereClauses: [String] = []
        if !query.nameTokens.isEmpty {
            ftsArg = query.nameTokens.map { "\($0)*" }.joined(separator: " ")
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
        let baseFrom: String
        let scoreExpr: String
        if ftsArg != nil {
            baseFrom = "places_word JOIN place_meta AS m ON m.rowid = places_word.rowid"
            scoreExpr = "bm25(places_word) - m.importance * 5.0 - (\(catBoost))"
        } else {
            baseFrom = "place_meta AS m"
            scoreExpr = "(-m.importance * 5.0) - (\(catBoost))"
        }
        let whereSql = whereClauses.isEmpty ? "1=1" : whereClauses.joined(separator: " AND ")
        let sql = """
        SELECT m.rowid, m.name, m.alt_names, m.category, m.lat, m.lon, m.importance,
               (\(scoreExpr)) AS final_score
        FROM \(baseFrom)
        WHERE \(whereSql)
        ORDER BY final_score ASC
        LIMIT ?;
        """
        return runRowidSQL(handle: handle, sql: sql,
                           catParams: catParams, ftsArg: ftsArg, limit: limit,
                           stage: 1)
    }

    nonisolated private static func stage2Query(handle: OpaquePointer, query: StructuredQuery, limit: Int) -> [SearchResult] {
        guard !query.nameTokens.isEmpty else { return [] }
        let prefixes = query.nameTokens.filter { $0.count >= 3 }.map { String($0.prefix(3)) + "*" }
        guard !prefixes.isEmpty else { return [] }
        let ftsArg = prefixes.joined(separator: " OR ")

        let sql = """
        SELECT m.rowid, m.name, m.alt_names, m.category, m.lat, m.lon, m.importance,
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
            let r = readRow(stmt: stmt, stage: 2, editDistance: 0)
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
                coord: r.coord, importance: r.importance, stage: 2, editDistance: total
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
        limit: Int,
        stage: Int
    ) -> [SearchResult] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        // Bind order is TEXTUAL order of `?` in SQL:
        //   1. category-hint params in SELECT's CASE expression
        //   2. FTS MATCH in WHERE
        //   3. LIMIT
        var idx: Int32 = 1
        for c in catParams {
            sqlite3_bind_text(stmt, idx, c, -1, SQLITE_TRANSIENT); idx += 1
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
        return SearchResult(
            id: rowid, name: name, altNames: altn, category: cat,
            coord: .init(latitude: lat, longitude: lon),
            importance: imp, stage: stage, editDistance: editDistance
        )
    }
}
