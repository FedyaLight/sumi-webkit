import AppKit
import SwiftUI
import XCTest

@testable import Sumi

@MainActor
final class SumiFaviconAccentColorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        (SumiFaviconAccentCacheDefaults.cache as? SumiFaviconAccentCache)?.resetForTesting()
    }

    override func tearDown() {
        // The accent cache is process-scoped; clear it between tests so one
        // test's stored colors cannot leak into another.
        (SumiFaviconAccentCacheDefaults.cache as? SumiFaviconAccentCache)?.resetForTesting()
        super.tearDown()
    }

    func testExtractsDominantRedFromSolidImage() {
        let image = makeSolidImage(color: NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1))
        let color = SumiFaviconAccentColor.extract(from: image)
        XCTAssertNotNil(color)
    }

    func testExtractsBrightRedFromYoutubeLikeFavicon() {
        let image = makeYoutubeLikeImage()
        let color = SumiFaviconAccentColor.extract(from: image)
        let nsColor = NSColor(color!)

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        nsColor.usingColorSpace(.sRGB)?.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: nil
        )

        XCTAssertTrue(hue < 0.04 || hue > 0.96)
        XCTAssertGreaterThan(saturation, 0.8)
        XCTAssertGreaterThan(brightness, 0.72)
    }

    func testClampsNearWhiteTowardReadableBrightness() {
        let clamped = SumiFaviconAccentColor.clampedDisplayColor(.white)
        let nsColor = NSColor(clamped)
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        nsColor.usingColorSpace(.sRGB)?.getHue(nil, saturation: &saturation, brightness: &brightness, alpha: nil)
        XCTAssertEqual(saturation, 0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(brightness, 0.56)
    }

    func testExtractsDarkNeutralFromBlackAndWhiteFavicon() {
        let image = makeBlackAndWhiteImage()
        let color = SumiFaviconAccentColor.extract(from: image)
        let nsColor = NSColor(color!)

        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        nsColor.usingColorSpace(.sRGB)?.getHue(nil, saturation: &saturation, brightness: &brightness, alpha: nil)

        XCTAssertEqual(saturation, 0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(brightness, 0.56)
        XCTAssertGreaterThanOrEqual(brightness, 0.24)
    }

    func testAccentCacheStoresAndReturnsColor() {
        let key = "example.com"
        let cache = SumiFaviconAccentCacheDefaults.cache
        cache.store(color: .red, forKey: key)
        XCTAssertNotNil(cache.color(forKey: key))
        cache.invalidate(forKey: key)
        XCTAssertNil(cache.color(forKey: key))
    }

    func testAccentCacheDomainInvalidation() {
        let cache = SumiFaviconAccentCacheDefaults.cache
        cache.store(color: .red, forKey: "example.com")
        cache.store(color: .blue, forKey: "example.com|icon")
        cache.store(color: .green, forKey: "other.test")

        cache.invalidate(domain: "example.com")

        XCTAssertNil(cache.color(forKey: "example.com"))
        XCTAssertNil(cache.color(forKey: "example.com|icon"))
        XCTAssertNotNil(cache.color(forKey: "other.test"))
        cache.invalidate(forKey: "other.test")
    }

    func testPinnedTileAccentResolverReadsInjectedPartitionCacheFirst() {
        let cache = RecordingFaviconAccentCache()
        let url = URL(string: "https://Example.com/path")!
        let partition = SumiFaviconPartition(profileIdentifier: "Work", isPrivate: false)
        let partitionKey = SumiFaviconAccentCache.cacheKey(
            domain: "example.com",
            faviconIdentity: partition.storageComponent
        )
        let domainKey = SumiFaviconAccentCache.cacheKey(domain: "example.com")
        cache.store(color: .red, forKey: domainKey)
        cache.store(color: .blue, forKey: partitionKey)

        let color = PinnedTileAccentResolver.cachedAccent(
            for: url,
            partition: partition,
            accentCache: cache
        )

        XCTAssertNotNil(color)
        XCTAssertEqual(cache.requestedKeys, [partitionKey])
    }

    func testPinnedTileAccentResolverFallsBackToInjectedDomainCache() {
        let cache = RecordingFaviconAccentCache()
        let url = URL(string: "https://Example.com/path")!
        let partition = SumiFaviconPartition(profileIdentifier: "Work", isPrivate: false)
        let partitionKey = SumiFaviconAccentCache.cacheKey(
            domain: "example.com",
            faviconIdentity: partition.storageComponent
        )
        let domainKey = SumiFaviconAccentCache.cacheKey(domain: "example.com")
        cache.store(color: .red, forKey: domainKey)

        let color = PinnedTileAccentResolver.cachedAccent(
            for: url,
            partition: partition,
            accentCache: cache
        )

        XCTAssertNotNil(color)
        XCTAssertEqual(cache.requestedKeys, [partitionKey, domainKey])
    }

    func testPinnedTileAccentResolverStoresAndInvalidatesInjectedCache() {
        let cache = RecordingFaviconAccentCache()
        let url = URL(string: "https://Example.com/path")!
        let partition = SumiFaviconPartition(profileIdentifier: "Work", isPrivate: false)
        let partitionKey = SumiFaviconAccentCache.cacheKey(
            domain: "example.com",
            faviconIdentity: partition.storageComponent
        )
        let domainKey = SumiFaviconAccentCache.cacheKey(domain: "example.com")

        PinnedTileAccentResolver.storeAccent(
            .green,
            for: url,
            partition: partition,
            accentCache: cache
        )
        PinnedTileAccentResolver.invalidateAccent(for: url, accentCache: cache)

        XCTAssertEqual(Set(cache.storedKeys), [partitionKey, domainKey])
        XCTAssertEqual(cache.invalidatedDomains, ["example.com"])
    }

    private func makeSolidImage(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        image.unlockFocus()
        return image
    }

    private func makeYoutubeLikeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 2, y: 6, width: 28, height: 20), xRadius: 5, yRadius: 5).fill()

        NSColor.white.setFill()
        let play = NSBezierPath()
        play.move(to: NSPoint(x: 13, y: 11))
        play.line(to: NSPoint(x: 13, y: 21))
        play.line(to: NSPoint(x: 22, y: 16))
        play.close()
        play.fill()
        image.unlockFocus()
        return image
    }

    private func makeBlackAndWhiteImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 6, y: 6, width: 20, height: 20)).fill()
        image.unlockFocus()
        return image
    }
}

@MainActor
private final class RecordingFaviconAccentCache: SumiFaviconAccentCaching {
    private var colorsByKey: [String: Color] = [:]
    private(set) var requestedKeys: [String] = []
    private(set) var storedKeys: [String] = []
    private(set) var invalidatedDomains: [String] = []

    func color(forKey key: String) -> Color? {
        requestedKeys.append(key)
        return colorsByKey[key]
    }

    func store(color: Color, forKey key: String) {
        storedKeys.append(key)
        colorsByKey[key] = color
    }

    func invalidate(forKey key: String) {
        colorsByKey.removeValue(forKey: key)
    }

    func invalidate(domain: String) {
        invalidatedDomains.append(domain)
    }
}
