import Combine
import XCTest

@testable import Sumi

@MainActor
final class SumiLiveFolderManagerTests: XCTestCase {
    func testCreateGitHubFolderUsesInjectedRuntime() throws {
        let spy = LiveFolderRuntimeSpy()
        let manager = try makeManager(runtime: spy.runtime())

        manager.createGitHubFolder(in: spy.spaceId, kind: .githubIssues)

        XCTAssertEqual(spy.createdFolders.count, 1)
        XCTAssertEqual(spy.createdFolders[0].spaceId, spy.spaceId)
        XCTAssertEqual(spy.createdFolders[0].name, SumiLiveFolderKind.githubIssues.defaultFolderName)
        XCTAssertEqual(spy.iconUpdates.count, 1)
        XCTAssertEqual(spy.iconUpdates[0].folderId, spy.folderId)
        XCTAssertEqual(spy.iconUpdates[0].icon, "zen:logo-github")
        let source = try XCTUnwrap(manager.source(for: spy.folderId))
        XCTAssertEqual(source.kind, .githubIssues)
        XCTAssertEqual(source.spaceId, spy.spaceId)
    }

    func testOpenItemUsesInjectedRuntimePreferredSpace() throws {
        let spy = LiveFolderRuntimeSpy()
        let manager = try makeManager(runtime: spy.runtime())
        manager.createGitHubFolder(in: spy.spaceId, kind: .githubPullRequests)
        let source = try XCTUnwrap(manager.source(for: spy.folderId))
        let item = SumiLiveFolderItem(
            id: "pull-1",
            sourceId: source.id,
            title: "Fix runtime bridge",
            urlString: "https://github.com/sumi/browser/pull/1",
            subtitle: nil,
            publishedAt: nil,
            updatedAt: nil,
            sortDate: nil,
            stateBadge: nil,
            iconSystemName: nil,
            shortcutPinId: nil,
            firstSeenAt: Date(),
            lastSeenAt: Date()
        )
        let windowState = BrowserWindowState()

        manager.open(item: item, in: windowState)

        XCTAssertEqual(spy.openedTabs.count, 1)
        XCTAssertEqual(spy.openedTabs[0].urlString, item.urlString)
        XCTAssertIdentical(spy.openedTabs[0].windowState, windowState)
        XCTAssertEqual(spy.openedTabs[0].preferredSpaceId, spy.spaceId)
    }

    func testRefreshDerivesProfileFromOwningSpace() async throws {
        let spy = LiveFolderRuntimeSpy()
        let manager = try makeManager(runtime: spy.runtime())

        manager.createGitHubFolder(
            in: spy.spaceId,
            kind: .githubIssues
        )
        for _ in 0..<20 where spy.profileRequests.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(spy.profileRequests.count, 1)
        XCTAssertNil(spy.profileRequests.first?.explicitProfileID)
        XCTAssertEqual(spy.profileRequests.first?.spaceID, spy.spaceId)
    }

    func testRSSRefreshBacksItemsWithNativePinsAndReusesThemOnOpen() async throws {
        let spy = LiveFolderRuntimeSpy()
        let manager = try makeManager(runtime: spy.runtime())

        await manager.createRSSFolder(
            in: spy.spaceId,
            feedURLString: "https://example.test/feed.xml"
        )

        XCTAssertEqual(spy.createdFolders.first?.name, "Sumi Updates")
        XCTAssertEqual(spy.iconUpdates.first?.icon, "zen:logo-rss")

        for _ in 0..<100 where manager.visibleItems(for: spy.folderId).isEmpty {
            try await Task.sleep(for: .milliseconds(1))
        }

        let item = try XCTUnwrap(manager.visibleItems(for: spy.folderId).first)
        XCTAssertEqual(item.shortcutPinId, spy.itemPinId)
        XCTAssertEqual(spy.reconciledItems.map(\.id), [item.id])

        let windowState = BrowserWindowState()
        manager.open(item: item, in: windowState)

        XCTAssertEqual(spy.activatedItems.map(\.id), [item.id])
        XCTAssertTrue(spy.openedTabs.isEmpty)

        manager.dismiss(item: item)

        XCTAssertEqual(spy.removedItems.map(\.id), [item.id])
        XCTAssertTrue(manager.visibleItems(for: spy.folderId).isEmpty)
    }

    func testDetachKeepsNativePinAndDismissesLiveResult() async throws {
        let spy = LiveFolderRuntimeSpy()
        let manager = try makeManager(runtime: spy.runtime())
        await manager.createRSSFolder(
            in: spy.spaceId,
            feedURLString: "https://example.test/feed.xml"
        )
        for _ in 0..<100 where manager.visibleItems(for: spy.folderId).isEmpty {
            try await Task.sleep(for: .milliseconds(1))
        }
        let item = try XCTUnwrap(manager.visibleItems(for: spy.folderId).first)

        manager.detach(item: item)

        XCTAssertEqual(spy.detachedItems.map(\.id), [item.id])
        XCTAssertTrue(spy.removedItems.isEmpty)
        XCTAssertTrue(manager.visibleItems(for: spy.folderId).isEmpty)
    }

    func testFolderContentChangesCoverMutationsWithoutUnrelatedFolderWork() throws {
        let spy = LiveFolderRuntimeSpy()
        let manager = try makeManager(runtime: spy.runtime())
        let unrelatedFolderID = UUID()
        var targetChanges = 0
        var unrelatedChanges = 0

        let target = manager.contentChanges(for: spy.folderId).sink {
            targetChanges += 1
        }
        let unrelated = manager.contentChanges(for: unrelatedFolderID).sink {
            unrelatedChanges += 1
        }
        manager.createGitHubFolder(in: spy.spaceId, kind: .githubIssues)
        XCTAssertEqual(targetChanges, 1)
        XCTAssertEqual(unrelatedChanges, 0)

        let source = try XCTUnwrap(manager.source(for: spy.folderId))
        manager.setRefreshInterval(folderId: spy.folderId, seconds: 900)
        XCTAssertEqual(targetChanges, 2)

        manager.dismiss(item: makeItem(sourceID: source.id))
        XCTAssertEqual(targetChanges, 3)

        manager.deleteState(forFolderIds: [spy.folderId])
        XCTAssertEqual(targetChanges, 4)

        manager.createGitHubFolder(in: spy.spaceId, kind: .githubIssues)
        XCTAssertEqual(targetChanges, 5)
        let removedItemCount = spy.removedItems.count
        manager.stopAndClearRuntime()

        XCTAssertEqual(targetChanges, 6)
        XCTAssertEqual(unrelatedChanges, 0)
        XCTAssertEqual(spy.removedItems.count, removedItemCount)
        withExtendedLifetime((target, unrelated)) { /* Keep subscriptions alive. */ }
    }

    func testDeletingFolderWhileModuleIsStoppedCannotRestoreOrphanedLiveState() async throws {
        let database = try SumiDatabase.inMemory()
        let store = SumiLiveFolderStore(database: database)
        let spy = LiveFolderRuntimeSpy()
        let source = SumiLiveFolderSource(
            folderId: spy.folderId,
            spaceId: spy.spaceId,
            kind: .githubIssues
        )
        let item = makeItem(sourceID: source.id)
        try await store.save(SumiLiveFolderDiskState(
            sources: [source],
            itemCaches: [SumiLiveFolderItemCache(sourceId: source.id, items: [item])],
            dismissals: []
        ))
        let manager = SumiLiveFolderManager(
            store: store,
            networkClient: stubNetworkClient()
        )

        manager.deleteState(forFolderIds: [spy.folderId])
        manager.attach(runtime: spy.runtime())
        manager.startAfterTabRestore()

        for _ in 0..<100 {
            if try await store.load().sources.isEmpty { break }
            await Task.yield()
        }
        let storedState = try await store.load()
        XCTAssertTrue(storedState.sources.isEmpty)
        XCTAssertNil(manager.source(for: spy.folderId))
        XCTAssertTrue(spy.reconciledItems.isEmpty)
    }

    func testReorderingBackedItemPersistsVisibleLiveFolderOrder() async throws {
        let database = try SumiDatabase.inMemory()
        let store = SumiLiveFolderStore(database: database)
        let spy = LiveFolderRuntimeSpy()
        spy.existingFolderIDs = [spy.folderId]
        var source = SumiLiveFolderSource(
            folderId: spy.folderId,
            spaceId: spy.spaceId,
            kind: .githubIssues
        )
        source.isEnabled = false
        var first = makeItem(sourceID: source.id)
        first.id = "first"
        first.shortcutPinId = UUID()
        var second = makeItem(sourceID: source.id)
        second.id = "second"
        second.shortcutPinId = UUID()
        try await store.save(SumiLiveFolderDiskState(
            sources: [source],
            itemCaches: [SumiLiveFolderItemCache(
                sourceId: source.id,
                items: [first, second]
            )],
            dismissals: []
        ))
        let manager = SumiLiveFolderManager(
            store: store,
            networkClient: stubNetworkClient()
        )
        manager.attach(runtime: spy.runtime())
        manager.startAfterTabRestore()
        for _ in 0..<100 where manager.visibleItems(for: spy.folderId).count != 2 {
            await Task.yield()
        }

        manager.reconcileExternalMove(
            shortcutPinID: try XCTUnwrap(second.shortcutPinId),
            fromFolderID: spy.folderId,
            toFolderID: spy.folderId,
            targetIndex: 0
        )

        XCTAssertEqual(
            manager.visibleItems(for: spy.folderId).map(\.id),
            ["second", "first"]
        )
        for _ in 0..<100 {
            let storedIDs = try await store.load().itemCaches.first?.items.map(\.id)
            if storedIDs == ["second", "first"] { break }
            await Task.yield()
        }
        let storedState = try await store.load()
        XCTAssertEqual(
            storedState.itemCaches.first?.items.map(\.id),
            ["second", "first"]
        )
    }

    func testLegacyLiveFolderStateDecodesWithoutNativePinFields() throws {
        let source = SumiLiveFolderSource(
            folderId: UUID(),
            spaceId: UUID(),
            kind: .githubPullRequests
        )
        let item = makeItem(sourceID: source.id)
        let encoder = JSONEncoder()
        var sourceJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(source)) as? [String: Any]
        )
        var itemJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(item)) as? [String: Any]
        )
        sourceJSON["githubDashboardMode"] = nil
        itemJSON["shortcutPinId"] = nil

        let decoder = JSONDecoder()
        let decodedSource = try decoder.decode(
            SumiLiveFolderSource.self,
            from: JSONSerialization.data(withJSONObject: sourceJSON)
        )
        let decodedItem = try decoder.decode(
            SumiLiveFolderItem.self,
            from: JSONSerialization.data(withJSONObject: itemJSON)
        )

        XCTAssertNil(decodedSource.githubDashboardMode)
        XCTAssertNil(decodedItem.shortcutPinId)
    }

    func testFetchedItemsPreserveSurvivingOrderAndAppendNewResults() {
        let sourceID = UUID()
        var first = makeItem(sourceID: sourceID)
        first.id = "first"
        first.title = "Cached first"
        var second = makeItem(sourceID: sourceID)
        second.id = "second"
        second.title = "Cached second"
        var refreshedSecond = second
        refreshedSecond.title = "Refreshed second"
        var refreshedFirst = first
        refreshedFirst.title = "Refreshed first"
        var third = makeItem(sourceID: sourceID)
        third.id = "third"

        let merged = SumiLiveFolderItemMerge.retainingExistingOrder(
            [refreshedSecond, refreshedFirst, third],
            with: [first, second],
            at: Date()
        )

        XCTAssertEqual(merged.map(\.id), ["first", "second", "third"])
        XCTAssertEqual(merged.map(\.title), ["Cached first", "Cached second", "Scoped item"])
    }

    func testFailureKeepsZenRefreshIntervalWithoutBackoff() {
        var source = SumiLiveFolderSource(
            folderId: UUID(),
            spaceId: UUID(),
            kind: .githubIssues
        )
        source.refreshIntervalSeconds = 15 * 60
        let failureDate = Date()

        source.markFailure(.network, at: failureDate)

        XCTAssertEqual(
            source.nextRefreshAfter,
            failureDate.addingTimeInterval(15 * 60)
        )
    }

    private func makeItem(sourceID: UUID) -> SumiLiveFolderItem {
        SumiLiveFolderItem(
            id: "item-1",
            sourceId: sourceID,
            title: "Scoped item",
            urlString: "https://example.test/item-1",
            subtitle: nil,
            publishedAt: nil,
            updatedAt: nil,
            sortDate: nil,
            stateBadge: nil,
            iconSystemName: nil,
            shortcutPinId: nil,
            firstSeenAt: Date(),
            lastSeenAt: Date()
        )
    }

    private func makeManager(runtime: SumiLiveFolderRuntime) throws -> SumiLiveFolderManager {
        let manager = SumiLiveFolderManager(
            store: SumiLiveFolderStore(
                database: try SumiDatabase.inMemory()
            ),
            networkClient: stubNetworkClient()
        )
        manager.attach(runtime: runtime)
        return manager
    }

    private func stubNetworkClient() -> SumiLiveFolderNetworkClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LiveFolderURLProtocolStub.self]
        return SumiLiveFolderNetworkClient(
            session: URLSession(configuration: configuration)
        )
    }
}

private final class LiveFolderURLProtocolStub: URLProtocol {
    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let responseURL = request.url ?? URL(fileURLWithPath: "/")
        let isFeed = responseURL.lastPathComponent == "feed.xml"
        guard let response = HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": isFeed ? "application/rss+xml" : "text/html"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(
            self,
            didLoad: isFeed ? Self.feedData : Data("<html><body></body></html>".utf8)
        )
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { /* No-op. */ }

    private static let feedData = Data(
        """
        <rss version="1.0">
          <channel>
            <title>Sumi Updates</title>
            <item>
              <title>Native live item</title>
              <link>https://example.test/posts/native-live-item</link>
              <guid>native-live-item</guid>
              <pubDate>Wed, 17 Jun 2026 08:00:00 GMT</pubDate>
            </item>
          </channel>
        </rss>
        """.utf8
    )
}

@MainActor
private final class LiveFolderRuntimeSpy {
    let spaceId = UUID()
    let profileId = UUID()
    let folderId = UUID()
    let itemPinId = UUID()
    var existingFolderIDs: Set<UUID> = []
    var createdFolders: [(spaceId: UUID, name: String)] = []
    var iconUpdates: [(folderId: UUID, icon: String)] = []
    var openedTabs: [LiveFolderOpenedTab] = []
    var reconciledItems: [SumiLiveFolderItem] = []
    var removedItems: [SumiLiveFolderItem] = []
    var detachedItems: [SumiLiveFolderItem] = []
    var activatedItems: [SumiLiveFolderItem] = []
    var profileRequests: [(
        explicitProfileID: UUID?,
        spaceID: UUID
    )] = []

    func runtime() -> SumiLiveFolderRuntime {
        let spaceId = spaceId
        let profileId = profileId
        let folderId = folderId
        return SumiLiveFolderRuntime(
            spaceContext: { [spaceId, profileId] requestedSpaceId in
                requestedSpaceId == spaceId
                    ? SumiLiveFolderRuntime.SpaceContext(profileId: profileId)
                    : nil
            },
            createLiveFolder: { [weak self] spaceId, name in
                guard let self else { return nil }
                self.createdFolders.append((spaceId: spaceId, name: name))
                return folderId
            },
            markFolderLive: { _ in /* No-op. */ },
            updateFolderIcon: { [weak self] folderId, icon in
                self?.iconUpdates.append((folderId: folderId, icon: icon))
            },
            openNewTab: { [weak self] urlString, windowState, preferredSpaceId in
                self?.openedTabs.append(LiveFolderOpenedTab(
                    urlString: urlString,
                    windowState: windowState,
                    preferredSpaceId: preferredSpaceId
                ))
            },
            profile: { [weak self] explicitProfileID, spaceID in
                self?.profileRequests.append((explicitProfileID, spaceID))
                return nil
            },
            folderIds: { [weak self] in self?.existingFolderIDs ?? [] },
            itemTabs: SumiLiveFolderItemTabRuntime(
                reconcile: { [weak self] _, items in
                    guard let self else { return items }
                    reconciledItems.append(contentsOf: items)
                    return items.map { item in
                        var backed = item
                        if backed.shortcutPinId == nil {
                            backed.shortcutPinId = itemPinId
                        }
                        return backed
                    }
                },
                remove: { [weak self] _, items in
                    self?.removedItems.append(contentsOf: items)
                },
                detach: { [weak self] item, _ in
                    self?.detachedItems.append(item)
                    return true
                },
                activate: { [weak self] item, _, _ in
                    self?.activatedItems.append(item)
                    return item.shortcutPinId != nil
                }
            )
        )
    }
}

private struct LiveFolderOpenedTab {
    let urlString: String
    let windowState: BrowserWindowState
    let preferredSpaceId: UUID?
}
