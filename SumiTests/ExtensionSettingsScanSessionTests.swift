@testable import Sumi
import Observation
import XCTest

@available(macOS 15.5, *)
@MainActor
final class ExtensionSettingsScanSessionTests: XCTestCase {
    func testInitialStateIsInertAndStartsNoScan() {
        let scanner = ControlledExtensionSettingsScanner()
        let capabilities = ExtensionSettingsCapabilityRecorder()
        _ = makeSession(scanner: scanner, capabilities: capabilities)

        XCTAssertEqual(scanner.callCount, 0)
        XCTAssertEqual(capabilities.synchronizeCallCount, 0)
        XCTAssertEqual(capabilities.loadCallCount, 0)
    }

    func testFirstScanPublishesTypedTerminalSnapshot() async {
        let scanner = ControlledExtensionSettingsScanner()
        let contentBlocker = makeCandidate(
            id: "content-blocker",
            kind: .contentBlocker,
            status: .contentBlockerImportable
        )
        let unsupported = makeCandidate(
            id: "legacy-extension",
            kind: .legacySafariAppExtension,
            status: .unsupportedLegacySafariAppExtension
        )
        let webExtension = makeCandidate(id: "web-extension")
        let blockerRecord = makeContentBlockerRecord(id: contentBlocker.id)
        let capabilities = ExtensionSettingsCapabilityRecorder(
            importResult: .init(
                importedExtensionCount: 1,
                failedMessages: [],
                skippedUnreadableCount: 0
            ),
            contentBlockerRecords: [blockerRecord]
        )
        let session = makeSession(scanner: scanner, capabilities: capabilities)

        session.beginIfNeeded()
        await scanner.waitUntilStarted(1)
        scanner.resolve(
            call: 1,
            with: .init(
                candidates: [webExtension, contentBlocker, unsupported],
                issues: []
            )
        )
        await waitForState(session) {
            if case .completed(let attempt, _) = $0 {
                return attempt.generation == 1
            }
            return false
        }

        guard case .completed(let attempt, let summary) = session.state else {
            return XCTFail("Expected a completed scan")
        }
        XCTAssertEqual(attempt, .init(generation: 1))
        XCTAssertEqual(summary.discoveredCandidateCount, 3)
        XCTAssertEqual(summary.importedExtensionCount, 1)
        XCTAssertFalse(summary.hasIssues)
        XCTAssertEqual(session.snapshot.contentBlockerCandidates, [contentBlocker])
        XCTAssertEqual(session.snapshot.unsupportedCandidates, [unsupported])
        XCTAssertEqual(session.snapshot.contentBlockerRecords, [blockerRecord])
        XCTAssertEqual(capabilities.synchronizedCandidates, [
            webExtension,
            contentBlocker,
            unsupported,
        ])
        XCTAssertEqual(capabilities.loadCallCount, 1)
    }

    func testRefreshSupersedesActiveAttempt() async {
        let scanner = ControlledExtensionSettingsScanner()
        let capabilities = ExtensionSettingsCapabilityRecorder()
        let session = makeSession(scanner: scanner, capabilities: capabilities)

        session.beginIfNeeded()
        await scanner.waitUntilStarted(1)
        session.refresh()
        await scanner.waitUntilCancellationObserved(for: 1)
        await scanner.waitUntilStarted(2)

        XCTAssertEqual(session.state, .scanning(.init(generation: 2)))

        scanner.resolve(call: 1, with: .init(candidates: [], issues: []))
        scanner.resolve(call: 2, with: .init(candidates: [], issues: []))
        await waitForState(session) {
            if case .completed(let attempt, _) = $0 {
                return attempt.generation == 2
            }
            return false
        }

        XCTAssertEqual(capabilities.synchronizeCallCount, 1)
    }

    func testRefreshWhileSynchronizeIsSuspendedRejectsCancelledAttemptBeforeBlockerLoad() async {
        let scanner = ControlledExtensionSettingsScanner()
        let synchronizer = ControlledExtensionSettingsSynchronizer()
        let blockerRecord = makeContentBlockerRecord(id: "current-blocker")
        let capabilities = ExtensionSettingsCapabilityRecorder(
            contentBlockerRecords: [blockerRecord]
        )
        let session = ExtensionSettingsScanSession(
            scan: { await scanner.scan() },
            synchronize: { candidates in
                await synchronizer.synchronize(candidates)
            },
            loadContentBlockers: {
                try capabilities.loadContentBlockers()
            }
        )
        let staleCandidate = makeCandidate(id: "stale-synchronize")
        let currentCandidate = makeCandidate(id: "current-synchronize")

        session.beginIfNeeded()
        await scanner.waitUntilStarted(1)
        scanner.resolve(
            call: 1,
            with: .init(candidates: [staleCandidate], issues: [])
        )
        await synchronizer.waitUntilStarted(1)

        session.refresh()
        await synchronizer.waitUntilCancellationObserved(for: 1)
        await scanner.waitUntilStarted(2)
        scanner.resolve(
            call: 2,
            with: .init(candidates: [currentCandidate], issues: [])
        )
        await synchronizer.waitUntilStarted(2)

        synchronizer.resolve(
            call: 1,
            with: .init(
                importedExtensionCount: 99,
                failedMessages: ["stale"],
                skippedUnreadableCount: 99
            )
        )
        synchronizer.resolve(
            call: 2,
            with: .init(
                importedExtensionCount: 1,
                failedMessages: [],
                skippedUnreadableCount: 0
            )
        )
        await waitForState(session) {
            if case .completed(let attempt, _) = $0 {
                return attempt.generation == 2
            }
            return false
        }

        guard case .completed(let attempt, let summary) = session.state else {
            return XCTFail("Expected the newer synchronize attempt to complete")
        }
        XCTAssertEqual(attempt.generation, 2)
        XCTAssertEqual(summary.importedExtensionCount, 1)
        XCTAssertEqual(summary.failedMessages, [])
        XCTAssertEqual(capabilities.loadCallCount, 1)
        XCTAssertEqual(session.snapshot.contentBlockerRecords, [blockerRecord])
        XCTAssertEqual(synchronizer.candidateIDsByCall, [
            1: [staleCandidate.id],
            2: [currentCandidate.id],
        ])
    }

    func testCancellationPublishesTerminalState() async {
        let scanner = ControlledExtensionSettingsScanner()
        let capabilities = ExtensionSettingsCapabilityRecorder()
        let session = makeSession(scanner: scanner, capabilities: capabilities)

        session.beginIfNeeded()
        await scanner.waitUntilStarted(1)
        session.cancel()
        await scanner.waitUntilCancellationObserved(for: 1)

        XCTAssertEqual(session.state, .cancelled(.init(generation: 1)))
        XCTAssertEqual(capabilities.synchronizeCallCount, 0)
        scanner.resolve(call: 1, with: .init(candidates: [], issues: []))
    }

    func testCancelledSessionBeginsAgainWhenPresented() async {
        let scanner = ControlledExtensionSettingsScanner()
        let capabilities = ExtensionSettingsCapabilityRecorder()
        let session = makeSession(scanner: scanner, capabilities: capabilities)

        session.beginIfNeeded()
        await scanner.waitUntilStarted(1)
        session.cancel()
        await scanner.waitUntilCancellationObserved(for: 1)

        session.beginIfNeeded()
        await scanner.waitUntilStarted(2)
        scanner.resolve(call: 1, with: .init(candidates: [], issues: []))
        scanner.resolve(call: 2, with: .init(candidates: [], issues: []))
        await waitForState(session) {
            if case .completed(let attempt, _) = $0 {
                return attempt.generation == 2
            }
            return false
        }

        XCTAssertEqual(capabilities.synchronizeCallCount, 1)
    }

    func testTeardownCancelsAttemptAndReleasesSession() async {
        let scanner = ControlledExtensionSettingsScanner()
        let capabilities = ExtensionSettingsCapabilityRecorder()
        var session: ExtensionSettingsScanSession? = makeSession(
            scanner: scanner,
            capabilities: capabilities
        )
        weak let weakSession = session

        session?.beginIfNeeded()
        await scanner.waitUntilStarted(1)
        session = nil
        await scanner.waitUntilCancellationObserved(for: 1)

        XCTAssertNil(weakSession)
        XCTAssertEqual(capabilities.synchronizeCallCount, 0)
        scanner.resolve(call: 1, with: .init(candidates: [], issues: []))
    }

    func testStaleResultCannotReplaceNewerTerminalSnapshot() async {
        let scanner = ControlledExtensionSettingsScanner()
        let capabilities = ExtensionSettingsCapabilityRecorder()
        let session = makeSession(scanner: scanner, capabilities: capabilities)
        let staleCandidate = makeCandidate(id: "stale")
        let currentCandidate = makeCandidate(id: "current")

        session.beginIfNeeded()
        await scanner.waitUntilStarted(1)
        session.refresh()
        await scanner.waitUntilStarted(2)

        scanner.resolve(
            call: 1,
            with: .init(candidates: [staleCandidate], issues: [])
        )
        scanner.resolve(
            call: 2,
            with: .init(candidates: [currentCandidate], issues: [])
        )
        await waitForState(session) {
            if case .completed(let attempt, _) = $0 {
                return attempt.generation == 2
            }
            return false
        }

        guard case .completed(let attempt, let summary) = session.state else {
            return XCTFail("Expected the current attempt to complete")
        }
        XCTAssertEqual(attempt.generation, 2)
        XCTAssertEqual(summary.discoveredCandidateCount, 1)
        XCTAssertEqual(capabilities.synchronizedCandidates, [currentCandidate])
    }

    func testPartialResultAggregatesScannerAndImportIssues() async {
        let scanner = ControlledExtensionSettingsScanner()
        let unreadableURL = URL(fileURLWithPath: "/Applications/Unreadable.app")
        let capabilities = ExtensionSettingsCapabilityRecorder(
            importResult: .init(
                importedExtensionCount: 2,
                failedMessages: ["Import failed"],
                skippedUnreadableCount: 1
            )
        )
        let session = makeSession(scanner: scanner, capabilities: capabilities)

        session.beginIfNeeded()
        await scanner.waitUntilStarted(1)
        scanner.resolve(
            call: 1,
            with: .init(
                candidates: [makeCandidate(id: "partial")],
                issues: [.unreadableBundle(unreadableURL)]
            )
        )
        await waitForState(session) {
            if case .completed = $0 { return true }
            return false
        }

        guard case .completed(_, let summary) = session.state else {
            return XCTFail("Expected a partial scan result")
        }
        XCTAssertTrue(summary.hasIssues)
        XCTAssertEqual(summary.importedExtensionCount, 2)
        XCTAssertEqual(summary.scannerIssues, [.unreadableBundle(unreadableURL)])
        XCTAssertEqual(summary.failedMessages, ["Import failed"])
        XCTAssertEqual(summary.skippedUnreadableCount, 1)
    }

    func testCapabilityErrorPublishesTerminalFailure() async {
        let session = ExtensionSettingsScanSession(
            scan: { throw ExtensionSettingsTestError.scanFailed },
            synchronize: { _ in
                XCTFail("Synchronization must not run after a scan error")
                return .init(
                    importedExtensionCount: 0,
                    failedMessages: [],
                    skippedUnreadableCount: 0
                )
            },
            loadContentBlockers: {
                XCTFail("Content blockers must not load after a scan error")
                return []
            }
        )

        session.beginIfNeeded()
        await waitForState(session) {
            if case .failed = $0 { return true }
            return false
        }

        guard case .failed(let attempt, let message) = session.state else {
            return XCTFail("Expected a terminal failure")
        }
        XCTAssertEqual(attempt.generation, 1)
        XCTAssertEqual(message, "Controlled scan failure")
        XCTAssertEqual(session.snapshot, .empty)
    }

    private func makeSession(
        scanner: ControlledExtensionSettingsScanner,
        capabilities: ExtensionSettingsCapabilityRecorder
    ) -> ExtensionSettingsScanSession {
        ExtensionSettingsScanSession(
            scan: { await scanner.scan() },
            synchronize: { candidates in
                await capabilities.synchronize(candidates)
            },
            loadContentBlockers: {
                try capabilities.loadContentBlockers()
            }
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ControlledExtensionSettingsScanner {
    private var pendingResults: [
        Int: CheckedContinuation<ExtensionSettingsScanDiscovery, Never>
    ] = [:]
    private var startWaiters: [
        (count: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []
    private var cancelledCalls: Set<Int> = []
    private var cancellationWaiters: [
        (call: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []
    private(set) var callCount = 0

    func waitUntilStarted(_ expectedCallCount: Int) async {
        guard callCount < expectedCallCount else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((expectedCallCount, continuation))
        }
    }

    func waitUntilCancellationObserved(for call: Int) async {
        guard cancelledCalls.contains(call) == false else { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append((call, continuation))
        }
    }

    func resolve(call: Int, with discovery: ExtensionSettingsScanDiscovery) {
        pendingResults.removeValue(forKey: call)?.resume(returning: discovery)
    }

    func scan() async -> ExtensionSettingsScanDiscovery {
        callCount += 1
        let call = callCount
        resumeSatisfiedStartWaiters()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingResults[call] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.recordCancellation(for: call)
            }
        }
    }

    private func recordCancellation(for call: Int) {
        cancelledCalls.insert(call)
        let satisfied = cancellationWaiters.filter { $0.call == call }
        cancellationWaiters.removeAll { $0.call == call }
        for waiter in satisfied {
            waiter.continuation.resume()
        }
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
private final class ControlledExtensionSettingsSynchronizer {
    private var pendingResults: [
        Int: CheckedContinuation<ExtensionSettingsImportResult, Never>
    ] = [:]
    private var startWaiters: [
        (count: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []
    private var cancelledCalls: Set<Int> = []
    private var cancellationWaiters: [
        (call: Int, continuation: CheckedContinuation<Void, Never>)
    ] = []
    private(set) var callCount = 0
    private(set) var candidateIDsByCall: [Int: [String]] = [:]

    func waitUntilStarted(_ expectedCallCount: Int) async {
        guard callCount < expectedCallCount else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((expectedCallCount, continuation))
        }
    }

    func waitUntilCancellationObserved(for call: Int) async {
        guard cancelledCalls.contains(call) == false else { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append((call, continuation))
        }
    }

    func resolve(call: Int, with result: ExtensionSettingsImportResult) {
        pendingResults.removeValue(forKey: call)?.resume(returning: result)
    }

    func synchronize(
        _ candidates: [DiscoveredSafariExtensionCandidate]
    ) async -> ExtensionSettingsImportResult {
        callCount += 1
        let call = callCount
        candidateIDsByCall[call] = candidates.map(\.id)
        resumeSatisfiedStartWaiters()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingResults[call] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.recordCancellation(for: call)
            }
        }
    }

    private func recordCancellation(for call: Int) {
        cancelledCalls.insert(call)
        let satisfied = cancellationWaiters.filter { $0.call == call }
        cancellationWaiters.removeAll { $0.call == call }
        for waiter in satisfied {
            waiter.continuation.resume()
        }
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
private final class ExtensionSettingsCapabilityRecorder {
    private let importResult: ExtensionSettingsImportResult
    private let contentBlockerRecords: [InstalledSafariContentBlockerRecord]
    private(set) var synchronizedCandidates: [
        DiscoveredSafariExtensionCandidate
    ] = []
    private(set) var synchronizeCallCount = 0
    private(set) var loadCallCount = 0

    init(
        importResult: ExtensionSettingsImportResult = .init(
            importedExtensionCount: 0,
            failedMessages: [],
            skippedUnreadableCount: 0
        ),
        contentBlockerRecords: [InstalledSafariContentBlockerRecord] = []
    ) {
        self.importResult = importResult
        self.contentBlockerRecords = contentBlockerRecords
    }

    func synchronize(
        _ candidates: [DiscoveredSafariExtensionCandidate]
    ) async -> ExtensionSettingsImportResult {
        synchronizeCallCount += 1
        synchronizedCandidates = candidates
        return importResult
    }

    func loadContentBlockers() throws -> [InstalledSafariContentBlockerRecord] {
        loadCallCount += 1
        return contentBlockerRecords
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ExtensionSettingsStateWaiter {
    private let session: ExtensionSettingsScanSession
    private let predicate: (ExtensionSettingsScanState) -> Bool
    private var continuation: CheckedContinuation<Void, Never>?

    init(
        session: ExtensionSettingsScanSession,
        predicate: @escaping (ExtensionSettingsScanState) -> Bool
    ) {
        self.session = session
        self.predicate = predicate
    }

    func wait() async {
        guard predicate(session.state) == false else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observe()
        }
    }

    private func observe() {
        guard continuation != nil else { return }
        let isSatisfied = withObservationTracking {
            predicate(session.state)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observe()
            }
        }
        if isSatisfied {
            continuation?.resume()
            continuation = nil
        }
    }
}

@available(macOS 15.5, *)
@MainActor
private func waitForState(
    _ session: ExtensionSettingsScanSession,
    predicate: @escaping (ExtensionSettingsScanState) -> Bool
) async {
    await ExtensionSettingsStateWaiter(
        session: session,
        predicate: predicate
    ).wait()
}

private enum ExtensionSettingsTestError: LocalizedError {
    case scanFailed

    var errorDescription: String? { "Controlled scan failure" }
}

private func makeCandidate(
    id: String,
    kind: SafariExtensionBundleKind = .webExtension,
    status: SafariExtensionRuntimeStatus = .webExtensionImportable
) -> DiscoveredSafariExtensionCandidate {
    let appURL = URL(fileURLWithPath: "/Applications/\(id).app")
    return DiscoveredSafariExtensionCandidate(
        extensionBundleIdentifier: id,
        displayName: id,
        version: "1.0",
        extensionPointIdentifier: "test.extension.point",
        bundleKind: kind,
        runtimeStatus: status,
        containingAppName: id,
        containingAppBundleIdentifier: "test.\(id)",
        containingAppURL: appURL,
        appexURL: appURL.appendingPathComponent("Contents/PlugIns/\(id).appex"),
        manifestURL: appURL.appendingPathComponent("manifest.json"),
        isReadable: true
    )
}

private func makeContentBlockerRecord(
    id: String,
    isEnabled: Bool = true
) -> InstalledSafariContentBlockerRecord {
    InstalledSafariContentBlockerRecord(
        id: id,
        extensionBundleIdentifier: id,
        displayName: id,
        version: "1.0",
        containingAppName: id,
        containingAppBundleIdentifier: "test.\(id)",
        appexPath: "/Applications/\(id).app/Contents/PlugIns/\(id).appex",
        containingAppPath: "/Applications/\(id).app",
        resourceFingerprint: "fingerprint-\(id)",
        isEnabled: isEnabled,
        installDate: .distantPast,
        lastUpdateDate: .distantPast,
        compileStatus: .available,
        lastError: nil,
        ruleListCount: 1,
        ignoredEmptyRuleListCount: 0
    )
}
