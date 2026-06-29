import XCTest

@testable import Sumi

final class SumiPermissionDomainCacheTests: XCTestCase {
    func testDisplayDomainFormatterPreservesExistingBehavior() {
        let cache = SumiPermissionDomainCache(limit: 4)

        XCTAssertEqual(
            SumiPermissionDisplayDomainFormatter.lowercasedDisplayDomain(" Example.COM "),
            "example.com"
        )
        XCTAssertEqual(
            SumiPermissionDisplayDomainFormatter.lowercasedDisplayDomain("   "),
            "Unknown Origin"
        )
        XCTAssertEqual(
            SumiPermissionDisplayDomainFormatter.trimmedDisplayDomain(" Example.COM "),
            "Example.COM"
        )
        XCTAssertEqual(
            SumiPermissionDisplayDomainFormatter.trimmedDisplayDomain("   "),
            "Current site"
        )
        XCTAssertEqual(cache.lowercasedDisplayDomain(" Example.COM "), "example.com")
        XCTAssertEqual(cache.lowercasedDisplayDomain("   "), "Unknown Origin")
        XCTAssertEqual(cache.trimmedDisplayDomain(" Example.COM "), "Example.COM")
        XCTAssertEqual(cache.trimmedDisplayDomain("   "), "Current site")
    }

    func testDisplayDomainLeafModelsUseFormatterSemantics() {
        let origin = SumiPermissionOrigin(string: "https://example.com")
        let request = SumiPermissionRequest(
            requestingOrigin: origin,
            topOrigin: origin,
            displayDomain: " Example.COM ",
            permissionTypes: [.geolocation],
            profilePartitionId: "Profile-A"
        )
        let key = SumiPermissionKey(
            requestingOrigin: origin,
            topOrigin: origin,
            permissionType: .geolocation,
            profilePartitionId: "Profile-A"
        )
        let record = SumiPermissionStoreRecord(
            key: key,
            decision: SumiPermissionDecision(
                state: .allow,
                persistence: .persistent,
                source: .user
            ),
            displayDomain: " Example.COM "
        )
        let indicatorEvent = SumiPermissionIndicatorEventRecord(
            tabId: "Tab-A",
            pageId: "Page-A",
            displayDomain: " Example.COM ",
            permissionTypes: [.geolocation],
            category: .pendingRequest,
            visualStyle: .attention,
            priority: .pendingSensitiveRequest
        )

        XCTAssertEqual(request.displayDomain, "Example.COM")
        XCTAssertEqual(record.displayDomain, "example.com")
        XCTAssertEqual(indicatorEvent.displayDomain, "Example.COM")
        XCTAssertEqual(
            SumiPermissionPromptStrings.normalizedDisplayDomain(" Example.COM "),
            "Example.COM"
        )
    }

    func testRegistrableDomainCacheReusesResolverResults() {
        let resolver = CountingRegistrableDomainResolver()
        let cache = SumiPermissionDomainCache(
            registrableDomainResolver: resolver,
            limit: 8
        )

        XCTAssertEqual(cache.registrableDomain(forHost: "www.example.com"), "example.com")
        XCTAssertEqual(cache.registrableDomain(forHost: "www.example.com"), "example.com")
        XCTAssertNil(cache.registrableDomain(forHost: "localhost"))
        XCTAssertNil(cache.registrableDomain(forHost: "localhost"))

        XCTAssertEqual(resolver.callCount, 2)
        XCTAssertEqual(resolver.hosts, ["www.example.com", "localhost"])
    }

    func testRegistrableDomainCacheCanBeClearedAndBounded() {
        let resolver = CountingRegistrableDomainResolver()
        let cache = SumiPermissionDomainCache(
            registrableDomainResolver: resolver,
            limit: 1
        )

        XCTAssertEqual(cache.registrableDomain(forHost: "www.example.com"), "example.com")
        XCTAssertEqual(cache.registrableDomain(forHost: "www.bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(cache.registrableDomain(forHost: "www.example.com"), "example.com")

        cache.clear()

        XCTAssertEqual(cache.registrableDomain(forHost: "www.example.com"), "example.com")
        XCTAssertEqual(resolver.callCount, 4)
    }
}

private final class CountingRegistrableDomainResolver: SumiRegistrableDomainResolving {
    private(set) var callCount = 0
    private(set) var hosts: [String] = []

    func registrableDomain(forHost host: String?) -> String? {
        callCount += 1
        if let host {
            hosts.append(host)
        }

        switch host {
        case "www.example.com":
            return "example.com"
        case "www.bbc.co.uk":
            return "bbc.co.uk"
        case "localhost":
            return nil
        default:
            return host
        }
    }
}
