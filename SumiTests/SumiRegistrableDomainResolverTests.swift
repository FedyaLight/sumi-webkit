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
        XCTAssertEqual(normalizer.siteDomain(fromRawDomain: " WWW.Example.COM. "), "example.com")
    }

    func testNormalizerFallsBackToNormalizedHostWhenRegistrableDomainIsNil() {
        XCTAssertEqual(normalizer.siteDomain(fromRawDomain: " localhost. "), "localhost")
        XCTAssertEqual(normalizer.siteDomain(fromRawDomain: "127.0.0.1"), "127.0.0.1")
    }

    func testNormalizedURLStripsQueryAndFragmentButPreservesPath() throws {
        let url = try XCTUnwrap(URL(string: "https://Example.COM/path?utm=1#section"))

        XCTAssertEqual(normalizer.normalizedURL(for: url)?.absoluteString, "https://example.com/path")
        XCTAssertEqual(normalizer.host(for: url), "example.com")
        XCTAssertEqual(normalizer.siteDomain(for: url), "example.com")
    }

    func testNormalizedURLNormalizesHTTPAndHTTPSCasing() throws {
        let http = try XCTUnwrap(URL(string: "HTTP://WWW.Example.COM:80/Path?one=1"))
        let https = try XCTUnwrap(URL(string: "HTTPS://WWW.Example.COM:443/Path#two"))

        XCTAssertEqual(normalizer.normalizedURL(for: http)?.absoluteString, "http://www.example.com/Path")
        XCTAssertEqual(normalizer.normalizedURL(for: https)?.absoluteString, "https://www.example.com/Path")
        XCTAssertEqual(normalizer.host(for: http), "www.example.com")
        XCTAssertEqual(normalizer.host(for: https), "www.example.com")
        XCTAssertEqual(normalizer.siteDomain(for: http), "example.com")
        XCTAssertEqual(normalizer.siteDomain(for: https), "example.com")
    }

    func testSiteDomainUsesPublicSuffixRegistrableDomain() throws {
        let url = try XCTUnwrap(URL(string: "https://news.bbc.co.uk/story?ref=home"))

        XCTAssertEqual(normalizer.host(for: url), "news.bbc.co.uk")
        XCTAssertEqual(normalizer.siteDomain(for: url), "bbc.co.uk")
    }
}
