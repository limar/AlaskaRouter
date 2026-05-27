import CoreLocation
import XCTest
@testable import AlaskaRouter

final class AlaskaRouterSmokeTests: XCTestCase {
    func testQueryParserParsesSimpleNameToken() {
        let parsed = QueryParser.parse("Denali")

        XCTAssertEqual(parsed.nameTokens, ["denali"])
        XCTAssertEqual(parsed.categoryHints, [])
    }

    func testSmartInsertHaversineIsZeroForSameCoordinate() {
        let denali = CLLocationCoordinate2D(latitude: 63.0695, longitude: -151.0074)

        XCTAssertEqual(SmartInsert.haversine(denali, denali), 0, accuracy: 0.0001)
    }
}
