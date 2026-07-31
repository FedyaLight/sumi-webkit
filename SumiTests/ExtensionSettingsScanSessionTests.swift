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
        XCTAssertEqual(capabilities.loadCallCount, 0)
    }

    func testScanDoesNotAddDiscoveredWebExtensions() async {
        let scanner = ControlledExtensionSettingsScanner()
        let capabilities = ExtensionSettingsCapabilityRecorder()
        let session = makeSession(scanner: scanner, capabilities: capabilities)

        session.refresh()
        await scanner.waitUntilStarted(1)
        scanner.resolve(
            call: 1,
            with: .init(
                candidates: [makeCandidate(id: "discovered-web-extension")],
                issues: []
            )
        )
        await waitForState(session) {
            if case .completed = $0 { return true }
            return false
        }

        XCTAssertEqual(
            session.snapshot.webExtensionCandidates.map(\.id),
            ["discovered-web-extension"],
            "Scanning must publish a finding without installing it"
        )
    }

    func testFindingsExcludeAlreadyAddedSafariExtension() {
        let added = makeCandidate(id: "already-added")
        let relocated = makeCandidate(id: "relocated")
        let available = makeCandidate(id: "available")
        let projection = ExtensionSettingsFindingsProjection(
            discoveredCandidates: [added, relocated, available],
            installedExtensions: [
                makeInstalledSafariExtension(
                    id: added.id,
                    sourceBundlePath: added.appexURL.path
                ),
                makeInstalledSafariExtension(
                    id: relocated.id,
                    sourceBundlePath: "/Applications/Old.app/Old.appex"
                ),
            ]
        )

        XCTAssertEqual(projection.candidates.map(\.id), [available.id])
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
            contentBlockerRecords: [blockerRecord]
        )
        let session = makeSession(scanner: scanner, capabilities: capabilities)

        session.refresh()
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
        XCTAssertFalse(summary.hasIssues)
        XCTAssertEqual(session.snapshot.webExtensionCandidates, [webExtension])
        XCTAssertEqual(session.snapshot.contentBlockerCandidates, [contentBlocker])
        XCTAssertEqual(session.snapshot.unsupportedCandidates, [unsupported])
        XCTAssertEqual(session.snapshot.contentBlockerRecords, [blockerRecord])
        XCTAssertEqual(capabilities.loadCallCount, 1)
    }

    func testRefreshSupersedesActiveAttempt() async {
        let scanner = ControlledExtensionSettingsScanner()
        let capabilities = ExtensionSettingsCapabilityRecorder()
        let session = makeSession(scanner: scanner, capabilities: capabilities)

        session.refresh()
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

        XCTAssertEqual(capabilities.loadCallCount, 1)
    }

    func testCancellationPublishesTerminalState() async {
        let scanner = ControlledExtensionSettingsScanner()
        let capabilities = ExtensionSettingsCapabilityRecorder()
        let session = makeSession(scanner: scanner, capabilities: capabilities)

        session.refresh()
        await scanner.waitUntilStarted(1)
        session.cancel()
        await scanner.waitUntilCancellationObserved(for: 1)

        XCTAssertEqual(session.state, .cancelled(.init(generation: 1)))
        scanner.resolve(call: 1, with: .init(candidates: [], issues: []))
    }

    func testCancelledSessionCanBeScannedAgainManually() async {
        let scanner = ControlledExtensionSettingsScanner()
        let capabilities = ExtensionSettingsCapabilityRecorder()
        let session = makeSession(scanner: scanner, capabilities: capabilities)

        session.refresh()
        await scanner.waitUntilStarted(1)
        session.cancel()
        await scanner.waitUntilCancellationObserved(for: 1)

        session.refresh()
        await scanner.waitUntilStarted(2)
        scanner.resolve(call: 1, with: .init(candidates: [], issues: []))
        scanner.resolve(call: 2, with: .init(candidates: [], issues: []))
        await waitForState(session) {
            if case .completed(let attempt, _) = $0 {
                return attempt.generation == 2
            }
            return false
        }

        XCTAssertEqual(capabilities.loadCallCount, 1)
    }

    func testTeardownCancelsAttemptAndReleasesSession() async {
        let scanner = ControlledExtensionSettingsScanner()
        let capabilities = ExtensionSettingsCapabilityRecorder()
        var session: ExtensionSettingsScanSession? = makeSession(
            scanner: scanner,
            capabilities: capabilities
        )
        weak let weakSession = session

        session?.refresh()
        await scanner.waitUntilStarted(1)
        session = nil
        await scanner.waitUntilCancellationObserved(for: 1)

        XCTAssertNil(weakSession)
        scanner.resolve(call: 1, with: .init(candidates: [], issues: []))
    }

    func testStaleResultCannotReplaceNewerTerminalSnapshot() async {
        let scanner = ControlledExtensionSettingsScanner()
        let capabilities = ExtensionSettingsCapabilityRecorder()
        let session = makeSession(scanner: scanner, capabilities: capabilities)
        let staleCandidate = makeCandidate(id: "stale")
        let currentCandidate = makeCandidate(id: "current")

        session.refresh()
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
        XCTAssertEqual(session.snapshot.webExtensionCandidates, [currentCandidate])
    }

    func testPartialResultReportsScannerIssues() async {
        let scanner = ControlledExtensionSettingsScanner()
        let unreadableURL = URL(fileURLWithPath: "/Applications/Unreadable.app")
        let capabilities = ExtensionSettingsCapabilityRecorder()
        let session = makeSession(scanner: scanner, capabilities: capabilities)

        session.refresh()
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
        XCTAssertEqual(summary.scannerIssues, [.unreadableBundle(unreadableURL)])
    }

    func testCapabilityErrorPublishesTerminalFailure() async {
        let session = ExtensionSettingsScanSession(
            scan: { throw ExtensionSettingsTestError.scanFailed },
            loadContentBlockers: {
                XCTFail("Content blockers must not load after a scan error")
                return []
            }
        )

        session.refresh()
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
private final class ExtensionSettingsCapabilityRecorder {
    private let contentBlockerRecords: [InstalledSafariContentBlockerRecord]
    private(set) var loadCallCount = 0

    init(
        contentBlockerRecords: [InstalledSafariContentBlockerRecord] = []
    ) {
        self.contentBlockerRecords = contentBlockerRecords
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

private func makeInstalledSafariExtension(
    id: String,
    sourceBundlePath: String
) -> InstalledExtension {
    InstalledExtension(
        id: id,
        name: id,
        version: "1.0",
        manifestVersion: 3,
        description: nil,
        isEnabled: false,
        installDate: .distantPast,
        lastUpdateDate: .distantPast,
        packagePath: sourceBundlePath,
        iconPath: nil,
        sourceKind: .safariAppExtension,
        backgroundModel: .serviceWorker,
        incognitoMode: .spanning,
        sourcePathFingerprint: "source-\(id)",
        manifestRootFingerprint: "manifest-\(id)",
        sourceBundlePath: sourceBundlePath,
        optionsPagePath: nil,
        defaultPopupPath: nil,
        hasBackground: true,
        hasAction: true,
        hasOptionsPage: false,
        hasContentScripts: true,
        hasExtensionPages: false,
        activationSummary: ExtensionActivationSummary(
            matchPatternStrings: [],
            broadScope: false,
            hasContentScripts: true,
            hasAction: true,
            hasOptionsPage: false,
            hasExtensionPages: false
        ),
        manifest: [:]
    )
}
