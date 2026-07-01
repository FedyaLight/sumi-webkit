import XCTest

@testable import Sumi

final class SumiRegistrableDomainResolverTests: XCTestCase {
    private let resolver = SumiRegistrableDomainResolver()

    func testRegistrableDomainReturnsNormalDomain() {
        XCTAssertEqual(resolver.registrableDomain(forHost: "example.com"), "example.com")
    }

    func testRegistrableDomainStripsSubdomains() {
        XCTAssertEqual(resolver.registrableDomain(forHost: "www.example.com"), "example.com")
        XCTAssertEqual(resolver.registrableDomain(forHost: "multi.part.example.com"), "example.com")
    }

    func testRegistrableDomainSupportsMultiPartPublicSuffixes() {
        XCTAssertEqual(resolver.registrableDomain(forHost: "www.bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(resolver.registrableDomain(forHost: "multi.part.bbc.co.uk"), "bbc.co.uk")
    }

    func testRegistrableDomainPreservesBSKNilBehavior() {
        XCTAssertNil(resolver.registrableDomain(forHost: nil))
        XCTAssertNil(resolver.registrableDomain(forHost: ""))
        XCTAssertNil(resolver.registrableDomain(forHost: "localhost"))
        XCTAssertNil(resolver.registrableDomain(forHost: "127.0.0.1"))
        XCTAssertNil(resolver.registrableDomain(forHost: "com"))
        XCTAssertNil(resolver.registrableDomain(forHost: "co.uk"))
        XCTAssertNil(resolver.registrableDomain(forHost: "abcderfg"))
    }

    func testRegistrableDomainDelegatesRawCaseBehaviorToBSK() {
        XCTAssertNil(resolver.registrableDomain(forHost: "WWW.EXAMPLE.COM"))
    }
}

final class SumiSiteNormalizerRegistrableDomainTests: XCTestCase {
    private let normalizer = SumiSiteNormalizer()

    func testNormalizerLowercasesAndUsesRegistrableDomain() {
        XCTAssertEqual(normalizer.normalizedHost(fromRawHost: " WWW.Example.COM. "), "example.com")
    }

    func testNormalizerFallsBackToNormalizedHostWhenRegistrableDomainIsNil() {
        XCTAssertEqual(normalizer.normalizedHost(fromRawHost: " localhost. "), "localhost")
        XCTAssertEqual(normalizer.normalizedHost(fromRawHost: "127.0.0.1"), "127.0.0.1")
    }

    func testIdentityStripsQueryAndFragmentButPreservesPath() throws {
        let identity = try XCTUnwrap(
            normalizer.identity(for: URL(string: "https://Example.COM/path?utm=1#section"))
        )

        XCTAssertEqual(identity.normalizedURL.absoluteString, "https://example.com/path")
        XCTAssertEqual(identity.host, "example.com")
        XCTAssertEqual(identity.displayDomain, "example.com")
        XCTAssertEqual(identity.siteDomain, "example.com")
    }

    func testIdentityNormalizesHTTPAndHTTPSCasing() throws {
        let http = try XCTUnwrap(
            normalizer.identity(for: URL(string: "HTTP://WWW.Example.COM:80/Path?one=1"))
        )
        let https = try XCTUnwrap(
            normalizer.identity(for: URL(string: "HTTPS://WWW.Example.COM:443/Path#two"))
        )

        XCTAssertEqual(http.normalizedURL.absoluteString, "http://www.example.com/Path")
        XCTAssertEqual(https.normalizedURL.absoluteString, "https://www.example.com/Path")
        XCTAssertEqual(http.host, "www.example.com")
        XCTAssertEqual(https.host, "www.example.com")
        XCTAssertEqual(http.displayDomain, "example.com")
        XCTAssertEqual(https.displayDomain, "example.com")
        XCTAssertEqual(http.siteDomain, "example.com")
        XCTAssertEqual(https.siteDomain, "example.com")
    }

    func testIdentityUsesPublicSuffixRegistrableDomain() throws {
        let identity = try XCTUnwrap(
            normalizer.identity(for: URL(string: "https://news.bbc.co.uk/story?ref=home"))
        )

        XCTAssertEqual(identity.host, "news.bbc.co.uk")
        XCTAssertEqual(identity.displayDomain, "news.bbc.co.uk")
        XCTAssertEqual(identity.siteDomain, "bbc.co.uk")
    }
}
