import XCTest

@testable import Sumi

@MainActor
final class SumiLiveFolderManagerTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

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
        XCTAssertEqual(source.profileId, spy.profileId)
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

    private func makeManager(runtime: SumiLiveFolderRuntime) -> SumiLiveFolderManager {
        let manager = SumiLiveFolderManager(
            store: SumiLiveFolderStore(fileURL: temporaryStoreURL()),
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

    private func temporaryStoreURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiLiveFolderManagerTests-\(UUID().uuidString)",
                isDirectory: true
            )
        temporaryDirectories.append(directory)
        return directory.appendingPathComponent("live-folders.json", isDirectory: false)
    }
}

private final class LiveFolderURLProtocolStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.test")!,
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

    override func stopLoading() {}
}

@MainActor
private final class LiveFolderRuntimeSpy {
    let spaceId = UUID()
    let profileId = UUID()
    let folderId = UUID()
    var createdFolders: [(spaceId: UUID, name: String)] = []
    var iconUpdates: [(folderId: UUID, icon: String)] = []
    var openedTabs: [(urlString: String, windowState: BrowserWindowState, preferredSpaceId: UUID?)] = []

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
            renameFolder: { _, _ in },
            openNewTab: { [weak self] urlString, windowState, preferredSpaceId in
                self?.openedTabs.append(
                    (
                        urlString: urlString,
                        windowState: windowState,
                        preferredSpaceId: preferredSpaceId
                    )
                )
            },
            profile: { _, _ in nil },
            folderIds: { nil }
        )
    }
}
