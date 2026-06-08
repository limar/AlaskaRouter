import XCTest
import CoreLocation
@testable import AlaskaRouter

final class PlaceShareURLTests: XCTestCase {

    // Denali Visitor Center-ish coords; deliberately not round so we can see
    // the 6-decimal truncation.
    private let coord = CLLocationCoordinate2D(latitude: 63.731234, longitude: -148.912345)

    private func named(_ name: String) -> SharePlace {
        SharePlace(name: name, coordinate: coord)
    }
    private var pin: SharePlace { SharePlace(name: nil, coordinate: coord) }

    // MARK: - Apple Maps (universal https — works on Simulator)

    func testAppleNamed() {
        let url = PlaceShareURL.url(for: .appleMaps, place: named("Denali Visitor Center"))
        XCTAssertEqual(url.absoluteString,
            "https://maps.apple.com/?q=Denali%20Visitor%20Center&ll=63.731234,-148.912345")
    }

    func testApplePin() {
        let url = PlaceShareURL.url(for: .appleMaps, place: pin)
        XCTAssertEqual(url.absoluteString,
            "https://maps.apple.com/?ll=63.731234,-148.912345")
    }

    // MARK: - Google Maps (native scheme + center bias)

    func testGoogleNamed() {
        let url = PlaceShareURL.url(for: .googleMaps, place: named("Finger Mountain Wayside"))
        XCTAssertEqual(url.absoluteString,
            "comgooglemaps://?q=Finger%20Mountain%20Wayside&center=63.731234,-148.912345&zoom=14")
    }

    func testGooglePin() {
        let url = PlaceShareURL.url(for: .googleMaps, place: pin)
        XCTAssertEqual(url.absoluteString,
            "comgooglemaps://?q=63.731234,-148.912345&center=63.731234,-148.912345&zoom=15")
    }

    // MARK: - Waze (nav: coords only, name ignored)

    func testWazeNamedAndPinAreIdentical() {
        let named = PlaceShareURL.url(for: .waze, place: named("Anything"))
        let pinned = PlaceShareURL.url(for: .waze, place: pin)
        XCTAssertEqual(named.absoluteString,
            "waze://?ll=63.731234,-148.912345&navigate=yes")
        XCTAssertEqual(named.absoluteString, pinned.absoluteString)
    }

    // MARK: - Maps.me (nav/offline: coords + optional label)

    func testMapsmeNamed() {
        let url = PlaceShareURL.url(for: .mapsme, place: named("Murphy Peak"))
        XCTAssertEqual(url.absoluteString,
            "mapsme://map?v=1&ll=63.731234,-148.912345&n=Murphy%20Peak")
    }

    func testMapsmePin() {
        let url = PlaceShareURL.url(for: .mapsme, place: pin)
        XCTAssertEqual(url.absoluteString,
            "mapsme://map?v=1&ll=63.731234,-148.912345")
    }

    // MARK: - Edge cases

    func testBlankNameCollapsesToPin() {
        // Whitespace-only name must take the dropped-pin path, not emit "q=".
        let url = PlaceShareURL.url(for: .appleMaps, place: SharePlace(name: "   ", coordinate: coord))
        XCTAssertEqual(url.absoluteString, "https://maps.apple.com/?ll=63.731234,-148.912345")
    }

    func testNameWithAmpersandIsEncoded() {
        // "&" must be percent-encoded so it can't be read as a query separator.
        let url = PlaceShareURL.url(for: .appleMaps, place: named("Bed & Breakfast"))
        XCTAssertEqual(url.absoluteString,
            "https://maps.apple.com/?q=Bed%20%26%20Breakfast&ll=63.731234,-148.912345")
    }

    func testProbeURLsExistForNativeAppsOnly() {
        XCTAssertNil(MapApp.appleMaps.probeURL)
        XCTAssertEqual(MapApp.googleMaps.probeURL?.absoluteString, "comgooglemaps://")
        XCTAssertEqual(MapApp.waze.probeURL?.absoluteString, "waze://")
        XCTAssertEqual(MapApp.mapsme.probeURL?.absoluteString, "mapsme://")
    }
}
