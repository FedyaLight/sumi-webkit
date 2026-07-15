import SwiftData
import WebKit
import XCTest

@testable import Sumi

/// Shared production-shaped harness for native-messaging callback admission
/// tests. Callbacks are driven through the real
/// `ExtensionControllerDelegateBridge` (send) or the exact settlement seam
/// the bridge uses (connect), against a live `ExtensionManager` with a real
/// installed, enabled extension context/controller binding. The external
/// companion-application boundary is modeled with a fake launcher/adapter so
/// no real application is ever launched.
@available(macOS 15.5, *)
@MainActor
class ExtensionNativeMessagingAdmissionTestCase: XCTestCase {
    static let fixtureHostBundleID = "com.example.sumi.nmhost"

    struct Harness {
        let manager: ExtensionManager
        let inspection: ExtensionManagerTestInspection
        let profileID: UUID
        let extensionID: String
        let context: WKWebExtensionContext
        let controller: WKWebExtensionController
    }

    final class MockHostLauncher: SumiHostApplicationLaunching {
        var bundleURLs: [String: URL] = [:]
        var openedBundleIdentifiers: [String] = []

        func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
            bundleURLs[bundleIdentifier]
        }

        func openApplication(withBundleIdentifier bundleIdentifier: String) async throws {
            openedBundleIdentifiers.append(bundleIdentifier)
        }
    }

    /// Adapter whose replies/completions are held until the test releases
    /// them, modeling the real async companion-application boundary.
    @MainActor
    final class HoldableProtocolAdapter: SumiNativeMessagingProtocolAdapter {
        let protocolIdentifier = "test.holdable"
        private let supportedHosts: Set<String>
        private(set) var oneShotRequestCount = 0
        private(set) var connectRequestCount = 0
        private(set) var heldOneShotReplies: [(Any?, (any Error)?) -> Void] = []
        private(set) var heldConnectCompletions: [((any Error)?) -> Void] = []
        var completesImmediately = false

        init(supportedHosts: Set<String>) {
            self.supportedHosts = supportedHosts
        }

        func supports(hostBundleIdentifier: String) -> Bool {
            supportedHosts.contains(hostBundleIdentifier)
        }

        func relayOneShotMessage(
            request: SumiNativeMessagingOneShotRequest,
            launcher: SumiHostApplicationLaunching,
            replyHandler: @escaping (Any?, (any Error)?) -> Void
        ) {
            _ = request
            _ = launcher
            oneShotRequestCount += 1
            if completesImmediately {
                replyHandler(["pong": true], nil)
                return
            }
            heldOneShotReplies.append(replyHandler)
        }

        func completeHeldOneShotReplies(value: Any?, error: (any Error)? = nil) {
            let held = heldOneShotReplies
            heldOneShotReplies = []
            held.forEach { $0(value, error) }
        }

        func connectPort(
            session: SumiNativeMessagingPortSession,
            launcher: SumiHostApplicationLaunching,
            completionHandler: @escaping ((any Error)?) -> Void
        ) {
            _ = session
            _ = launcher
            connectRequestCount += 1
            if completesImmediately {
                completionHandler(nil)
                return
            }
            heldConnectCompletions.append(completionHandler)
        }

        func completeHeldConnectCompletions(error: (any Error)? = nil) {
            let held = heldConnectCompletions
            heldConnectCompletions = []
            held.forEach { $0(error) }
        }

        func relayPortMessage(
            session: SumiNativeMessagingPortSession,
            message: Any
        ) -> Bool {
            _ = session
            _ = message
            return true
        }
    }

    @MainActor
    final class MockNativeMessagingPort: SumiNativeMessagingPortControlling {
        var applicationIdentifier: String?
        var isDisconnected = false
        var disconnectCount = 0
        /// Fires when the port session wires its handlers during
        /// construction, modeling a reentrant callback during registration.
        var onMessageHandlerWired: (() -> Void)?
        var messageHandler: ((Any?, (any Error)?) -> Void)? {
            didSet {
                if messageHandler != nil {
                    onMessageHandlerWired?()
                }
            }
        }

        var disconnectHandler: (((any Error)?) -> Void)?

        func disconnect() {
            disconnect(throwing: nil)
        }

        func disconnect(throwing error: (any Error)?) {
            disconnectCount += 1
            guard isDisconnected == false else { return }
            isDisconnected = true
            disconnectHandler?(error)
        }
    }

    private var modelContainers: [ModelContainer] = []

    override func tearDown() {
        modelContainers = []
        super.tearDown()
    }

    // MARK: - Harness construction

    func makeHarness(
        name: String,
        withBackgroundContent: Bool = false
    ) async throws -> Harness {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        modelContainers.append(container)
        let profile = Profile(name: name)
        let inspection = ExtensionManagerInspectionCapture()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            testInspectionDidAssemble: inspection.install
        )
        // Intercept every background load before any runtime activation so
        // tests never execute real background content in the test host.
        manager.testHooks.backgroundContentWake = { _, _ in }
        let installed = try await installExtension(
            inspection: inspection.inspection,
            name: name,
            withBackgroundContent: withBackgroundContent
        )
        _ = try await inspection.inspection.installation.lifecycle.enable(installed.id)
        let context = try XCTUnwrap(
            inspection.inspection.contextState.profileState.context(for: installed.id, profileId: profile.id)
        )
        let controller = inspection.inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        XCTAssertNotNil(
            inspection.inspection.controller.callbackAdmission.capture(
                context: context,
                controller: controller
            ),
            "harness must start from an admissible current binding"
        )
        return Harness(
            manager: manager,
            inspection: inspection.inspection,
            profileID: profile.id,
            extensionID: installed.id,
            context: context,
            controller: controller
        )
    }

    /// Installs a relay with test-controlled launcher/adapters and upserts a
    /// Safari-app-extension-shaped installed record for the harness
    /// extension, so the relay policy and route resolution admit the
    /// fixture host without launching a real application.
    @discardableResult
    func installFakeCompanionBoundary(
        harness: Harness,
        adapter: HoldableProtocolAdapter
    ) throws -> MockHostLauncher {
        let launcher = MockHostLauncher()
        launcher.bundleURLs[Self.fixtureHostBundleID] = URL(
            fileURLWithPath: "/Applications/SumiNMFixture.app"
        )
        let relay = SumiNativeMessagingRelay(
            launcher: launcher,
            adapterRegistry: SumiNativeMessagingAdapterRegistry(adapters: [adapter]),
            launchPolicy: SumiCompanionAppLaunchPolicy(),
            loopGuard: SumiNativeMessagingRelayLoopGuard(),
            extensionsModuleEnabled: { true }
        )
        harness.inspection.nativeMessaging.owners.relayOwner().installRelayForTesting(relay)
        try upsertSafariAppExtensionRecord(harness: harness)
        return launcher
    }

    private func upsertSafariAppExtensionRecord(harness: Harness) throws {
        let appexPath = try makeFixtureApp(
            appBundleID: Self.fixtureHostBundleID,
            appexBundleID: "\(Self.fixtureHostBundleID).extension"
        )
        harness.inspection.actionSurfaces.installedExtensions.upsert(
            InstalledExtension(
                id: harness.extensionID,
                name: "Fixture",
                version: "1.0",
                manifestVersion: 3,
                description: nil,
                isEnabled: true,
                installDate: Date(),
                lastUpdateDate: Date(),
                packagePath: "/tmp/\(harness.extensionID)",
                iconPath: nil,
                sourceKind: .safariAppExtension,
                backgroundModel: .serviceWorker,
                incognitoMode: .split,
                sourcePathFingerprint: "fp",
                manifestRootFingerprint: "mf",
                sourceBundlePath: appexPath,
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
        )
    }

    // MARK: - Drivers

    struct SendResult {
        let value: Any?
        let error: (any Error)?
        let replyCalls: Int
    }

    /// Drives sendMessage through the real WebKit delegate bridge and waits
    /// for the reply plus stray-continuation turns.
    func driveSendMessage(
        harness: Harness,
        controller: WKWebExtensionController? = nil,
        applicationIdentifier: String? = fixtureHostBundleID,
        afterDispatch: (@MainActor () -> Void)? = nil
    ) async -> SendResult {
        let collector = SendReplyCollector()
        let firstReply = expectation(description: "native messaging reply")
        harness.inspection.controller.delegateBridge.webExtensionController(
            controller ?? harness.controller,
            sendMessage: ["type": "ping"],
            toApplicationWithIdentifier: applicationIdentifier,
            for: harness.context
        ) { value, error in
            collector.record(value, error)
            if collector.replies.count == 1 {
                firstReply.fulfill()
            }
        }
        afterDispatch?()
        await fulfillment(of: [firstReply], timeout: 2.0)
        await drainMainActorTurns()
        let settled = collector.replies.first
        return SendResult(
            value: settled?.value,
            error: settled?.error,
            replyCalls: collector.replies.count
        )
    }

    /// Records every reply for sends whose adapter completion is held by the
    /// test, so late/stale/double completions stay observable.
    @MainActor
    final class SendReplyCollector {
        private(set) var replies: [(value: Any?, error: (any Error)?)] = []

        func record(_ value: Any?, _ error: (any Error)?) {
            replies.append((value, error))
        }
    }

    /// Dispatches sendMessage through the real bridge without waiting for
    /// the reply; the caller controls the held adapter completion.
    func dispatchSend(
        harness: Harness,
        applicationIdentifier: String? = fixtureHostBundleID
    ) async -> SendReplyCollector {
        let collector = SendReplyCollector()
        harness.inspection.controller.delegateBridge.webExtensionController(
            harness.controller,
            sendMessage: ["type": "ping"],
            toApplicationWithIdentifier: applicationIdentifier,
            for: harness.context
        ) { value, error in
            collector.record(value, error)
        }
        // Let the scheduled relay task reach the held adapter boundary.
        await drainMainActorTurns()
        return collector
    }

    func makeUnrelatedExtensionContext() async throws -> WKWebExtensionContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Unrelated",
            "version": "1.0",
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(
                to: directory.appendingPathComponent("manifest.json"),
                options: [.atomic]
            )
        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        return WKWebExtensionContext(for: webExtension)
    }

    /// A stale/fail-closed callback surfaces the relay error either raw
    /// (bridge capture failure) or mapped into the WebKit callback error
    /// domain with the underlying relay code preserved in userInfo.
    func assertIsStaleCallbackError(
        _ error: (any Error)?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let nsError = error as NSError? else {
            XCTFail("stale callback must fail closed", file: file, line: line)
            return
        }
        let staleCode = SumiNativeMessagingRelay.ErrorCode.extensionContextMissing.rawValue
        let underlyingCode = nsError.userInfo[
            SumiWebExtensionCallbackErrorMapper.underlyingCodeUserInfoKey
        ] as? Int
        XCTAssertTrue(
            nsError.code == staleCode || underlyingCode == staleCode,
            "stale callback must settle with the fail-closed relay error, got \(nsError)",
            file: file,
            line: line
        )
    }

    struct ConnectResult {
        let error: (any Error)?
        let completionCalls: Int
    }

    /// Drives connect through the exact settlement seam the bridge uses,
    /// starting from freshly captured (and asserted admissible) evidence.
    func driveConnect(
        harness: Harness,
        port: any SumiNativeMessagingPortControlling,
        beforeSettlement: (@MainActor (ExtensionControllerCallbackEvidence) -> Void)? = nil
    ) async throws -> ConnectResult {
        let evidence = try XCTUnwrap(
            harness.inspection.controller.callbackAdmission.capture(
                context: harness.context,
                controller: harness.controller
            ),
            "connect must start from admissible evidence"
        )
        beforeSettlement?(evidence)
        let replyCounter = ReplyCounter()
        let settledError: (any Error)? = await withCheckedContinuation { continuation in
            harness.inspection.nativeMessaging.portSettlement.connect(
                using: port,
                evidence: evidence
            ) { error in
                replyCounter.calls += 1
                if replyCounter.calls == 1 {
                    continuation.resume(returning: error)
                }
            }
        }
        await drainMainActorTurns()
        return ConnectResult(error: settledError, completionCalls: replyCounter.calls)
    }

    /// Rebinding the same context bumps its binding revision, which is the
    /// same-object rebind invalidation the admission model must catch.
    func rebindSameContext(_ harness: Harness) {
        _ = harness.inspection.contextState.profiles.setContext(
            harness.context,
            extensionId: harness.extensionID,
            profileId: harness.profileID
        )
    }

    func drainMainActorTurns() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    func drainScheduledRuntimeTasks(_ harness: Harness) async {
        await harness.manager.drainExtensionRuntimeTasksForTests()
        await drainMainActorTurns()
    }

    // MARK: - Fixtures

    private func installExtension(
        inspection: ExtensionManagerTestInspection,
        name: String,
        withBackgroundContent: Bool
    ) async throws -> InstalledExtension {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let installRoot = directory.deletingLastPathComponent()
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: installRoot.path) {
                try FileManager.default.removeItem(at: installRoot)
            }
        }

        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": name,
            "version": "1.0",
            "permissions": ["storage", "nativeMessaging"],
            "action": ["default_popup": "popup.html"],
        ]
        if withBackgroundContent {
            manifest["background"] = ["service_worker": "background.js"]
            try Data("// background\n".utf8).write(
                to: directory.appendingPathComponent("background.js"),
                options: [.atomic]
            )
        }
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(
                to: directory.appendingPathComponent("manifest.json"),
                options: [.atomic]
            )
        try Data("<!doctype html><title>popup</title>".utf8)
            .write(
                to: directory.appendingPathComponent("popup.html"),
                options: [.atomic]
            )

        return try await inspection.installation.installer.install(
            from: directory,
            enableOnInstall: false
        )
    }

    private func makeFixtureApp(
        appBundleID: String,
        appexBundleID: String
    ) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiNMAdmission.\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
        }
        let appURL = root.appendingPathComponent("Host.app", isDirectory: true)
        let appexURL = appURL
            .appendingPathComponent("Contents/PlugIns/Extension.appex", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appexURL.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        try writePlist(
            ["CFBundleIdentifier": appBundleID],
            to: appURL.appendingPathComponent("Contents/Info.plist")
        )
        try writePlist(
            [
                "CFBundleIdentifier": appexBundleID,
                "NSExtension": [
                    "NSExtensionPointIdentifier":
                        SafariExtensionScanner.safariWebExtensionPointIdentifier,
                ],
            ],
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
}

@MainActor
final class ReplyCounter {
    var calls = 0
}
