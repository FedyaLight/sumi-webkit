import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class WebExtensionRuntimeSourceCacheTests: XCTestCase {
    func testExactNormalizedKeyReusesAtomicEntry() async throws {
        let webExtension = try await makeWebExtension(named: "reuse")
        var factoryCallCount = 0
        let fixture = makeFixture { _, _, _ in
            factoryCallCount += 1
            return .init(
                webExtension: webExtension,
                loadSource: .copiedPackage
            )
        }
        let extensionID = "cache-reuse"
        let firstClaim = fixture.claim(
            extensionID: extensionID,
            profileID: UUID()
        )
        let first = try await fixture.cache.resolve(
            extensionID: extensionID,
            sourceKind: .directory,
            sourceBundlePath: "/tmp/source/../source",
            packageRoot: URL(fileURLWithPath: "/tmp/package/../package"),
            claim: firstClaim,
            mutationLease: nil
        )
        let secondClaim = fixture.claim(
            extensionID: extensionID,
            profileID: UUID()
        )
        let second = try await fixture.cache.resolve(
            extensionID: extensionID,
            sourceKind: .directory,
            sourceBundlePath: "/tmp/source",
            packageRoot: URL(fileURLWithPath: "/tmp/package"),
            claim: secondClaim,
            mutationLease: nil
        )

        XCTAssertEqual(factoryCallCount, 1)
        XCTAssertIdentical(first.webExtension, webExtension)
        XCTAssertIdentical(second.webExtension, webExtension)
        let entry = try XCTUnwrap(fixture.cache.entry(for: extensionID))
        XCTAssertIdentical(entry.resolution.webExtension, webExtension)
        XCTAssertEqual(entry.key.sourceBundlePath, "/tmp/source")
        XCTAssertEqual(entry.key.packageRootPath, "/tmp/package")
    }

    func testUnavailableSafariBundleUsesCopiedPackageSource() async throws {
        let webExtension = try await makeWebExtension(named: "fallback")
        var receivedSourceKind: WebExtensionSourceKind?
        let fixture = makeFixture { sourceKind, _, _ in
            receivedSourceKind = sourceKind
            return .init(
                webExtension: webExtension,
                loadSource: .copiedPackage
            )
        }
        let extensionID = "safari-fallback"
        let resolution = try await fixture.cache.resolve(
            extensionID: extensionID,
            sourceKind: .safariAppExtension,
            sourceBundlePath: "/tmp/missing-\(UUID().uuidString).appex",
            packageRoot: URL(fileURLWithPath: "/tmp/copied-package"),
            claim: fixture.claim(
                extensionID: extensionID,
                profileID: UUID()
            ),
            mutationLease: nil
        )

        XCTAssertEqual(receivedSourceKind, .directory)
        XCTAssertEqual(resolution.loadSource, .copiedPackage)
        XCTAssertEqual(
            fixture.cache.entry(for: extensionID)?.key.sourceKind,
            .directory
        )
    }

    func testRevokedClaimCannotPublishSuspendedCandidate() async throws {
        let webExtension = try await makeWebExtension(named: "revoked")
        let factory = ControlledSourceFactory(
            webExtensions: [webExtension]
        )
        let fixture = makeFixture(factory: factory)
        let extensionID = "revoked-source"
        let claim = fixture.claim(
            extensionID: extensionID,
            profileID: UUID()
        )

        async let result = capturedSourceResult {
            try await fixture.cache.resolve(
                extensionID: extensionID,
                sourceKind: .directory,
                sourceBundlePath: "/tmp/revoked-source",
                packageRoot: URL(fileURLWithPath: "/tmp/revoked-package"),
                claim: claim,
                mutationLease: nil
            )
        }
        await factory.waitUntilStarted(1)
        fixture.loadRegistry.invalidate(claim.key)
        factory.release(call: 1)

        guard case .failure(let error) = await result else {
            return XCTFail("A revoked source publication must fail")
        }
        XCTAssertTrue(error is CancellationError)
        XCTAssertNil(fixture.cache.entry(for: extensionID))
    }

    func testConcurrentSameKeyCoalescesOneSourceCreation() async throws {
        let webExtension = try await makeWebExtension(named: "coalesced")
        let factory = ControlledSourceFactory(webExtensions: [webExtension])
        let fixture = makeFixture(factory: factory)
        let extensionID = "same-key"

        async let first = fixture.cache.resolve(
            extensionID: extensionID,
            sourceKind: .directory,
            sourceBundlePath: "/tmp/shared-source",
            packageRoot: URL(fileURLWithPath: "/tmp/shared-package"),
            claim: fixture.claim(
                extensionID: extensionID,
                profileID: UUID()
            ),
            mutationLease: nil
        )
        await factory.waitUntilStarted(1)
        async let second = fixture.cache.resolve(
            extensionID: extensionID,
            sourceKind: .directory,
            sourceBundlePath: "/tmp/shared-source",
            packageRoot: URL(fileURLWithPath: "/tmp/shared-package"),
            claim: fixture.claim(
                extensionID: extensionID,
                profileID: UUID()
            ),
            mutationLease: nil
        )
        await Task.yield()

        XCTAssertEqual(factory.callCount, 1)
        factory.release(call: 1)

        let firstResolution = try await first
        let secondResolution = try await second
        XCTAssertIdentical(firstResolution.webExtension, webExtension)
        XCTAssertIdentical(secondResolution.webExtension, webExtension)
        XCTAssertEqual(factory.callCount, 1)
    }

    func testCancellingSoleWaiterPromptlyReleasesPendingPublication()
        async throws {
        let webExtension = try await makeWebExtension(named: "cancelled")
        let factory = CancellationAwareSourceFactory(
            webExtension: webExtension
        )
        let fixture = makeFixture { sourceKind, sourceBundlePath, packageRoot in
            try await factory.makeSource(
                sourceKind: sourceKind,
                sourceBundlePath: sourceBundlePath,
                packageRoot: packageRoot
            )
        }
        let extensionID = "cancelled-source"
        let task = Task { @MainActor in
            try await fixture.cache.resolve(
                extensionID: extensionID,
                sourceKind: .directory,
                sourceBundlePath: "/tmp/cancelled-source",
                packageRoot: URL(fileURLWithPath: "/tmp/cancelled-package"),
                claim: fixture.claim(
                    extensionID: extensionID,
                    profileID: UUID()
                ),
                mutationLease: nil
            )
        }
        await factory.waitUntilStarted()

        task.cancel()
        await factory.waitUntilCancellationObserved()

        do {
            _ = try await task.value
            XCTFail("A cancelled source waiter must fail promptly")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertFalse(fixture.cache.extensionIDs.contains(extensionID))
        XCTAssertNil(fixture.cache.entry(for: extensionID))
    }

    func testCancellingOneSameKeyWaiterPreservesSharedCreation()
        async throws {
        let webExtension = try await makeWebExtension(named: "shared")
        let factory = ControlledSourceFactory(webExtensions: [webExtension])
        let fixture = makeFixture(factory: factory)
        let extensionID = "shared-with-cancellation"
        let sourcePath = "/tmp/shared-with-cancellation"
        let packageRoot = URL(fileURLWithPath: "/tmp/shared-cancellation-package")
        let first = Task { @MainActor in
            try await fixture.cache.resolve(
                extensionID: extensionID,
                sourceKind: .directory,
                sourceBundlePath: sourcePath,
                packageRoot: packageRoot,
                claim: fixture.claim(
                    extensionID: extensionID,
                    profileID: UUID()
                ),
                mutationLease: nil
            )
        }
        await factory.waitUntilStarted(1)
        let second = Task { @MainActor in
            try await fixture.cache.resolve(
                extensionID: extensionID,
                sourceKind: .directory,
                sourceBundlePath: sourcePath,
                packageRoot: packageRoot,
                claim: fixture.claim(
                    extensionID: extensionID,
                    profileID: UUID()
                ),
                mutationLease: nil
            )
        }
        await Task.yield()

        first.cancel()
        do {
            _ = try await first.value
            XCTFail("The cancelled waiter must not receive the shared result")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(fixture.cache.extensionIDs.contains(extensionID))
        XCTAssertEqual(factory.callCount, 1)

        factory.release(call: 1)
        let secondResolution = try await second.value
        XCTAssertIdentical(secondResolution.webExtension, webExtension)
        XCTAssertEqual(factory.callCount, 1)
    }

    func testRemoveWhileSuspendedCannotAdoptNewSameKeyPublication()
        async throws {
        let staleWebExtension = try await makeWebExtension(named: "stale")
        let replacementWebExtension = try await makeWebExtension(
            named: "replacement"
        )
        let factory = ControlledSourceFactory(
            webExtensions: [staleWebExtension, replacementWebExtension]
        )
        let fixture = makeFixture(factory: factory)
        let extensionID = "removed-source"
        let sourcePath = "/tmp/removed-source"
        let packageRoot = URL(fileURLWithPath: "/tmp/removed-package")

        async let staleResult = capturedSourceResult {
            try await fixture.cache.resolve(
                extensionID: extensionID,
                sourceKind: .directory,
                sourceBundlePath: sourcePath,
                packageRoot: packageRoot,
                claim: fixture.claim(
                    extensionID: extensionID,
                    profileID: UUID()
                ),
                mutationLease: nil
            )
        }
        await factory.waitUntilStarted(1)
        fixture.cache.remove(extensionID: extensionID)

        async let replacement = fixture.cache.resolve(
            extensionID: extensionID,
            sourceKind: .directory,
            sourceBundlePath: sourcePath,
            packageRoot: packageRoot,
            claim: fixture.claim(
                extensionID: extensionID,
                profileID: UUID()
            ),
            mutationLease: nil
        )
        await factory.waitUntilStarted(2)
        factory.release(call: 2)
        let replacementResolution = try await replacement
        factory.release(call: 1)

        guard case .failure(let staleError) = await staleResult else {
            return XCTFail("The removed publication must stay revoked")
        }
        XCTAssertTrue(staleError is CancellationError)
        XCTAssertIdentical(
            replacementResolution.webExtension,
            replacementWebExtension
        )
        XCTAssertIdentical(
            fixture.cache.entry(for: extensionID)?.resolution.webExtension,
            replacementWebExtension
        )
    }

    func testDifferentKeyInvalidatesOlderSuspendedPublication()
        async throws {
        let firstWebExtension = try await makeWebExtension(named: "old")
        let secondWebExtension = try await makeWebExtension(named: "new")
        let factory = ControlledSourceFactory(
            webExtensions: [firstWebExtension, secondWebExtension]
        )
        let fixture = makeFixture(factory: factory)
        let extensionID = "source-replacement"

        async let firstResult = capturedSourceResult {
            try await fixture.cache.resolve(
                extensionID: extensionID,
                sourceKind: .directory,
                sourceBundlePath: "/tmp/old-source",
                packageRoot: URL(fileURLWithPath: "/tmp/old-package"),
                claim: fixture.claim(
                    extensionID: extensionID,
                    profileID: UUID()
                ),
                mutationLease: nil
            )
        }
        await factory.waitUntilStarted(1)
        async let secondResult = capturedSourceResult {
            try await fixture.cache.resolve(
                extensionID: extensionID,
                sourceKind: .directory,
                sourceBundlePath: "/tmp/new-source",
                packageRoot: URL(fileURLWithPath: "/tmp/new-package"),
                claim: fixture.claim(
                    extensionID: extensionID,
                    profileID: UUID()
                ),
                mutationLease: nil
            )
        }
        await factory.waitUntilStarted(2)
        factory.release(call: 2)
        await waitUntilEntryPublished(
            in: fixture.cache,
            extensionID: extensionID
        )
        factory.release(call: 1)

        guard case .failure(let firstError) = await firstResult else {
            return XCTFail("The superseded source must not be returned")
        }
        guard case .success(let second) = await secondResult else {
            return XCTFail("The replacement source must succeed")
        }
        XCTAssertTrue(firstError is CancellationError)
        XCTAssertIdentical(second.webExtension, secondWebExtension)
        let entry = try XCTUnwrap(fixture.cache.entry(for: extensionID))
        XCTAssertEqual(entry.key.sourceBundlePath, "/tmp/new-source")
        XCTAssertIdentical(
            entry.resolution.webExtension,
            secondWebExtension
        )
    }

    private func waitUntilEntryPublished(
        in cache: WebExtensionRuntimeSourceCache,
        extensionID: String
    ) async {
        while cache.entry(for: extensionID) == nil {
            await Task.yield()
        }
    }

    private func makeFixture(
        factory: ControlledSourceFactory
    ) -> SourceCacheFixture {
        makeFixture { sourceKind, sourceBundlePath, packageRoot in
            try await factory.makeSource(
                sourceKind: sourceKind,
                sourceBundlePath: sourceBundlePath,
                packageRoot: packageRoot
            )
        }
    }

    private func makeFixture(
        factory: @escaping WebExtensionRuntimeSourceCache.SourceFactory
    ) -> SourceCacheFixture {
        SourceCacheFixture(factory: factory)
    }

    private func makeWebExtension(named name: String) async throws
        -> WKWebExtension {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
        }
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 3,
                "name": name,
                "version": "1.0",
            ],
            options: [.sortedKeys]
        ).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        return try await WKWebExtension(resourceBaseURL: directory)
    }
}

@MainActor
private func capturedSourceResult<T>(
    _ operation: @MainActor () async throws -> T
) async -> Result<T, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}

@available(macOS 15.5, *)
@MainActor
private final class SourceCacheFixture {
    let loadRegistry = ExtensionContextLoadRegistry()
    let cache: WebExtensionRuntimeSourceCache

    init(factory: @escaping WebExtensionRuntimeSourceCache.SourceFactory) {
        let mutationRegistry = ExtensionRuntimeMutationRegistry()
        let admission = ExtensionContextLoadAdmission(
            mutationRegistry: mutationRegistry,
            loadRegistry: loadRegistry
        )
        cache = WebExtensionRuntimeSourceCache(
            admission: admission,
            makeSource: factory
        )
    }

    func claim(
        extensionID: String,
        profileID: UUID
    ) -> ExtensionContextLoadClaim {
        loadRegistry.begin(
            for: .init(
                profileId: profileID,
                extensionId: extensionID
            )
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ControlledSourceFactory {
    private let webExtensions: [WKWebExtension]
    private var releaseContinuations:
        [Int: CheckedContinuation<Void, Never>] = [:]
    private var startWaiters:
        [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var callCount = 0

    init(webExtensions: [WKWebExtension]) {
        self.webExtensions = webExtensions
    }

    func waitUntilStarted(_ expectedCallCount: Int) async {
        guard callCount < expectedCallCount else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((expectedCallCount, continuation))
        }
    }

    func release(call: Int) {
        releaseContinuations.removeValue(forKey: call)?.resume()
    }

    func makeSource(
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath _: String,
        packageRoot _: URL
    ) async throws -> WebExtensionRuntimeSourceCache.Resolution {
        callCount += 1
        let call = callCount
        resumeSatisfiedStartWaiters()
        await withCheckedContinuation { continuation in
            releaseContinuations[call] = continuation
        }
        return .init(
            webExtension: webExtensions[call - 1],
            loadSource: sourceKind == .safariAppExtension
                ? .originalAppexBundle
                : .copiedPackage
        )
    }

    private func resumeSatisfiedStartWaiters() {
        let satisfied = startWaiters.filter { $0.count <= callCount }
        startWaiters.removeAll { $0.count <= callCount }
        for waiter in satisfied {
            waiter.continuation.resume()
        }
    }
}

@available(macOS 15.5, *)
@MainActor
private final class CancellationAwareSourceFactory {
    private let webExtension: WKWebExtension
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var cancellationContinuation: CheckedContinuation<Void, Never>?
    private var suspendedContinuation:
        CheckedContinuation<Void, Error>?
    private var didStart = false
    private var didObserveCancellation = false

    init(webExtension: WKWebExtension) {
        self.webExtension = webExtension
    }

    func waitUntilStarted() async {
        guard didStart == false else { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func waitUntilCancellationObserved() async {
        guard didObserveCancellation == false else { return }
        await withCheckedContinuation { cancellationContinuation = $0 }
    }

    func makeSource(
        sourceKind _: WebExtensionSourceKind,
        sourceBundlePath _: String,
        packageRoot _: URL
    ) async throws -> WebExtensionRuntimeSourceCache.Resolution {
        didStart = true
        startContinuation?.resume()
        startContinuation = nil
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                suspendedContinuation = $0
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.didObserveCancellation = true
                self.cancellationContinuation?.resume()
                self.cancellationContinuation = nil
                self.suspendedContinuation?.resume(
                    throwing: CancellationError()
                )
                self.suspendedContinuation = nil
            }
        }
        return .init(
            webExtension: webExtension,
            loadSource: .copiedPackage
        )
    }
}
