import XCTest
@testable import AlaskaRouter

@MainActor
final class SearchTests: XCTestCase {
    func testQueryParserExtractsMultiWordCategoryPhrases() {
        let parsed = QueryParser.parse("Wrangell visitor center")

        XCTAssertEqual(parsed.nameTokens, ["wrangell"])
        XCTAssertEqual(parsed.categoryHints, ["visitor_center"])
    }

    func testQueryParserDeduplicatesCategoryHints() {
        let parsed = QueryParser.parse("Coldfoot gas fuel")

        XCTAssertEqual(parsed.nameTokens, ["coldfoot"])
        XCTAssertEqual(parsed.categoryHints, ["fuel"])
    }

    func testQueryParserMapsTownAndCityToSettlement() {
        // AlaskaRouter-tluk: descriptor is stripped from the name and applied
        // as a settlement category hint, so "Fairbanks town" finds Fairbanks.
        let town = QueryParser.parse("Fairbanks town")
        XCTAssertEqual(town.nameTokens, ["fairbanks"])
        XCTAssertEqual(town.categoryHints, ["settlement"])

        let city = QueryParser.parse("Bethel city")
        XCTAssertEqual(city.nameTokens, ["bethel"])
        XCTAssertEqual(city.categoryHints, ["settlement_major"])
    }

    func testCategoryLabelHumanizesKeys() {
        XCTAssertEqual(CategoryLabel.display("settlement"), "Town")
        XCTAssertEqual(CategoryLabel.display("settlement_major"), "City")
        XCTAssertEqual(CategoryLabel.display("fuel"), "Gas")
        XCTAssertEqual(CategoryLabel.display("river_crossing"), "River crossing")
        XCTAssertEqual(CategoryLabel.display("brand_new_key"), "Brand New Key") // fallback
        XCTAssertEqual(CategoryLabel.display(nil), "Stop")
    }

    func testEditDistanceTreatsPrefixesAsExactMatches() {
        XCTAssertEqual(EditDistance.minTokenDistance(qToken: "den", against: "Denali National Park"), 0)
    }

    func testEditDistanceScoresTyposAgainstNearestWord() {
        XCTAssertEqual(EditDistance.minTokenDistance(qToken: "atagun", against: "Atigun Pass"), 1)
    }

    func testBundledSearchBatteryFindsExpectedPlaces() async throws {
        let cases: [(query: String, expected: String)] = [
            ("Denali", "denali"),
            ("Anchorage", "anchorage"),
            ("Atagun pas", "atigun"),
            ("Wrangell visitor center", "wrangell"),
            ("Chena hot spring", "chena"),
            ("Fairbanks town", "fairbanks"),
        ]
        for testCase in cases {
            let service = SearchService(db: PlacesDB(bundleResource: "alaska-places"))
            let results = try await results(for: testCase.query, service: service)
            XCTAssertTrue(
                results.contains { $0.name.lowercased().contains(testCase.expected) },
                "Expected \(testCase.query) results to contain \(testCase.expected), got: \(results.map(\.name))"
            )
        }
    }

    func testExactNameMatchOutranksLongerSamePrefixPlaces() async throws {
        // AlaskaRouter-ezt0. Cities carry huge multilingual alt_names, which
        // inflate FTS5 document length and make BM25 score them BELOW small
        // same-prefix places (e.g. "Fairbanks Park" used to beat "Fairbanks").
        // The exact-name boost + column-weighted bm25 must put the city #1.
        let service = SearchService(db: PlacesDB(bundleResource: "alaska-places"))
        let results = try await results(for: "Fairbanks", service: service)
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(
            results.first?.name, "Fairbanks",
            "Expected the city 'Fairbanks' as the first result. Got: \(results.map(\.name))"
        )
    }

    func testExactNameMatchOutranksLongerSamePrefixPlacesAnchorage() async throws {
        // AlaskaRouter-ezt0 — same as above for Anchorage (369 chars of alt_names).
        let service = SearchService(db: PlacesDB(bundleResource: "alaska-places"))
        let results = try await results(for: "Anchorage", service: service)
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(
            results.first?.name, "Anchorage",
            "Expected the city 'Anchorage' as the first result. Got: \(results.map(\.name))"
        )
    }

    func testMultiWordExactMatchStillWorks() async throws {
        // Regression guard: the exact-name boost is keyed on the joined query
        // string, so multi-word names like "Fairbanks Park" must keep working.
        let service = SearchService(db: PlacesDB(bundleResource: "alaska-places"))
        let results = try await results(for: "Fairbanks Park", service: service)
        XCTAssertEqual(
            results.first?.name, "Fairbanks Park",
            "Expected 'Fairbanks Park' as the first result for that exact query. Got: \(results.map(\.name))"
        )
    }

    func testCategoryHintBindOrderStillReturnsNameMatches() async throws {
        let service = SearchService(db: PlacesDB(bundleResource: "alaska-places"))
        let results = try await results(for: "Fairbanks ranger", service: service)

        XCTAssertEqual(service.parsed.nameTokens, ["fairbanks"])
        XCTAssertEqual(service.parsed.categoryHints, ["ranger_station"])
        XCTAssertTrue(
            results.contains { $0.name.lowercased().contains("fairbanks") },
            "Category-hint bind order regressed; expected a Fairbanks-named result, got: \(results.map(\.name))"
        )
    }

    private func results(for query: String, service: SearchService) async throws -> [SearchResult] {
        service.setQuery(query)
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if !service.results.isEmpty { return service.results }
        }
        return service.results
    }
}
