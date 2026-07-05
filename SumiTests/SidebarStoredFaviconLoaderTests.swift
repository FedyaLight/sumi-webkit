@testable import Sumi
import XCTest

@MainActor
final class SidebarStoredFaviconLoaderTests: XCTestCase {
    func testLoadKeyIncludesURLPartitionAndRefreshIdentity() throws {
        let loader = SidebarStoredFaviconLoader()
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))

        let key = loader.loadKey(launchURL: launchURL, partition: partition)

        XCTAssertTrue(key.contains(launchURL.absoluteString))
        XCTAssertTrue(key.contains(partition.storageComponent))
    }

    func testDisabledLoadKeyIgnoresURLAndPartitionPolicyInputs() throws {
        let loader = SidebarStoredFaviconLoader()
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))

        let key = loader.loadKey(
            launchURL: launchURL,
            partition: partition,
            isEnabled: false,
            disabledID: "pin-id"
        )

        XCTAssertTrue(key.hasPrefix("disabled|pin-id|"))
        XCTAssertFalse(key.contains(launchURL.absoluteString))
        XCTAssertFalse(key.contains(partition.storageComponent))
    }

    func testDomainInvalidationRefreshesOnlyMatchingLaunchURL() throws {
        let loader = SidebarStoredFaviconLoader()
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular(nil)
        let originalKey = loader.loadKey(launchURL: launchURL, partition: partition)

        loader.invalidateIfNeeded(
            for: Notification(
                name: .faviconCacheUpdated,
                userInfo: [NSNotification.Name.faviconCacheUpdatedDomainKey: "other.example"]
            ),
            launchURL: launchURL
        )
        XCTAssertEqual(loader.loadKey(launchURL: launchURL, partition: partition), originalKey)

        loader.invalidateIfNeeded(
            for: Notification(
                name: .faviconCacheUpdated,
                userInfo: [NSNotification.Name.faviconCacheUpdatedDomainKey: "example.com"]
            ),
            launchURL: launchURL
        )
        XCTAssertNotEqual(loader.loadKey(launchURL: launchURL, partition: partition), originalKey)
    }

    func testFaviconNotificationMatcherMatchesDomainUpdates() throws {
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let matchingNotification = Notification(
            name: .faviconCacheUpdated,
            userInfo: [NSNotification.Name.faviconCacheUpdatedDomainKey: "example.com"]
        )
        let nonMatchingNotification = Notification(
            name: .faviconCacheUpdated,
            userInfo: [NSNotification.Name.faviconCacheUpdatedDomainKey: "other.example"]
        )
        let broadNotification = Notification(name: .faviconCacheUpdated)

        XCTAssertTrue(SumiFaviconNotificationMatcher.update(matchingNotification, matches: launchURL))
        XCTAssertFalse(SumiFaviconNotificationMatcher.update(nonMatchingNotification, matches: launchURL))
        XCTAssertTrue(SumiFaviconNotificationMatcher.update(broadNotification, matches: launchURL))
        XCTAssertFalse(SumiFaviconNotificationMatcher.update(matchingNotification, matches: nil))
    }

    func testFaviconNotificationMatcherHonorsPartitionWhenProvided() throws {
        let launchURL = try XCTUnwrap(URL(string: "https://example.com/app"))
        let partition = SumiFaviconPartition.regular(
            try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        )
        let otherPartition = SumiFaviconPartition.regular(
            try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        )
        let matchingNotification = Notification(
            name: .faviconCacheUpdated,
            userInfo: [
                NSNotification.Name.faviconCacheUpdatedDomainKey: "example.com",
                NSNotification.Name.faviconCacheUpdatedPartitionKey: partition.storageComponent,
            ]
        )
        let otherPartitionNotification = Notification(
            name: .faviconCacheUpdated,
            userInfo: [
                NSNotification.Name.faviconCacheUpdatedDomainKey: "example.com",
                NSNotification.Name.faviconCacheUpdatedPartitionKey: otherPartition.storageComponent,
            ]
        )

        XCTAssertTrue(
            SumiFaviconNotificationMatcher.update(
                matchingNotification,
                matches: launchURL,
                partition: partition
            )
        )
        XCTAssertFalse(
            SumiFaviconNotificationMatcher.update(
                otherPartitionNotification,
                matches: launchURL,
                partition: partition
            )
        )
    }
}
