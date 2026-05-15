import Foundation
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiAdblockUpdatePipelineTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testDownloaderPersistsConditionalRequestHeadersFromMetadata() async throws {
        let requestRecorder = RequestRecorder()
        let downloader = AdblockFilterListDownloader { request in
            await requestRecorder.record(request)
            return (
                Data("||ads.example^".utf8),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["ETag": "\"next\"", "Last-Modified": "Tue, 14 May 2024 12:00:00 GMT"]
                )!
            )
        }

        _ = try await downloader.download(
            descriptor: Self.descriptor("easylist"),
            previousMetadata: AdblockFilterListHTTPMetadata(
                eTag: "\"old\"",
                lastModified: "Mon, 13 May 2024 12:00:00 GMT"
            )
        )

        let observedRequest = await requestRecorder.recordedRequest()
        XCTAssertEqual(observedRequest?.value(forHTTPHeaderField: "If-None-Match"), "\"old\"")
        XCTAssertEqual(observedRequest?.value(forHTTPHeaderField: "If-Modified-Since"), "Mon, 13 May 2024 12:00:00 GMT")
    }

    func testCoordinatorDownloadsOnlySelectedListsAndWritesManifest() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let downloader = FakeAdblockDownloader(results: [
            "easylist": .downloaded(Data("||ads.example^".utf8), Self.response(for: "easylist", eTag: "\"one\"")),
        ])
        let compiler = FakeAdblockCompiler()
        let publisher = FakeAdblockPublisher()
        let coordinator = Self.coordinator(
            registry: AdblockFilterListRegistry(descriptors: [
                Self.descriptor("easylist", defaultEnabled: true),
                Self.descriptor("regional-de", defaultEnabled: false),
            ]),
            selection: SumiAdblockFilterListSelection(identifiers: ["easylist"]),
            downloader: downloader,
            manifestStore: manifestStore,
            compiler: compiler,
            publisher: publisher
        )

        let optionalManifest = try await coordinator.updateIfEnabled(reason: "manual")
        let manifest = try XCTUnwrap(optionalManifest)
        let requestedIdentifiers = await downloader.allRequestedIdentifiers()
        let compileCount = await compiler.currentCompileCount()
        let activeGenerationId = try await manifestStore.activeManifest()?.activeGenerationId

        XCTAssertEqual(requestedIdentifiers, ["easylist"])
        XCTAssertEqual(compileCount, 1)
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.selectedFilterLists.map(\.id), ["easylist"])
        XCTAssertTrue(manifest.webKitRuleListIdentifiers.allSatisfy(AdblockUpdateCoordinator.isAdblockGeneratedWebKitIdentifier))
        XCTAssertEqual(activeGenerationId, manifest.activeGenerationId)
        XCTAssertEqual(publisher.publishedManifests.count, 1)
    }

    func testNotModifiedReusesPreviousRawContent() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let firstDownloader = FakeAdblockDownloader(results: [
            "easylist": .downloaded(Data("||first.example^".utf8), Self.response(for: "easylist", eTag: "\"one\"")),
        ])
        let compiler = FakeAdblockCompiler()
        let publisher = FakeAdblockPublisher()
        _ = try await Self.coordinator(
            downloader: firstDownloader,
            manifestStore: manifestStore,
            compiler: compiler,
            publisher: publisher
        ).updateIfEnabled(reason: "manual")

        let secondDownloader = FakeAdblockDownloader(results: [
            "easylist": .notModified(Self.response(for: "easylist", statusCode: 304)),
        ])
        _ = try await Self.coordinator(
            downloader: secondDownloader,
            manifestStore: manifestStore,
            compiler: compiler,
            publisher: publisher
        ).updateIfEnabled(reason: "manual")

        let inputs = await compiler.inputs
        XCTAssertEqual(inputs.count, 2)
        XCTAssertEqual(inputs.last?.filterTexts.first, "||first.example^")
    }

    func testDisabledCoordinatorIsInert() async throws {
        let downloader = FakeAdblockDownloader(results: [:])
        let compiler = FakeAdblockCompiler()
        let publisher = FakeAdblockPublisher()
        let coordinator = Self.coordinator(
            isEnabled: false,
            downloader: downloader,
            manifestStore: AdblockUpdateManifestStore(rootDirectory: temporaryDirectory()),
            compiler: compiler,
            publisher: publisher
        )

        let manifest = try await coordinator.updateIfEnabled(reason: "manual")

        XCTAssertNil(manifest)
        let requestedIdentifiers = await downloader.allRequestedIdentifiers()
        let compileCount = await compiler.currentCompileCount()
        XCTAssertTrue(requestedIdentifiers.isEmpty)
        XCTAssertEqual(compileCount, 0)
        XCTAssertTrue(publisher.publishedManifests.isEmpty)
    }

    func testDownloadAndCompileFailuresKeepPreviousManifest() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let publisher = FakeAdblockPublisher()
        let optionalFirstManifest = try await Self.coordinator(
            downloader: FakeAdblockDownloader(results: [
                "easylist": .downloaded(Data("||first.example^".utf8), Self.response(for: "easylist")),
            ]),
            manifestStore: manifestStore,
            compiler: FakeAdblockCompiler(),
            publisher: publisher
        ).updateIfEnabled(reason: "manual")
        let firstManifest = try XCTUnwrap(optionalFirstManifest)

        do {
            _ = try await Self.coordinator(
                downloader: FakeAdblockDownloader(results: [
                    "easylist": .failure(AdblockUpdateDiagnostics(summary: "offline")),
                ]),
                manifestStore: manifestStore,
                compiler: FakeAdblockCompiler(),
                publisher: publisher
            ).updateIfEnabled(reason: "manual")
            XCTFail("Expected download failure")
        } catch {}

        let activeAfterDownloadFailure = try await manifestStore.activeManifest()?.activeGenerationId
        XCTAssertEqual(activeAfterDownloadFailure, firstManifest.activeGenerationId)

        do {
            _ = try await Self.coordinator(
                downloader: FakeAdblockDownloader(results: [
                    "easylist": .downloaded(Data("||second.example^".utf8), Self.response(for: "easylist")),
                ]),
                manifestStore: manifestStore,
                compiler: FakeAdblockCompiler(error: AdblockUpdateDiagnostics(summary: "compiler failed")),
                publisher: publisher
            ).updateIfEnabled(reason: "manual")
            XCTFail("Expected compile failure")
        } catch {}

        let activeAfterCompileFailure = try await manifestStore.activeManifest()?.activeGenerationId
        XCTAssertEqual(activeAfterCompileFailure, firstManifest.activeGenerationId)
    }

    func testCleanupPreservesActiveAndPreviousAndDeletesOlderGenerations() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let active = Self.manifest(
            generationId: "20240515T000002Z-activehash",
            previousGenerationId: "20240515T000001Z-prevhash",
            listIds: ["easylist"],
            identifiers: ["sumi.adblock.network.activehash", "sumi.adblock.nativeCSS.activehash"]
        )
        let previous = Self.manifest(
            generationId: "20240515T000001Z-prevhash",
            previousGenerationId: "20240515T000000Z-oldhash",
            listIds: ["regional-de"],
            identifiers: ["sumi.adblock.network.prevhash", "sumi.adblock.nativeCSS.prevhash"]
        )
        let old = Self.manifest(
            generationId: "20240515T000000Z-oldhash",
            previousGenerationId: nil,
            listIds: ["obsolete"],
            identifiers: ["sumi.adblock.network.oldhash", "sumi.adblock.nativeCSS.oldhash"]
        )
        try await archive(old, in: manifestStore)
        try await archive(previous, in: manifestStore)
        try await archive(active, in: manifestStore)
        try await manifestStore.replaceActiveManifest(active)
        try writeRawList("easylist", root: root)
        try writeRawList("regional-de", root: root)
        try writeRawList("obsolete", root: root)
        try createStagingDirectory(root: root, name: "interrupted")
        let ruleStore = FakeContentRuleListStore(identifiers: [
            "sumi.adblock.network.activehash",
            "sumi.adblock.nativeCSS.activehash",
            "sumi.adblock.network.prevhash",
            "sumi.adblock.nativeCSS.prevhash",
            "sumi.adblock.network.oldhash",
            "sumi.trackingProtection.tds",
            "third.party.rule.list",
        ])
        let cleaner = AdblockGenerationGarbageCollector(
            manifestStore: manifestStore,
            contentRuleListStore: ruleStore
        )

        let report = await cleaner.cleanupAfterSuccessfulUpdate()

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Generated/20240515T000002Z-activehash").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Generated/20240515T000001Z-prevhash").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Generated/20240515T000000Z-oldhash").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("RawLists/easylist.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("RawLists/regional-de.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("RawLists/obsolete.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Staging/interrupted").path))
        let removedIdentifiers = ruleStore.removedIdentifiers()
        let remainingIdentifiers = ruleStore.identifiers()
        XCTAssertEqual(removedIdentifiers, ["sumi.adblock.network.oldhash"])
        XCTAssertTrue(remainingIdentifiers.contains("sumi.trackingProtection.tds"))
        XCTAssertTrue(remainingIdentifiers.contains("third.party.rule.list"))
        XCTAssertTrue(report.diagnostics.isEmpty)
    }

    func testCleanupToleratesMissingFilesAndReportsWebKitRemoveFailures() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let active = Self.manifest(
            generationId: "activehash",
            previousGenerationId: nil,
            listIds: ["easylist"],
            identifiers: ["sumi.adblock.network.activehash"]
        )
        try await archive(active, in: manifestStore)
        try await manifestStore.replaceActiveManifest(active)
        let ruleStore = FakeContentRuleListStore(
            identifiers: ["sumi.adblock.network.oldhash"],
            removeFailures: ["sumi.adblock.network.oldhash"]
        )
        let cleaner = AdblockGenerationGarbageCollector(
            manifestStore: manifestStore,
            contentRuleListStore: ruleStore
        )

        let report = await cleaner.cleanupAfterSuccessfulUpdate()
        let activeAfterCleanup = try await manifestStore.activeManifest()

        XCTAssertEqual(activeAfterCleanup?.activeGenerationId, active.activeGenerationId)
        XCTAssertTrue(report.diagnostics.contains { $0.contains("Failed to remove WebKit rule list") })
    }

    func testCleanupRunsOnlyAfterSuccessfulManifestSwitch() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let ruleStore = FakeContentRuleListStore(identifiers: ["sumi.adblock.network.oldhash"])
        let cleaner = AdblockGenerationGarbageCollector(
            manifestStore: manifestStore,
            contentRuleListStore: ruleStore
        )
        let publisher = FakeAdblockPublisher()
        _ = try await Self.coordinator(
            downloader: FakeAdblockDownloader(results: [
                "easylist": .downloaded(Data("||first.example^".utf8), Self.response(for: "easylist")),
            ]),
            manifestStore: manifestStore,
            compiler: FakeAdblockCompiler(),
            publisher: publisher,
            garbageCollector: cleaner
        ).updateIfEnabled(reason: "manual")

        XCTAssertEqual(ruleStore.removedIdentifiers(), ["sumi.adblock.network.oldhash"])

        let failingRuleStore = FakeContentRuleListStore(identifiers: ["sumi.adblock.network.afterfailure"])
        let failingCleaner = AdblockGenerationGarbageCollector(
            manifestStore: manifestStore,
            contentRuleListStore: failingRuleStore
        )
        do {
            _ = try await Self.coordinator(
                downloader: FakeAdblockDownloader(results: [
                    "easylist": .failure(AdblockUpdateDiagnostics(summary: "offline")),
                ]),
                manifestStore: manifestStore,
                compiler: FakeAdblockCompiler(),
                publisher: publisher,
                garbageCollector: failingCleaner
            ).updateIfEnabled(reason: "manual")
            XCTFail("Expected update failure")
        } catch {}

        XCTAssertTrue(failingRuleStore.removedIdentifiers().isEmpty)
    }

    func testRollbackSwitchesActiveGenerationBackToPreviousWithoutDownloadOrCompile() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let previous = Self.manifest(
            generationId: "prevhash",
            previousGenerationId: nil,
            listIds: ["easylist"],
            identifiers: ["sumi.adblock.network.prevhash"]
        )
        let active = Self.manifest(
            generationId: "activehash",
            previousGenerationId: "prevhash",
            listIds: ["easylist"],
            identifiers: ["sumi.adblock.network.activehash"]
        )
        try await archive(previous, in: manifestStore)
        try await archive(active, in: manifestStore)
        try await manifestStore.replaceActiveManifest(active)
        let ruleStore = FakeContentRuleListStore(identifiers: ["sumi.adblock.network.prevhash"])
        let downloader = FakeAdblockDownloader(results: [:])
        let compiler = FakeAdblockCompiler()
        let publisher = FakeAdblockPublisher()
        let coordinator = Self.coordinator(
            downloader: downloader,
            manifestStore: manifestStore,
            compiler: compiler,
            publisher: publisher,
            contentRuleListStore: ruleStore
        )

        let report = await coordinator.rollbackIfActiveGenerationFailsSmokeCheck()

        XCTAssertTrue(report.rolledBack)
        let activeAfterRollback = try await manifestStore.activeManifest()?.activeGenerationId
        let requestedIdentifiers = await downloader.allRequestedIdentifiers()
        let compileCount = await compiler.currentCompileCount()
        XCTAssertEqual(activeAfterRollback, "prevhash")
        XCTAssertEqual(publisher.publishedManifests.map(\.activeGenerationId), ["prevhash"])
        XCTAssertTrue(requestedIdentifiers.isEmpty)
        XCTAssertEqual(compileCount, 0)
    }

    private static func coordinator(
        registry: AdblockFilterListRegistry = AdblockFilterListRegistry(descriptors: [descriptor("easylist", defaultEnabled: true)]),
        selection: SumiAdblockFilterListSelection = SumiAdblockFilterListSelection(identifiers: ["easylist"]),
        isEnabled: Bool = true,
        downloader: FakeAdblockDownloader,
        manifestStore: AdblockUpdateManifestStore,
        compiler: FakeAdblockCompiler,
        publisher: FakeAdblockPublisher,
        contentRuleListStore: (any SumiContentRuleListCompiling)? = nil,
        garbageCollector: AdblockGenerationGarbageCollector? = nil
    ) -> AdblockUpdateCoordinator {
        AdblockUpdateCoordinator(
            registry: registry,
            selection: { selection },
            isAdblockEnabled: { isEnabled },
            downloader: downloader,
            manifestStore: manifestStore,
            filterCompiler: compiler,
            publisher: publisher,
            contentRuleListStore: contentRuleListStore,
            garbageCollector: garbageCollector,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    private static func manifest(
        generationId: String,
        previousGenerationId: String?,
        listIds: [String],
        identifiers: [String]
    ) -> AdblockCompiledGenerationManifest {
        AdblockCompiledGenerationManifest(
            schemaVersion: 1,
            activeGenerationId: generationId,
            createdDate: Date(timeIntervalSince1970: 1_700_000_000),
            selectedFilterLists: listIds.map {
                AdblockCompiledGenerationManifest.SelectedFilterList(
                    id: $0,
                    displayName: $0,
                    contentHash: "\($0)-hash"
                )
            },
            webKitRuleListIdentifiers: identifiers,
            groupedOutputs: identifiers.map {
                AdblockCompiledGenerationManifest.Group(
                    kind: $0.contains("nativeCSS") ? .nativeCosmeticCSS : .network,
                    webKitIdentifier: $0,
                    contentHash: "\($0)-hash",
                    convertedRuleCount: 1
                )
            },
            compilerDiagnosticsSummary: "unsupported=0; ignored=0",
            lastSuccessfulUpdateDate: Date(timeIntervalSince1970: 1_700_000_000),
            previousGenerationId: previousGenerationId
        )
    }

    private func archive(
        _ manifest: AdblockCompiledGenerationManifest,
        in manifestStore: AdblockUpdateManifestStore
    ) async throws {
        try await manifestStore.commit(
            manifest: manifest,
            httpMetadata: [:],
            stagedRawListURLs: [:]
        )
    }

    private func writeRawList(_ id: String, root: URL) throws {
        let directory = root.appendingPathComponent("RawLists", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("||\(id).example^".utf8).write(to: directory.appendingPathComponent("\(id).txt"))
    }

    private func createStagingDirectory(root: URL, name: String) throws {
        let directory = root.appendingPathComponent("Staging/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: directory.appendingPathComponent("partial.txt"))
    }

    private static func descriptor(_ id: String, defaultEnabled: Bool = false) -> AdblockFilterListDescriptor {
        AdblockFilterListDescriptor(
            id: id,
            displayName: id,
            category: id.contains("regional") ? .regional : .baseAds,
            remoteURL: URL(string: "https://filters.example/\(id).txt")!,
            homepageURL: URL(string: "https://filters.example/"),
            defaultEnabled: defaultEnabled,
            localeTags: [],
            licenseNoticeHint: "test",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        )
    }

    private static func response(
        for id: String,
        statusCode: Int = 200,
        eTag: String? = nil
    ) -> HTTPURLResponse {
        var headers = [String: String]()
        if let eTag {
            headers["ETag"] = eTag
        }
        return HTTPURLResponse(
            url: URL(string: "https://filters.example/\(id).txt")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiAdblockUpdatePipelineTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }
}

private actor FakeAdblockDownloader: AdblockFilterListDownloading {
    enum Result {
        case downloaded(Data, HTTPURLResponse)
        case notModified(HTTPURLResponse)
        case failure(Error)
    }

    private(set) var requestedIdentifiers = [String]()
    private let results: [String: Result]

    init(results: [String: Result]) {
        self.results = results
    }

    func allRequestedIdentifiers() -> [String] {
        requestedIdentifiers
    }

    func download(
        descriptor: AdblockFilterListDescriptor,
        previousMetadata: AdblockFilterListHTTPMetadata?
    ) async throws -> AdblockDownloadOutcome {
        requestedIdentifiers.append(descriptor.id)
        switch results[descriptor.id] {
        case .downloaded(let data, let response):
            return .downloaded(data, response)
        case .notModified(let response):
            return .notModified(response)
        case .failure(let error):
            throw error
        case nil:
            throw AdblockUpdateDiagnostics(summary: "unexpected list")
        }
    }
}

private actor FakeAdblockCompiler: AdblockFilterCompiling {
    private(set) var inputs = [AdblockCompilationInput]()
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    var compileCount: Int {
        inputs.count
    }

    func currentCompileCount() -> Int {
        inputs.count
    }

    func compile(_ input: AdblockCompilationInput) async throws -> AdblockCompilationOutput {
        if let error {
            throw error
        }
        inputs.append(input)
        return AdblockCompilationOutput(
            sourceIdentifier: input.sourceIdentifier,
            groups: [
                AdblockCompiledRuleGroup(
                    kind: .network,
                    name: "\(input.sourceIdentifier).network",
                    encodedContentRuleList: "[]",
                    convertedRuleCount: 1,
                    contentHash: "network-hash"
                ),
                AdblockCompiledRuleGroup(
                    kind: .nativeCosmeticCSS,
                    name: "\(input.sourceIdentifier).native-css",
                    encodedContentRuleList: "[]",
                    convertedRuleCount: 1,
                    contentHash: "css-hash"
                ),
            ],
            diagnostics: AdblockCompilationDiagnostics(),
            inputRuleCount: input.filterTexts.count,
            convertedNetworkRuleCount: 1,
            convertedNativeCosmeticRuleCount: 1,
            unsupportedOrIgnoredRuleCount: 0,
            contentHash: "compiled-hash"
        )
    }
}

private actor RequestRecorder {
    private(set) var request: URLRequest?

    func record(_ request: URLRequest) {
        self.request = request
    }

    func recordedRequest() -> URLRequest? {
        request
    }
}

@MainActor
private final class FakeAdblockPublisher: AdblockRuleListPublishing {
    private(set) var publishedManifests = [AdblockCompiledGenerationManifest]()

    func publish(
        manifest: AdblockCompiledGenerationManifest,
        definitions: [SumiContentRuleListDefinition]
    ) async throws {
        publishedManifests.append(manifest)
    }
}

@MainActor
private final class FakeContentRuleListStore: SumiContentRuleListCompiling {
    private var storedIdentifiers: Set<String>
    private let removeFailures: Set<String>
    private var removed = [String]()

    init(
        identifiers: Set<String>,
        removeFailures: Set<String> = []
    ) {
        storedIdentifiers = identifiers
        self.removeFailures = removeFailures
    }

    func identifiers() -> Set<String> {
        storedIdentifiers
    }

    func removedIdentifiers() -> [String] {
        removed
    }

    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList? {
        nil
    }

    func canLookUpContentRuleList(forIdentifier identifier: String) async -> Bool {
        storedIdentifiers.contains(identifier)
    }

    func compileContentRuleList(
        forIdentifier identifier: String,
        encodedContentRuleList: String
    ) async throws -> WKContentRuleList {
        throw AdblockUpdateDiagnostics(summary: "FakeContentRuleListStore does not compile")
    }

    func availableContentRuleListIdentifiers() async -> [String] {
        storedIdentifiers.sorted()
    }

    func removeContentRuleList(forIdentifier identifier: String) async throws {
        if removeFailures.contains(identifier) {
            throw AdblockUpdateDiagnostics(summary: "remove failed")
        }
        storedIdentifiers.remove(identifier)
        removed.append(identifier)
    }
}
