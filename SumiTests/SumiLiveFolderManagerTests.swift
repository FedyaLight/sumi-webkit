import Combine
import XCTest

@testable import Sumi

@MainActor
final class SumiLiveFolderManagerTests: XCTestCase {
    func testCreateGitHubFolderUsesInjectedRuntime() throws {
        let spy = LiveFolderRuntimeSpy()
        let manager = makeManager(runtime: spy.runtime())

        manager.createGitHubFolder(in: spy.spaceId, kind: .githubIssues)

        XCTAssertEqual(spy.createdFolders.count, 1)
        XCTAssertEqual(spy.createdFolders[0].spaceId, spy.spaceId)
        XCTAssertEqual(spy.createdFolders[0].name, SumiLiveFolderKind.githubIssues.defaultFolderName)
        XCTAssertEqual(spy.iconUpdates.count, 1)
        XCTAssertEqual(spy.iconUpdates[0].folderId, spy.folderId)
        XCTAssertEqual(spy.iconUpdates[0].icon, "chevron.left.forwardslash.chevron.right")
        let source = try XCTUnwrap(manager.source(for: spy.folderId))
        XCTAssertEqual(source.kind, .githubIssues)
        XCTAssertEqual(source.spaceId, spy.spaceId)
    }

    func testOpenItemUsesInjectedRuntimePreferredSpace() throws {
        let spy = LiveFolderRuntimeSpy()
        let manager = makeManager(runtime: spy.runtime())
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

    func testRefreshDerivesProfileFromOwningSpace() async {
        let spy = LiveFolderRuntimeSpy()
        let manager = makeManager(runtime: spy.runtime())

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

    func testFolderContentChangesCoverMutationsWithoutUnrelatedFolderWork() throws {
        let spy = LiveFolderRuntimeSpy()
        let manager = makeManager(runtime: spy.runtime())
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
        manager.stopAndClearRuntime()

        XCTAssertEqual(targetChanges, 6)
        XCTAssertEqual(unrelatedChanges, 0)
        withExtendedLifetime((target, unrelated)) {}
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
            firstSeenAt: Date(),
            lastSeenAt: Date()
        )
    }

    private func makeManager(runtime: SumiLiveFolderRuntime) -> SumiLiveFolderManager {
        let manager = SumiLiveFolderManager(
            store: SumiLiveFolderStore(
                database: try! SumiDatabase.inMemory()
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
        let responseURL = request.url ?? URL(string: "https://example.test")!
        let response = HTTPURLResponse(
            url: responseURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(
            self,
            didLoad: Data("<html><body></body></html>".utf8)
        )
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { /* No-op. */ }
}

@MainActor
private final class LiveFolderRuntimeSpy {
    let spaceId = UUID()
    let profileId = UUID()
    let folderId = UUID()
    var createdFolders: [(spaceId: UUID, name: String)] = []
    var iconUpdates: [(folderId: UUID, icon: String)] = []
    var openedTabs: [LiveFolderOpenedTab] = []
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
            createFolder: { [weak self] spaceId, name in
                guard let self else { return nil }
                self.createdFolders.append((spaceId: spaceId, name: name))
                return folderId
            },
            updateFolderIcon: { [weak self] folderId, icon in
                self?.iconUpdates.append((folderId: folderId, icon: icon))
            },
            renameFolder: { _, _ in /* No-op. */ },
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
            folderIds: { [] }
        )
    }
}

private struct LiveFolderOpenedTab {
    let urlString: String
    let windowState: BrowserWindowState
    let preferredSpaceId: UUID?
}
