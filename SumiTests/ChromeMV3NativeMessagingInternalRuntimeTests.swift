import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3NativeMessagingInternalRuntimeTests: XCTestCase {
    private let extensionID = "abcdefghijklmnopabcdefghijklmnop"
    private let otherExtensionID = "ponmlkjihgfedcbaponmlkjihgfedcba"
    private let hostName =
        ChromeMV3NativeMessagingFixtureHostBuilder
        .passwordManagerFixtureHostName
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    @MainActor
    func testDisabledModuleBlocksNativeMessagingImplementationReport()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 module diagnostics require macOS 15.5.")
        }
        let root = try temporaryDirectory(named: "disabled-module")
        let module = try makeModule(enabled: false)

        let report = module.chromeMV3NativeMessagingImplementationReportIfEnabled(
            fromRewrittenBundleRoot: root,
            fixtureHostRootURL: root.appendingPathComponent(
                "fixture-hosts",
                isDirectory: true
            ),
            writeReport: true
        )

        XCTAssertNil(report)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    ChromeMV3NativeMessagingImplementationReportWriter
                        .reportFileName
                ).path
            )
        )
        XCTAssertFalse(
            module.tearDownChromeMV3NativeMessagingImplementationIfEnabled()
        )
    }

    func testFixtureManifestParsesAndLookupDoesNotScanSystemRoots()
        throws
    {
        let root = try temporaryDirectory(named: "valid-fixture")
        _ = try writeFixture(kind: .echo, root: root)
        let owner = makeOwner(root: root)

        let lookup = owner.lookupPolicy().lookupHost(named: hostName)

        XCTAssertEqual(lookup.status, .found)
        XCTAssertTrue(lookup.manifest?.isValid == true)
        XCTAssertEqual(lookup.manifest?.name, hostName)
        XCTAssertFalse(lookup.arbitrarySystemScanPerformed)
        XCTAssertEqual(lookup.checkedLocations.count, 1)
        XCTAssertTrue(
            lookup.futureLocationsRecorded.allSatisfy {
                $0.lookupAllowedInThisModel == false
            }
        )
    }

    func testFixturePackBuilderCreatesDeterministicProtocolPack()
        throws
    {
        let root = try temporaryDirectory(named: "fixture-pack")
        let baseHostName = "com.example.native_host"

        let first = try ChromeMV3NativeMessagingFixturePackBuilder.writePack(
            targetID: "target-a",
            fixtureRootURL: root,
            baseHostName: baseHostName,
            extensionID: extensionID,
            protocols: [.echo, .error, .malformed, .disconnect]
        )
        let second = try ChromeMV3NativeMessagingFixturePackBuilder.writePack(
            targetID: "target-a",
            fixtureRootURL: root,
            baseHostName: baseHostName,
            extensionID: extensionID,
            protocols: [.disconnect, .malformed, .error, .echo]
        )

        XCTAssertEqual(first.packID, second.packID)
        XCTAssertEqual(first.records.count, 4)
        XCTAssertEqual(first.generatedState, .generated)
        XCTAssertEqual(first.validatedState, .valid)
        XCTAssertTrue(first.noNetworkInvariant)
        XCTAssertTrue(first.noCredentialsInvariant)
        XCTAssertFalse(first.arbitraryHostLaunchAllowed)
        XCTAssertTrue(first.realVendorHostDiscoveryBlocked)
        XCTAssertEqual(
            Set(first.records.map(\.messageProtocol)),
            Set(ChromeMV3NativeMessagingFixtureMessageProtocol.allCases)
        )
        for record in first.records {
            XCTAssertEqual(record.generatedState, .generated)
            XCTAssertEqual(record.validatedState, .valid)
            XCTAssertEqual(record.cleanupState, .notRequired)
            XCTAssertTrue(record.noNetworkInvariant)
            XCTAssertTrue(record.noCredentialsInvariant)
            XCTAssertTrue(record.executableInsideFixtureRoot)
            XCTAssertTrue(record.executableIsExecutable)
            XCTAssertTrue(record.manifestPath?.hasPrefix(root.path) == true)
            XCTAssertTrue(record.executablePath?.hasPrefix(root.path) == true)
            XCTAssertEqual(
                record.allowedOrigins,
                [
                    ChromeMV3NativeMessagingAllowedOrigin.originString(
                        extensionID: extensionID
                    ),
                ]
            )
            let executable = try XCTUnwrap(record.executablePath)
            let script = try String(
                contentsOf: URL(fileURLWithPath: executable),
                encoding: .utf8
            )
            XCTAssertFalse(script.contains("socket"))
            XCTAssertFalse(script.contains("urllib"))
            XCTAssertFalse(script.contains("requests"))
            XCTAssertFalse(script.localizedCaseInsensitiveContains("keychain"))
            XCTAssertFalse(script.localizedCaseInsensitiveContains("credential"))
        }
    }

    func testFixturePackErrorAndDisconnectProtocolsAreDeterministic()
        throws
    {
        let root = try temporaryDirectory(named: "fixture-pack-protocols")
        let baseHostName = "com.example.protocol_host"
        let pack = try ChromeMV3NativeMessagingFixturePackBuilder.writePack(
            targetID: "target-protocols",
            fixtureRootURL: root,
            baseHostName: baseHostName,
            extensionID: extensionID,
            protocols: [.error, .disconnect]
        )
        let errorHost = try XCTUnwrap(
            pack.record(for: .error, baseHostName: baseHostName)?.hostName
        )
        let disconnectHost = try XCTUnwrap(
            pack.record(for: .disconnect, baseHostName: baseHostName)?.hostName
        )
        let errorOwner = makeOwner(root: root, hostName: errorHost)
        let disconnectOwner = makeOwner(root: root, hostName: disconnectHost)

        let error = errorOwner.sendNativeMessage(
            hostName: errorHost,
            message: .object(["kind": .string("error")])
        )
        let disconnect = disconnectOwner.sendNativeMessage(
            hostName: disconnectHost,
            message: .object(["kind": .string("disconnect")])
        )

        XCTAssertTrue(error.succeeded, error.diagnostics.joined(separator: "\n"))
        XCTAssertEqual(object(error.response)?["ok"], .bool(false))
        XCTAssertEqual(object(error.response)?["error"], .string("fixtureError"))
        XCTAssertFalse(disconnect.succeeded)
        XCTAssertEqual(disconnect.lastErrorCode, .hostCrashedOrExited)
        XCTAssertEqual(disconnect.lifecycle.disconnectReason, .nativeHostExited)
        XCTAssertTrue(disconnect.lifecycle.processLaunchAttempted)
        XCTAssertFalse(disconnect.lifecycle.processLaunchAllowedInProduct)
    }

    func testAllowedOriginsMismatchBlocksLaunch()
        throws
    {
        let root = try temporaryDirectory(named: "origin-mismatch")
        _ = try writeFixture(kind: .echo, root: root)
        let owner = makeOwner(root: root, extensionID: otherExtensionID)

        let result = owner.sendNativeMessage(
            hostName: hostName,
            message: .object(["kind": .string("mismatch")])
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.lastErrorCode, .authorizationFailed)
        XCTAssertFalse(result.lifecycle.processLaunchAttempted)
        XCTAssertFalse(result.launchPolicy.processLaunchAllowedForFixtureHost)
        XCTAssertFalse(result.launchPolicy.processLaunchAllowedInProduct)
    }

    func testTrustedHostApprovalRequiredBeforeFixtureLaunch()
        throws
    {
        let root = try temporaryDirectory(named: "approval-required")
        _ = try writeFixture(kind: .echo, root: root)
        let owner = makeOwner(root: root, includeTrustedHostApproval: false)

        let result = owner.sendNativeMessage(
            hostName: hostName,
            message: .object(["kind": .string("approvalRequired")])
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.lastErrorCode, .trustedHostApprovalRequired)
        XCTAssertFalse(result.lifecycle.processLaunchAttempted)
        XCTAssertFalse(result.preflight.trustedHostPolicyApproved)
        XCTAssertFalse(result.launchPolicy.trustedHostApprovedForDeveloperPreview)
    }

    func testMissingNativeMessagingPermissionBlocksLaunch()
        throws
    {
        let root = try temporaryDirectory(named: "missing-permission")
        _ = try writeFixture(kind: .echo, root: root)
        let owner = makeOwner(root: root, permissionState: .missing)

        let result = owner.sendNativeMessage(
            hostName: hostName,
            message: .object(["kind": .string("missingPermission")])
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.lastErrorCode, .missingNativeMessagingPermission)
        XCTAssertFalse(result.lifecycle.processLaunchAttempted)
    }

    func testProductHostRootsAreRecordedButNotScanned()
        throws
    {
        let owner = ChromeMV3NativeMessagingRuntimeOwner(
            configuration: .internalFixture(
                extensionID: extensionID,
                profileID: "profile-a",
                fixtureHostRootPaths: [],
                explicitInternalNativeMessagingBridgeAllowed: false
            )
        )

        let lookup = owner.lookupPolicy().lookupHost(named: hostName)

        XCTAssertEqual(lookup.status, .missing)
        XCTAssertTrue(lookup.checkedLocations.isEmpty)
        XCTAssertFalse(lookup.futureLocationsRecorded.isEmpty)
        XCTAssertFalse(lookup.arbitrarySystemScanPerformed)
    }

    func testArbitraryAbsoluteHostPathOutsideFixtureRootIsRejected()
        throws
    {
        let root = try temporaryDirectory(named: "absolute-path-rejected")
        try writeManifest(
            root: root,
            hostName: hostName,
            executablePath: "/bin/echo",
            extensionID: extensionID
        )
        let owner = makeOwner(root: root)

        let result = owner.sendNativeMessage(
            hostName: hostName,
            message: .object(["kind": .string("absolute")])
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.lastErrorCode, .invalidExecutablePath)
        XCTAssertFalse(result.launchPolicy.processLaunchAllowedForFixtureHost)
        XCTAssertTrue(
            result.launchPolicy.diagnostics.contains {
                $0.contains("escapes explicit fixture roots")
            }
        )
    }

    func testSymlinkEscapingFixtureRootIsRejected()
        throws
    {
        let root = try temporaryDirectory(named: "symlink-root")
        let outside = try temporaryDirectory(named: "symlink-outside")
        let outsideExecutable = outside.appendingPathComponent("host.py")
        try """
        #!/usr/bin/python3
        import sys
        sys.exit(0)
        """.write(to: outsideExecutable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: outsideExecutable.path
        )
        let symlink = root.appendingPathComponent("escaped-host.py")
        try FileManager.default.createSymbolicLink(
            at: symlink,
            withDestinationURL: outsideExecutable
        )
        try writeManifest(
            root: root,
            hostName: hostName,
            executablePath: symlink.path,
            extensionID: extensionID
        )
        let owner = makeOwner(root: root)

        let result = owner.sendNativeMessage(
            hostName: hostName,
            message: .object(["kind": .string("symlink")])
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.lastErrorCode, .invalidExecutablePath)
        XCTAssertFalse(result.launchPolicy.processLaunchAllowedForFixtureHost)
    }

    func testEchoFixtureSendNativeMessageReturnsResponse()
        throws
    {
        let root = try temporaryDirectory(named: "send-echo")
        _ = try writeFixture(kind: .echo, root: root)
        let owner = makeOwner(root: root)

        let result = owner.sendNativeMessage(
            hostName: hostName,
            message: .object(["kind": .string("sendNativeMessage")])
        )
        let response = object(result.response)

        XCTAssertTrue(result.succeeded, result.diagnostics.joined(separator: "\n"))
        XCTAssertEqual(response?["ok"], .bool(true))
        XCTAssertEqual(
            object(response?["echo"])?["kind"],
            .string("sendNativeMessage")
        )
        XCTAssertEqual(
            response?["origin"],
            .string(
                ChromeMV3NativeMessagingAllowedOrigin.originString(
                    extensionID: extensionID
                )
            )
        )
        XCTAssertEqual(result.lifecycle.messageSentCount, 1)
        XCTAssertEqual(result.lifecycle.messageReceivedCount, 1)
        XCTAssertFalse(result.lifecycle.processLaunchAllowedInProduct)
    }

    func testMalformedFrameHostMapsToDeterministicLastError()
        throws
    {
        let root = try temporaryDirectory(named: "malformed-frame")
        _ = try writeFixture(kind: .malformedFrame, root: root)
        let owner = makeOwner(root: root)

        let result = owner.sendNativeMessage(
            hostName: hostName,
            message: .object(["kind": .string("malformed")])
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.lastErrorCode, .truncatedFrame)
        XCTAssertEqual(result.lifecycle.disconnectReason, .malformedFrame)
    }

    func testOversizedOutboundMessageIsRejectedByFramingCodec()
        throws
    {
        let policy = ChromeMV3NativeMessagingFramingPolicy(
            lengthPrefixBytes: 4,
            lengthPrefixByteOrder: "native-endian",
            payloadEncoding: "JSON UTF-8",
            inboundHostMessageLimitBytes: 1_048_576,
            outboundHostMessageLimitBytes: 8,
            serializesNow: false,
            readsPipesNow: false,
            diagnostics: []
        )

        let result = ChromeMV3NativeMessagingFramingCodec
            .encodeOutboundMessage(.string("0123456789"), policy: policy)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.error?.code, .oversizedMessage)
        XCTAssertEqual(result.maximumPayloadBytes, 8)
    }

    func testOversizedInboundResponseIsRejected()
        throws
    {
        let root = try temporaryDirectory(named: "oversized-inbound")
        _ = try writeFixture(kind: .oversizedResponse, root: root)
        let owner = makeOwner(root: root)

        let result = owner.sendNativeMessage(
            hostName: hostName,
            message: .object(["kind": .string("oversized")])
        )

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.lastErrorCode, .oversizedMessage)
        XCTAssertEqual(result.lifecycle.disconnectReason, .oversizedMessage)
    }

    func testInvalidJSONAndCrashEarlyExitMapDeterministically()
        throws
    {
        let invalidRoot = try temporaryDirectory(named: "invalid-json")
        _ = try writeFixture(kind: .invalidJSON, root: invalidRoot)
        let invalid = makeOwner(root: invalidRoot).sendNativeMessage(
            hostName: hostName,
            message: .object(["kind": .string("invalidJSON")])
        )

        let crashRoot = try temporaryDirectory(named: "crash")
        _ = try writeFixture(kind: .crashEarlyExit, root: crashRoot)
        let crash = makeOwner(root: crashRoot).sendNativeMessage(
            hostName: hostName,
            message: .object(["kind": .string("crash")])
        )

        XCTAssertFalse(invalid.succeeded)
        XCTAssertEqual(invalid.lastErrorCode, .invalidJSON)
        XCTAssertEqual(invalid.lifecycle.disconnectReason, .malformedFrame)
        XCTAssertFalse(crash.succeeded)
        XCTAssertEqual(crash.lastErrorCode, .hostCrashedOrExited)
        XCTAssertEqual(crash.lifecycle.disconnectReason, .nativeHostExited)
    }

    func testConnectNativePortPostMessageAndDisconnectLifecycle()
        throws
    {
        let root = try temporaryDirectory(named: "connect-port")
        _ = try writeFixture(kind: .echo, root: root)
        let owner = makeOwner(root: root)

        let connect = owner.connectNative(hostName: hostName)
        let portID = try XCTUnwrap(connect.portID)
        let post = owner.postMessage(
            portID: portID,
            message: .object(["kind": .string("portMessage")])
        )
        let disconnect = owner.disconnect(
            portID: portID,
            reason: .nativeHostExited
        )
        let response = object(post.response)

        XCTAssertTrue(connect.succeeded, connect.diagnostics.joined(separator: "\n"))
        XCTAssertEqual(owner.activePortCount, 0)
        XCTAssertTrue(post.succeeded, post.diagnostics.joined(separator: "\n"))
        XCTAssertEqual(response?["ok"], .bool(true))
        XCTAssertEqual(object(response?["echo"])?["kind"], .string("portMessage"))
        XCTAssertTrue(disconnect.disconnected)
        XCTAssertEqual(disconnect.activePortCountAfterDisconnect, 0)
        XCTAssertEqual(disconnect.reason, .nativeHostExited)
    }

    func testExtensionDisableAndProfileCloseTearDownNativePorts()
        throws
    {
        let disableRoot = try temporaryDirectory(named: "disable-teardown")
        _ = try writeFixture(kind: .echo, root: disableRoot)
        let disableOwner = makeOwner(root: disableRoot)
        let first = disableOwner.connectNative(hostName: hostName)
        let second = disableOwner.connectNative(hostName: hostName)
        XCTAssertNotNil(first.portID)
        XCTAssertNotNil(second.portID)
        XCTAssertEqual(disableOwner.activePortCount, 2)

        let disabled = disableOwner.tearDownForExtensionDisable()

        XCTAssertEqual(disabled.count, 2)
        XCTAssertTrue(disabled.allSatisfy { $0.reason == .extensionDisabled })
        XCTAssertEqual(disableOwner.activePortCount, 0)

        let profileRoot = try temporaryDirectory(named: "profile-teardown")
        _ = try writeFixture(kind: .echo, root: profileRoot)
        let profileOwner = makeOwner(root: profileRoot)
        XCTAssertNotNil(profileOwner.connectNative(hostName: hostName).portID)

        let closed = profileOwner.tearDownForProfileClose()

        XCTAssertEqual(closed.count, 1)
        XCTAssertEqual(closed.first?.reason, .profileClosed)
        XCTAssertEqual(profileOwner.activePortCount, 0)
    }

    func testImplementationReportMarksFixtureReadyAndProductUnavailable()
        throws
    {
        let root = try temporaryDirectory(named: "implementation-report")

        let report = try ChromeMV3NativeMessagingImplementationReportGenerator
            .makeReport(
                extensionID: extensionID,
                profileID: "profile-report",
                fixtureHostRootURL: root
            )

        XCTAssertTrue(report.nativeMessagingAvailableInInternalFixture)
        XCTAssertEqual(report.fixturePack.records.count, 4)
        XCTAssertEqual(report.fixturePack.generatedState, .generated)
        XCTAssertEqual(report.fixturePack.validatedState, .valid)
        XCTAssertTrue(report.fixturePack.noNetworkInvariant)
        XCTAssertTrue(report.fixturePack.noCredentialsInvariant)
        XCTAssertTrue(report.processLaunchAllowedForFixtureHost)
        XCTAssertTrue(report.passwordManagerNativeMessagingReadyInFixture)
        XCTAssertFalse(report.nativeMessagingAvailableInProduct)
        XCTAssertFalse(report.processLaunchAllowedInProduct)
        XCTAssertFalse(report.passwordManagerProductRuntimeReady)
        XCTAssertFalse(report.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(report.serviceWorkerWakeAvailable)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertTrue(report.sendNativeMessageResult.succeeded)
        XCTAssertTrue(report.connectNativeResult.succeeded)
        XCTAssertTrue(report.nativePortPostMessageResult?.succeeded == true)
        XCTAssertTrue(report.nativePortDisconnectResult?.disconnected == true)
        XCTAssertEqual(report.malformedFrameResult?.lastErrorCode, .truncatedFrame)
        XCTAssertEqual(report.oversizedInboundResult?.lastErrorCode, .oversizedMessage)
        XCTAssertEqual(report.crashEarlyExitResult?.lastErrorCode, .hostCrashedOrExited)
    }

    private func writeFixture(
        kind: ChromeMV3NativeMessagingFixtureHostKind,
        root: URL
    ) throws -> ChromeMV3NativeMessagingFixtureHost {
        try ChromeMV3NativeMessagingFixtureHostBuilder.writeFixtureHost(
            kind: kind,
            rootURL: root,
            hostName: hostName,
            extensionID: extensionID
        )
    }

    private func writeManifest(
        root: URL,
        hostName: String,
        executablePath: String,
        extensionID: String
    ) throws {
        let object: [String: Any] = [
            "allowed_origins": [
                ChromeMV3NativeMessagingAllowedOrigin.originString(
                    extensionID: extensionID
                ),
            ],
            "description": "Sumi native messaging fixture",
            "name": hostName,
            "path": executablePath,
            "type": "stdio",
        ]
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: root.appendingPathComponent("\(hostName).json"))
    }

    private func makeOwner(
        root: URL,
        hostName: String? = nil,
        extensionID: String? = nil,
        permissionState: ChromeMV3NativeMessagingPermissionState =
            .grantedByManifest,
        includeTrustedHostApproval: Bool = true
    ) -> ChromeMV3NativeMessagingRuntimeOwner {
        let resolvedExtensionID = extensionID ?? self.extensionID
        let resolvedHostName = hostName ?? self.hostName
        let trustedRecords: [ChromeMV3NativeTrustedHostApprovalRecord]
        if includeTrustedHostApproval {
            let lookupPolicy = ChromeMV3NativeHostLookupPolicy.macOS(
                explicitTestRootPath: root.path
            )
            trustedRecords = [
                ChromeMV3NativeTrustedHostPolicyFactory
                    .recordForExplicitDeveloperPreviewApproval(
                        hostName: resolvedHostName,
                        extensionID: resolvedExtensionID,
                        profileID: "profile-a",
                        lookupPolicy: lookupPolicy,
                        permissionState: permissionState,
                        approvedRootPaths: [root.path],
                        sequence: 1,
                        now: Date(timeIntervalSince1970: 1)
                    )
                    .record,
            ]
        } else {
            trustedRecords = []
        }
        return ChromeMV3NativeMessagingRuntimeOwner(
            configuration: .internalFixture(
                extensionID: resolvedExtensionID,
                profileID: "profile-a",
                fixtureHostRootPaths: [root.path],
                permissionState: permissionState,
                trustedHostApprovalRecords: trustedRecords
            )
        )
    }

    @MainActor
    private func makeModule(enabled: Bool) throws -> SumiExtensionsModule {
        let defaults = UserDefaults(
            suiteName:
                "ChromeMV3NativeMessagingInternalRuntimeTests.\(UUID().uuidString)"
        )!
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.setEnabled(enabled, for: .extensions)
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration()
        )
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ChromeMV3NativeMessagingInternalRuntimeTests",
                isDirectory: true
            )
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(root.deletingLastPathComponent())
        return root.standardizedFileURL
    }

    private func object(_ value: ChromeMV3StorageValue?)
        -> [String: ChromeMV3StorageValue]?
    {
        guard case .object(let object) = value else { return nil }
        return object
    }
}
