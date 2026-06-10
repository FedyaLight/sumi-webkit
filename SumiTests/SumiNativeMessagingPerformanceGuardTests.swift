import XCTest

@testable import Sumi

/// Performance guards for native messaging retry storms, idle teardown, and bounded I/O.
@available(macOS 15.5, *)
@MainActor
final class SumiNativeMessagingPerformanceGuardTests: XCTestCase {
    private final class MockHostLauncher: SumiHostApplicationLaunching {
        var bundleURLs: [String: URL] = [:]
        var openedBundleIdentifiers: [String] = []

        func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
            bundleURLs[bundleIdentifier]
        }

        func openApplication(withBundleIdentifier bundleIdentifier: String) async throws {
            openedBundleIdentifiers.append(bundleIdentifier)
        }
    }

    private final class MockNativeMessagingPort: SumiNativeMessagingPortControlling {
        var applicationIdentifier: String?
        var isDisconnected = false
        var messageHandler: ((Any?, (any Error)?) -> Void)?
        var disconnectHandler: (((any Error)?) -> Void)?
        var disconnectError: (any Error)?

        func disconnect() {
            isDisconnected = true
            disconnectHandler?(disconnectError)
        }

        func disconnect(throwing error: (any Error)?) {
            disconnectError = error
            disconnect()
        }
    }

    override func setUp() {
        super.setUp()
        SumiNativeMessagingRuntimeCounters.resetForTesting()
    }

    // MARK: - Repeated failure coalescing

    func testDelegateInvocationCountersTrackWKDelegateEntry() {
        SumiNativeMessagingRuntimeCounters.recordDelegateSendMessageInvoked()
        SumiNativeMessagingRuntimeCounters.recordDelegateConnectInvoked()
        SumiNativeMessagingRuntimeCounters.recordDelegateConnectInvoked()

        let snapshot = SumiNativeMessagingRuntimeCounters.snapshot()
        XCTAssertEqual(snapshot.delegateSendMessageInvokedCount, 1)
        XCTAssertEqual(snapshot.delegateConnectInvokedCount, 2)
    }

    func testRepeatedFailureDiagnosticsAreCoalesced() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.host",
            appexBundleID: "com.example.host.extension"
        )
        let installed = try makeInstalledExtension(id: "ext-perf-coalesce", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        var diagnostics: [SafariExtensionNativeMessagingDiagnostic] = []
        let relay = SumiNativeMessagingRelay(
            importStore: SafariExtensionImportStore(defaults: makeDefaults()),
            launcher: launcher,
            logDiagnostic: { diagnostics.append($0) }
        )

        for _ in 0..<100 {
            _ = await sendMessageReply(
                relay: relay,
                installed: installed,
                applicationIdentifier: "com.example.host"
            )
        }

        XCTAssertTrue(launcher.openedBundleIdentifiers.isEmpty)
        XCTAssertLessThan(diagnostics.count, 10)
        let snapshot = SumiNativeMessagingRuntimeCounters.snapshot()
        XCTAssertGreaterThan(snapshot.repeatedIdenticalErrorCount, 0)
        XCTAssertGreaterThan(snapshot.coalescedDiagnosticEmits, 0)
    }

    func testDiagnosticCoalescerBoundsEmissionToDetailedThenSummarized() {
        var styles: [SumiNativeMessagingDiagnosticLogStyle] = []
        let coalescer = SumiNativeMessagingDiagnosticCoalescer { _, style in
            styles.append(style)
        }
        let base = SafariExtensionNativeMessagingDiagnostic(
            extensionId: "ext-1",
            direction: .send,
            requestedApplicationIdentifier: "com.example.host",
            hostBundleIdentifier: "com.example.host",
            resolverBucket: nil,
            outcome: .companionAppProtocolUnknown,
            errorDomain: SumiNativeMessagingRelay.errorDomain,
            errorCode: SumiNativeMessagingRelay.ErrorCode.companionAppProtocolUnknown.rawValue,
            retryCountBucket: .none
        )

        for index in 0..<50 {
            coalescer.record(
                SafariExtensionNativeMessagingDiagnostic(
                    extensionId: base.extensionId,
                    direction: base.direction,
                    requestedApplicationIdentifier: base.requestedApplicationIdentifier,
                    hostBundleIdentifier: base.hostBundleIdentifier,
                    resolverBucket: base.resolverBucket,
                    outcome: index == 0 ? .companionAppProtocolUnknown : .launchSuppressed,
                    errorDomain: base.errorDomain,
                    errorCode: base.errorCode,
                    launchSuppressed: index > 0,
                    retryCountBucket: index > 0 ? .first : SumiNativeMessagingRetryCountBucket.none
                )
            )
        }

        XCTAssertEqual(styles.count, 2)
        XCTAssertEqual(styles.first, .detailed)
        if case .summarized(let repeatCount, let bucket) = styles.last {
            XCTAssertEqual(repeatCount, 2)
            XCTAssertEqual(bucket, .first)
        } else {
            XCTFail("Expected summarized coalesced diagnostic")
        }
    }

    // MARK: - Retry cooldown

    func testRetryCooldownSuppressesRepeatedLaunchAttempts() async throws {
        let loopGuard = SumiNativeMessagingRelayLoopGuard()
        let key = SumiNativeMessagingRelayLoopGuard.SessionKey(
            profileId: UUID(),
            extensionId: "ext-cooldown",
            applicationIdentifier: "com.example.host"
        )
        loopGuard.recordCompanionAppProtocolUnknown(key: key, launchAttempted: false)

        let evaluation = loopGuard.evaluate(
            key: key,
            hostBundleIdentifier: "com.example.host"
        )

        XCTAssertTrue(evaluation.launchSuppressed)
        XCTAssertTrue(evaluation.isWithinCooldown)
        XCTAssertFalse(evaluation.shouldLaunchHost)
    }

    func testSupportedAdapterLaunchIsBoundedToOneAttemptPerSessionKey() async throws {
        let appexPath = try makeFixtureApp(
            appBundleID: "com.example.host",
            appexBundleID: "com.example.host.extension"
        )
        let installed = try makeInstalledExtension(id: "ext-bounded-launch", sourceBundlePath: appexPath)
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        let adapter = SumiNativeMessagingFakePublicAdapter(
            supportedHosts: ["com.example.host"],
            shouldLaunchOnConnect: true
        )
        let relay = SumiNativeMessagingRelay(
            importStore: SafariExtensionImportStore(defaults: makeDefaults()),
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: [adapter]),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )

        let port1 = MockNativeMessagingPort()
        port1.applicationIdentifier = "com.example.host"
        _ = await connectReply(relay: relay, port: port1, installed: installed)
        XCTAssertEqual(launcher.openedBundleIdentifiers.count, 1)

        let port2 = MockNativeMessagingPort()
        port2.applicationIdentifier = "com.example.host"
        _ = await connectReply(relay: relay, port: port2, installed: installed)

        XCTAssertEqual(launcher.openedBundleIdentifiers.count, 1)
    }

    // MARK: - Idle cleanup

    func testIdlePortSessionDisconnectsAfterInactivityTimeout() async throws {
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.example.host"
        let session = SumiNativeMessagingPortSession(
            port: port,
            adapter: nil,
            extensionId: "ext-idle-guard",
            hostBundleIdentifier: "com.example.host",
            resolverBucket: .knownCompanionAlias,
            logDiagnostic: { _ in },
            companionProtocolErrorProvider: {
                SumiNativeMessagingErrorMapper.relayError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: nil
                )
            },
            portInactivityTimeout: .milliseconds(50)
        )
        _ = session

        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(port.isDisconnected)
    }

    func testContextUnloadClearsLiveNativeMessagingSessions() async throws {
        let installed = try makeInstalledExtension(
            id: "ext-unload-guard",
            sourceBundlePath: try makeFixtureApp(
                appBundleID: "com.example.host",
                appexBundleID: "com.example.host.extension"
            )
        )
        let launcher = MockHostLauncher()
        launcher.bundleURLs["com.example.host"] = URL(fileURLWithPath: "/Applications/Example.app")
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(
                adapters: [
                    SumiNativeMessagingFakePublicAdapter(
                        supportedHosts: ["com.example.host"],
                        shouldLaunchOnConnect: false
                    ),
                ]
            ),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )
        let port = MockNativeMessagingPort()
        port.applicationIdentifier = "com.example.host"
        _ = await connectReply(relay: relay, port: port, installed: installed)
        XCTAssertEqual(SumiNativeMessagingRuntimeCounters.snapshot().liveRelayPortSessions, 1)

        relay.clearLaunchSessionOnExtensionContextUnload(forExtensionId: installed.id)

        let snapshot = SumiNativeMessagingRuntimeCounters.snapshot()
        XCTAssertEqual(snapshot.liveRelayPortSessions, 0)
        XCTAssertEqual(snapshot.contextUnloadCount, 1)
        XCTAssertTrue(port.isDisconnected)
    }

    // MARK: - Bounded buffers

    func testProxyFramingRejectsOversizedLengthPrefix() {
        var buffer = Data()
        var oversizedLength = UInt32(BitwardenDesktopProxyFraming.maxFrameBytes + 1).littleEndian
        buffer.append(Data(bytes: &oversizedLength, count: MemoryLayout<UInt32>.size))
        buffer.append(Data(count: 16))

        let decoded = BitwardenDesktopProxyFraming.decodeNext(from: &buffer)

        XCTAssertTrue(decoded is NSNull)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testProxyFramingWaitsForCompleteFrameBeforeDecode() {
        let payload = Data("{\"command\":\"connected\"}".utf8)
        var length = UInt32(payload.count).littleEndian
        var buffer = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        buffer.append(payload.prefix(4))

        XCTAssertNil(BitwardenDesktopProxyFraming.decodeNext(from: &buffer))
        XCTAssertEqual(buffer.count, MemoryLayout<UInt32>.size + 4)

        buffer.append(payload.suffix(from: 4))
        let decoded = BitwardenDesktopProxyFraming.decodeNext(from: &buffer)
        XCTAssertTrue(decoded is [String: Any])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testTransportShutdownClearsPendingReadBuffer() throws {
        let transportSource = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/BitwardenDesktopProxyTransport.swift"
        )
        XCTAssertTrue(transportSource.contains("pendingBuffer.removeAll()"))
        XCTAssertTrue(transportSource.contains("maxFrameBytes"))
        XCTAssertTrue(transportSource.contains("Task.detached(priority: .utility)"))
    }

    // MARK: - DEBUG performance report

    func testPerformanceReportIsPayloadFree() {
        SumiNativeMessagingRuntimeCounters.recordSendMessage(applicationIdentifier: "com.example.host")
        SumiNativeMessagingRuntimeCounters.recordConnect(applicationIdentifier: "com.example.host")
        SumiNativeMessagingRuntimeCounters.recordPopupOpened(extensionId: "ext-report")

        let report = SumiNativeMessagingRuntimeCounters.buildPerformanceReport(
            context: "unit-test"
        )

        XCTAssertEqual(report.context, "unit-test")
        XCTAssertEqual(report.counters.sendMessageCount, 1)
        XCTAssertEqual(report.counters.connectCount, 1)
        XCTAssertEqual(report.counters.popupOpenCount, 1)
        XCTAssertFalse(report.hasActivePortSessions)
        XCTAssertFalse(report.hasActiveDesktopTransports)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try? encoder.encode(report)
        let json = String(data: data ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("password"))
        XCTAssertFalse(json.contains("credential"))
        XCTAssertFalse(json.contains("message"))
    }

    // MARK: - Helpers

    private func connectReply(
        relay: SumiNativeMessagingRelay,
        port: MockNativeMessagingPort,
        installed: InstalledExtension
    ) async -> (any Error)? {
        let expectation = expectation(description: "connect")
        var connectError: (any Error)?
        _ = relay.handleConnect(
            port: port,
            extensionId: installed.id,
            installedExtensions: [installed],
            registerHandler: { _ in },
            completionHandler: { error in
                connectError = error
                expectation.fulfill()
            }
        )
        await fulfillment(of: [expectation], timeout: 5)
        return connectError
    }

    private func sendMessageReply(
        relay: SumiNativeMessagingRelay,
        installed: InstalledExtension,
        applicationIdentifier: String
    ) async -> (value: Any?, error: (any Error)?) {
        let expectation = expectation(description: "send")
        var replyValue: Any?
        var replyError: (any Error)?
        relay.handleSendMessage(
            applicationIdentifier: applicationIdentifier,
            message: ["type": "ping"],
            extensionId: installed.id,
            installedExtensions: [installed]
        ) { value, error in
            replyValue = value
            replyError = error
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 5)
        return (replyValue, replyError)
    }

    private func makeInstalledExtension(
        id: String,
        sourceBundlePath: String
    ) throws -> InstalledExtension {
        InstalledExtension(
            id: id,
            name: "Fixture",
            version: "1.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: true,
            installDate: Date(),
            lastUpdateDate: Date(),
            packagePath: "/tmp/\(id)",
            iconPath: nil,
            sourceKind: .safariAppExtension,
            backgroundModel: .serviceWorker,
            incognitoMode: .split,
            sourcePathFingerprint: "fp",
            manifestRootFingerprint: "mf",
            sourceBundlePath: sourceBundlePath,
            optionsPagePath: nil,
            defaultPopupPath: nil,
            hasBackground: true,
            hasAction: true,
            hasOptionsPage: false,
            hasContentScripts: true,
            hasExtensionPages: true,
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: [],
                broadScope: false,
                hasContentScripts: true,
                hasAction: true,
                hasOptionsPage: false,
                hasExtensionPages: true
            ),
            manifest: [:]
        )
    }

    private func makeFixtureApp(
        appBundleID: String,
        appexBundleID: String
    ) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiNM.Perf.\(UUID().uuidString)", isDirectory: true)
        let appURL = root.appendingPathComponent("Host.app", isDirectory: true)
        let appexURL = appURL
            .appendingPathComponent("Contents/PlugIns/Extension.appex", isDirectory: true)

        try FileManager.default.createDirectory(
            at: appexURL.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )

        let appInfo: [String: Any] = ["CFBundleIdentifier": appBundleID]
        let appexInfo: [String: Any] = [
            "CFBundleIdentifier": appexBundleID,
            "NSExtension": [
                "NSExtensionPointIdentifier": SafariExtensionScanner.safariWebExtensionPointIdentifier,
            ],
        ]
        try writePlist(appInfo, to: appURL.appendingPathComponent("Contents/Info.plist"))
        try writePlist(
            appexInfo,
            to: appexURL.appendingPathComponent("Contents/Info.plist")
        )
        return appexURL.path
    }

    private func writePlist(_ dictionary: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .xml,
            options: 0
        )
        try data.write(to: url)
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SumiNativeMessagingPerformanceGuardTests.\(UUID().uuidString)")!
    }

    private func source(named relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
