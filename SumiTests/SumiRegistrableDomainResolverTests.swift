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

final class SumiTrackingProtectionSiteNormalizerRegistrableDomainTests: XCTestCase {
    private let normalizer = SumiTrackingProtectionSiteNormalizer()

    func testNormalizerLowercasesAndUsesRegistrableDomain() {
        XCTAssertEqual(normalizer.normalizedHost(fromRawHost: " WWW.Example.COM. "), "example.com")
    }

    func testNormalizerFallsBackToNormalizedHostWhenRegistrableDomainIsNil() {
        XCTAssertEqual(normalizer.normalizedHost(fromRawHost: " localhost. "), "localhost")
        XCTAssertEqual(normalizer.normalizedHost(fromRawHost: "127.0.0.1"), "127.0.0.1")
    }
}
