import Foundation
import XCTest

@testable import Sumi

@MainActor
final class HTTPDiskCacheBudgetTests: XCTestCase {
    private let mebibyte: UInt64 = 1_024 * 1_024

    func testClearsOldestInactiveCacheUntilAggregateFitsBudget() async throws {
        let database = try SumiDatabase.inMemory()
        let foreground = Profile(name: "Foreground")
        let oldestInactive = Profile(name: "Oldest")
        let newerInactive = Profile(name: "Newer")
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        SumiHTTPDiskCacheBudget.recordActivation(
            profileID: oldestInactive.id,
            database: database,
            now: now.addingTimeInterval(-2)
        )
        SumiHTTPDiskCacheBudget.recordActivation(
            profileID: newerInactive.id,
            database: database,
            now: now.addingTimeInterval(-1)
        )
        var sizes = [
            foreground.id: 400 * mebibyte,
            oldestInactive.id: 400 * mebibyte,
            newerInactive.id: 400 * mebibyte,
        ]

        let cleared = try await SumiHTTPDiskCacheBudget.runIfNeeded(
            profiles: [foreground, oldestInactive, newerInactive],
            foregroundProfileID: { foreground.id },
            database: database,
            now: now,
            observe: { profile in sizes[profile.id] },
            clearDiskCache: { profile in sizes[profile.id] = 0 }
        )

        XCTAssertEqual(cleared, [oldestInactive.id])
        XCTAssertEqual(sizes[foreground.id], 400 * mebibyte)
        XCTAssertEqual(sizes[oldestInactive.id], 0)
        XCTAssertEqual(sizes[newerInactive.id], 400 * mebibyte)
    }

    func testFreshObservationSkipsASecondWebKitScan() async throws {
        let database = try SumiDatabase.inMemory()
        let foreground = Profile(name: "Foreground")
        let inactive = Profile(name: "Inactive")
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        var observations = 0

        _ = try await SumiHTTPDiskCacheBudget.runIfNeeded(
            profiles: [foreground, inactive],
            foregroundProfileID: { foreground.id },
            database: database,
            now: now,
            observe: { _ in
                observations += 1
                return self.mebibyte
            },
            clearDiskCache: { _ in }
        )
        observations = 0

        let cleared = try await SumiHTTPDiskCacheBudget.runIfNeeded(
            profiles: [foreground, inactive],
            foregroundProfileID: { foreground.id },
            database: database,
            now: now.addingTimeInterval(60),
            observe: { _ in
                observations += 1
                return self.mebibyte
            },
            clearDiskCache: { _ in }
        )

        XCTAssertTrue(cleared.isEmpty)
        XCTAssertEqual(observations, 0)
    }

    func testUnknownSizeNeverTriggersCacheDeletion() async throws {
        let database = try SumiDatabase.inMemory()
        let foreground = Profile(name: "Foreground")
        let inactive = Profile(name: "Inactive")
        var cleared: [UUID] = []

        let result = try await SumiHTTPDiskCacheBudget.runIfNeeded(
            profiles: [foreground, inactive],
            foregroundProfileID: { foreground.id },
            database: database,
            observe: { profile in
                profile.id == inactive.id ? nil : 2 * SumiHTTPDiskCacheBudget.targetBytes
            },
            clearDiskCache: { profile in cleared.append(profile.id) }
        )

        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(cleared.isEmpty)
    }

    func testForegroundCacheIsNeverAnAutomaticEvictionTarget() async throws {
        let database = try SumiDatabase.inMemory()
        let foreground = Profile(name: "Foreground")
        let inactive = Profile(name: "Inactive")
        var sizes = [
            foreground.id: 2 * SumiHTTPDiskCacheBudget.targetBytes,
            inactive.id: 200 * mebibyte,
        ]

        let cleared = try await SumiHTTPDiskCacheBudget.runIfNeeded(
            profiles: [foreground, inactive],
            foregroundProfileID: { foreground.id },
            database: database,
            observe: { profile in sizes[profile.id] },
            clearDiskCache: { profile in sizes[profile.id] = 0 }
        )

        XCTAssertEqual(cleared, [inactive.id])
        XCTAssertEqual(sizes[foreground.id], 2 * SumiHTTPDiskCacheBudget.targetBytes)
    }
}
