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

    func testSumiSecurityOriginMapsHTTPSOriginToPermissionOrigin() {
        let origin = SumiSecurityOrigin(protocol: "https", host: "Example.COM", port: 0)
            .permissionOrigin(missingReason: "missing-test-origin")

        XCTAssertEqual(origin.kind, .web)
        XCTAssertEqual(origin.identity, "https://example.com")
    }

    func testSumiSecurityOriginMapsHTTPOriginToPermissionOrigin() {
        let origin = SumiSecurityOrigin(protocol: "http", host: "example.com", port: 0)
            .permissionOrigin(missingReason: "missing-test-origin")

        XCTAssertEqual(origin.kind, .web)
        XCTAssertEqual(origin.identity, "http://example.com")
    }

    func testSumiSecurityOriginPreservesNonDefaultPort() {
        let origin = SumiSecurityOrigin(protocol: "https", host: "example.com", port: 8443)
            .permissionOrigin(missingReason: "missing-test-origin")

        XCTAssertEqual(origin.kind, .web)
        XCTAssertEqual(origin.identity, "https://example.com:8443")
    }

    func testSumiSecurityOriginMapsNonstandardSchemeToUnsupportedPermissionOrigin() {
        let origin = SumiSecurityOrigin(protocol: "custom-scheme", host: "example.com", port: 0)
            .permissionOrigin(missingReason: "missing-test-origin")

        XCTAssertEqual(origin.kind, .unsupported)
        XCTAssertEqual(origin.identity, "unsupported:custom-scheme")
    }

    func testSumiSecurityOriginFailsClosedWhenSchemeOrHostIsMissing() {
        let missingHost = SumiSecurityOrigin(protocol: "https", host: "   ", port: 0)
            .permissionOrigin(missingReason: "missing-test-origin")
        let missingScheme = SumiSecurityOrigin(protocol: "   ", host: "example.com", port: 0)
            .permissionOrigin(missingReason: "missing-test-origin")

        XCTAssertEqual(missingHost.kind, .invalid)
        XCTAssertEqual(missingHost.detail, "missing-test-origin")
        XCTAssertEqual(missingScheme.kind, .invalid)
        XCTAssertEqual(missingScheme.detail, "missing-test-origin")
    }

    func testSumiSecurityOriginFailsClosedWhenURLComponentsCannotBuildURL() {
        let origin = SumiSecurityOrigin(protocol: "https", host: "exa mple", port: 0)
            .permissionOrigin(missingReason: "missing-test-origin")

        XCTAssertEqual(origin.kind, .invalid)
        XCTAssertEqual(origin.detail, "missing-url")
    }

    func testSumiSecurityOriginURLInitializerMatchesBSKURLSecurityOriginFields() {
        let origin = SumiSecurityOrigin(url: URL(string: "https://example.com:8443/path"))

        XCTAssertEqual(origin.protocol, "https")
        XCTAssertEqual(origin.host, "example.com")
        XCTAssertEqual(origin.port, 8443)
    }

    func testEmptySumiSecurityOriginMatchesBSKEmptyOriginShape() {
        XCTAssertEqual(SumiSecurityOrigin.empty.protocol, "")
        XCTAssertEqual(SumiSecurityOrigin.empty.host, "")
        XCTAssertEqual(SumiSecurityOrigin.empty.port, 0)
    }
}
