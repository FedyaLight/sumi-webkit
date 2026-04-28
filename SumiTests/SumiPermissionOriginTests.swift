import XCTest

@testable import Sumi

final class SumiPermissionOriginTests: XCTestCase {
    func testLowercasesSchemeAndHost() {
        let origin = SumiPermissionOrigin(string: "HTTPS://Example.COM/path")

        XCTAssertEqual(origin.kind, .web)
        XCTAssertEqual(origin.scheme, "https")
        XCTAssertEqual(origin.host, "example.com")
        XCTAssertEqual(origin.identity, "https://example.com")
    }

    func testDefaultPortNormalization() {
        XCTAssertEqual(
            SumiPermissionOrigin(string: "http://Example.com:80/path").identity,
            "http://example.com"
        )
        XCTAssertEqual(
            SumiPermissionOrigin(string: "https://Example.com:443/path").identity,
            "https://example.com"
        )
    }

    func testNonDefaultPortPreservation() {
        let origin = SumiPermissionOrigin(string: "https://example.com:8443/path")

        XCTAssertEqual(origin.port, 8443)
        XCTAssertEqual(origin.identity, "https://example.com:8443")
        XCTAssertEqual(origin.displayDomain, "example.com:8443")
    }

    func testLocalDevelopmentTrustClassification() {
        for value in [
            "http://localhost",
            "http://127.0.0.1",
            "http://[::1]",
        ] {
            let origin = SumiPermissionOrigin(string: value)
            XCTAssertTrue(origin.isLocalDevelopmentOrigin, value)
            XCTAssertTrue(origin.isPotentiallyTrustworthy, value)
        }
    }

    func testFileURLRepresentation() {
        let origin = SumiPermissionOrigin(url: URL(fileURLWithPath: "/tmp/sumi-permission-test.html"))

        XCTAssertEqual(origin.kind, .file)
        XCTAssertEqual(origin.identity, "file://")
        XCTAssertEqual(origin.displayDomain, "Local File")
        XCTAssertFalse(origin.isPotentiallyTrustworthy)
    }

    func testOpaqueAndMalformedOrigins() {
        XCTAssertEqual(SumiPermissionOrigin(string: "about:blank").kind, .opaque)
        XCTAssertEqual(SumiPermissionOrigin(string: "data:text/plain,hello").kind, .opaque)
        XCTAssertEqual(SumiPermissionOrigin(string: "http://").kind, .invalid)
    }
}
