import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3NativeMessagingSecurityTests: XCTestCase {
    private let allowedExtensionID = "abcdefghijklmnopabcdefghijklmnop"
    private let otherExtensionID = "ponmlkjihgfedcbaponmlkjihgfedcba"
    private let hostName = "com.example.native_host"

    func testNativeHostManifestValidFixtureParsesDeterministically() throws {
        let data = try manifestData()
        let source = ChromeMV3NativeHostManifestSourceLocation
            .explicitTestRoot(
                rootPath: "/tmp/native-hosts",
                hostName: hostName
            )

        let first = ChromeMV3NativeHostManifestDecoder.decode(
            data: data,
            sourceLocation: source,
            requestedHostName: hostName
        )
        let second = ChromeMV3NativeHostManifestDecoder.decode(
            data: data,
            sourceLocation: source,
            requestedHostName: hostName
        )

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.isValid)
        XCTAssertEqual(first.name, hostName)
        XCTAssertEqual(first.type, "stdio")
        XCTAssertEqual(first.allowedOrigins.first?.extensionID, allowedExtensionID)
        XCTAssertNotNil(first.rawJSONSHA256)
        XCTAssertNotNil(first.canonicalJSONSHA256)
    }

    func testMissingHostManifestIsDiagnosed() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let policy = ChromeMV3NativeHostLookupPolicy.macOS(
            explicitTestRootPath: root.path
        )

        let result = policy.lookupHost(named: hostName)

        XCTAssertEqual(result.status, .missing)
        XCTAssertFalse(result.arbitrarySystemScanPerformed)
        XCTAssertTrue(result.manifest == nil)
        XCTAssertTrue(
            result.diagnostics.contains {
                $0.contains("No native host manifest")
            }
        )
    }

    func testInvalidHostNameIsDiagnosedBeforeLookup() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let policy = ChromeMV3NativeHostLookupPolicy.macOS(
            explicitTestRootPath: root.path
        )

        let result = policy.lookupHost(named: ".bad..host")

        XCTAssertEqual(result.status, .invalidHostName)
        XCTAssertTrue(result.checkedLocations.isEmpty)
        XCTAssertFalse(result.arbitrarySystemScanPerformed)
    }

    func testMissingPathIsDiagnosed() throws {
        var object = validManifestObject()
        object.removeValue(forKey: "path")

        let manifest = decode(object)

        XCTAssertFalse(manifest.isValid)
        XCTAssertTrue(
            manifest.validationSummary.errorCodes.contains(.missingPath)
        )
    }

    func testUnsupportedTypeIsDiagnosed() throws {
        var object = validManifestObject()
        object["type"] = "socket"

        let manifest = decode(object)

        XCTAssertFalse(manifest.isValid)
        XCTAssertTrue(
            manifest.validationSummary.errorCodes.contains(.unsupportedType)
        )
    }

    func testMalformedAllowedOriginIsDiagnosed() throws {
        var object = validManifestObject()
        object["allowed_origins"] = ["chrome-extension://*/"]

        let manifest = decode(object)

        XCTAssertFalse(manifest.isValid)
        XCTAssertTrue(
            manifest.validationSummary.errorCodes.contains(
                .malformedAllowedOrigin
            )
        )
    }

    func testUnsafePathAndUnknownFieldsAreDiagnosed() throws {
        var object = validManifestObject()
        object["path"] = "../bin/native-host"
        object["extra"] = true
        object["platforms"] = ["mac"]

        let manifest = decode(object)

        XCTAssertFalse(manifest.isValid)
        XCTAssertTrue(manifest.validationSummary.errorCodes.contains(.unsafePath))
        XCTAssertTrue(
            manifest.validationSummary.warningCodes.contains(
                .unknownFieldIgnored
            )
        )
        XCTAssertTrue(
            manifest.validationSummary.warningCodes.contains(
                .unsupportedPlatformField
            )
        )
    }

    func testExplicitRootLookupFindsFixtureWithoutSystemScan() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeManifest(to: root)
        let policy = ChromeMV3NativeHostLookupPolicy.macOS(
            explicitTestRootPath: root.path
        )

        let result = policy.lookupHost(named: hostName)

        XCTAssertEqual(result.status, .found)
        XCTAssertTrue(result.manifest?.isValid == true)
        XCTAssertEqual(result.checkedLocations.count, 1)
        XCTAssertFalse(result.futureLocationsRecorded.isEmpty)
        XCTAssertFalse(result.arbitrarySystemScanPerformed)
        XCTAssertTrue(
            result.futureLocationsRecorded.allSatisfy {
                $0.lookupAllowedInThisModel == false
            }
        )
    }

    func testNoArbitrarySystemScanIsPerformedWithoutExplicitRoot() {
        let policy = ChromeMV3NativeHostLookupPolicy.macOS()

        let result = policy.lookupHost(named: hostName)

        XCTAssertEqual(result.status, .missing)
        XCTAssertTrue(result.checkedLocations.isEmpty)
        XCTAssertFalse(result.futureLocationsRecorded.isEmpty)
        XCTAssertFalse(result.arbitrarySystemScanPerformed)
    }

    func testAllowedOriginAuthorizesMatchingExtensionID() throws {
        let manifest = decode(validManifestObject())
        let result = ChromeMV3NativeMessagingAuthorizationEvaluator.evaluate(
            extensionID: allowedExtensionID,
            permissionState: .grantedByManifest,
            hostManifest: manifest,
            productPolicy: productPolicy(userConsentRequired: false)
        )

        XCTAssertTrue(result.authorizedByManifest)
        XCTAssertTrue(result.hasNativeMessagingPermission)
        XCTAssertFalse(result.blockedByHostManifest)
        XCTAssertFalse(result.requiresUserConsent)
        XCTAssertFalse(result.canConnectNativeNow)
    }

    func testNonMatchingExtensionIDIsBlockedByHostManifest() throws {
        let manifest = decode(validManifestObject())

        let result = ChromeMV3NativeMessagingAuthorizationEvaluator.evaluate(
            extensionID: otherExtensionID,
            permissionState: .grantedByManifest,
            hostManifest: manifest,
            productPolicy: productPolicy(userConsentRequired: false)
        )

        XCTAssertFalse(result.authorizedByManifest)
        XCTAssertTrue(result.blockedByHostManifest)
        XCTAssertFalse(result.canConnectNativeNow)
    }

    func testMissingDeniedDeferredAndUnsupportedPermissionStatesBlockConnection()
        throws
    {
        let manifest = decode(validManifestObject())

        for state in [
            ChromeMV3NativeMessagingPermissionState.missing,
            .denied,
            .deferred,
            .unsupported,
        ] {
            let result = ChromeMV3NativeMessagingAuthorizationEvaluator
                .evaluate(
                    extensionID: allowedExtensionID,
                    permissionState: state,
                    hostManifest: manifest,
                    productPolicy: productPolicy(userConsentRequired: false)
                )

            XCTAssertFalse(result.hasNativeMessagingPermission, state.rawValue)
            XCTAssertTrue(result.blockedByMissingPermission, state.rawValue)
            XCTAssertFalse(result.canConnectNativeNow, state.rawValue)
        }
    }

    func testLongLivedNativePortPreflightKeepsRuntimeBlocked() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeManifest(to: root)
        let policy = ChromeMV3NativeHostLookupPolicy.macOS(
            explicitTestRootPath: root.path
        )
        let preflight = makePreflight(
            operationKind: .longLivedNativePort,
            lookupPolicy: policy
        )

        XCTAssertEqual(preflight.hostLookupResult.status, .found)
        XCTAssertTrue(preflight.authorizationResult.authorizedByManifest)
        XCTAssertFalse(preflight.canConnectNativeNow)
        XCTAssertFalse(preflight.processLaunchAllowedNow)
        XCTAssertFalse(preflight.canOpenPortNow)
        XCTAssertFalse(preflight.canWakeServiceWorkerNow)
        XCTAssertFalse(preflight.canLoadContextNow)
        XCTAssertFalse(preflight.runtimeLoadable)
        XCTAssertFalse(preflight.nativeMessagingRuntimeImplemented)
    }

    func testOneShotNativeMessagePreflightKeepsRuntimeBlocked() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeManifest(to: root)
        let policy = ChromeMV3NativeHostLookupPolicy.macOS(
            explicitTestRootPath: root.path
        )
        let preflight = makePreflight(
            operationKind: .oneShotNativeMessage,
            lookupPolicy: policy
        )

        XCTAssertEqual(preflight.hostLookupResult.status, .found)
        XCTAssertFalse(preflight.canSendNativeMessageNow)
        XCTAssertFalse(preflight.processLaunchAllowedNow)
        XCTAssertFalse(preflight.canOpenPortNow)
        XCTAssertFalse(preflight.canWakeServiceWorkerNow)
        XCTAssertFalse(preflight.canLoadContextNow)
        XCTAssertFalse(preflight.runtimeLoadable)
    }

    func testApprovedTrustedFixtureHostAllowsPreflightButNotRuntimeLoadable()
        throws
    {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try ChromeMV3NativeMessagingFixtureHostBuilder.writeFixtureHost(
            kind: .echo,
            rootURL: root,
            hostName: hostName,
            extensionID: allowedExtensionID
        )
        let policy = ChromeMV3NativeHostLookupPolicy.macOS(
            explicitTestRootPath: root.path
        )
        let approval = ChromeMV3NativeTrustedHostPolicyFactory
            .recordForExplicitDeveloperPreviewApproval(
                hostName: hostName,
                extensionID: allowedExtensionID,
                profileID: "profile-a",
                lookupPolicy: policy,
                permissionState: .grantedByManifest,
                approvedRootPaths: [root.path],
                sequence: 1,
                now: Date(timeIntervalSince1970: 1)
            )
            .record
        let connect = makePreflight(
            operationKind: .longLivedNativePort,
            lookupPolicy: policy,
            trustedHostPolicyRecord: approval
        )
        let send = makePreflight(
            operationKind: .oneShotNativeMessage,
            lookupPolicy: policy,
            trustedHostPolicyRecord: approval
        )

        XCTAssertTrue(approval.trustedForDeveloperPreview)
        XCTAssertTrue(connect.trustedHostPolicyApproved)
        XCTAssertTrue(connect.canConnectNativeNow)
        XCTAssertFalse(connect.canSendNativeMessageNow)
        XCTAssertTrue(send.canSendNativeMessageNow)
        XCTAssertFalse(send.canConnectNativeNow)
        XCTAssertTrue(connect.processLaunchAllowedNow)
        XCTAssertFalse(connect.runtimeLoadable)
        XCTAssertFalse(connect.canWakeServiceWorkerNow)
    }

    func testPermissionGrantAndHostApprovalRemainSeparate()
        throws
    {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try ChromeMV3NativeMessagingFixtureHostBuilder.writeFixtureHost(
            kind: .echo,
            rootURL: root,
            hostName: hostName,
            extensionID: allowedExtensionID
        )
        let policy = ChromeMV3NativeHostLookupPolicy.macOS(
            explicitTestRootPath: root.path
        )
        let approval = ChromeMV3NativeTrustedHostPolicyFactory
            .recordForExplicitDeveloperPreviewApproval(
                hostName: hostName,
                extensionID: allowedExtensionID,
                profileID: "profile-a",
                lookupPolicy: policy,
                permissionState: .grantedByManifest,
                approvedRootPaths: [root.path],
                sequence: 1,
                now: Date(timeIntervalSince1970: 1)
            )
            .record
        let permissionOnly = makePreflight(
            operationKind: .longLivedNativePort,
            lookupPolicy: policy
        )
        let approvalOnly = ChromeMV3NativeMessagingPreflightEvaluator
            .evaluate(
                input: ChromeMV3NativeMessagingPreflightInput(
                    extensionID: allowedExtensionID,
                    profileID: "profile-a",
                    hostName: hostName,
                    operationKind: .longLivedNativePort,
                    sourceContext: .serviceWorker,
                    permissionState: .missing,
                    productPolicy:
                        productPolicy(userConsentRequired: true),
                    trustedHostPolicyRecord: approval
                ),
                lookupPolicy: policy
            )

        XCTAssertFalse(permissionOnly.trustedHostPolicyApproved)
        XCTAssertFalse(permissionOnly.canConnectNativeNow)
        XCTAssertTrue(approvalOnly.trustedHostPolicyApproved)
        XCTAssertFalse(approvalOnly.authorizationResult.hasNativeMessagingPermission)
        XCTAssertFalse(approvalOnly.canConnectNativeNow)
    }

    func testDeniedRevokedAndDiscoveryPolicyStayBlocked()
        throws
    {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try ChromeMV3NativeMessagingFixtureHostBuilder.writeFixtureHost(
            kind: .echo,
            rootURL: root,
            hostName: hostName,
            extensionID: allowedExtensionID
        )
        let policy = ChromeMV3NativeHostLookupPolicy.macOS(
            explicitTestRootPath: root.path
        )
        let lookup = policy.lookupHost(named: hostName)
        let auth = ChromeMV3NativeMessagingAuthorizationEvaluator.evaluate(
            extensionID: allowedExtensionID,
            permissionState: .grantedByManifest,
            hostManifest: lookup.manifest,
            productPolicy: productPolicy(userConsentRequired: true)
        )
        let denied = ChromeMV3NativeTrustedHostPolicyEvaluator.evaluate(
            hostName: hostName,
            extensionID: allowedExtensionID,
            profileID: "profile-a",
            lookupResult: lookup,
            authorizationResult: auth,
            approvedRootPaths: [root.path],
            control: .deny,
            sequence: 1,
            now: Date(timeIntervalSince1970: 1)
        )
        let revoked = ChromeMV3NativeTrustedHostPolicyEvaluator.evaluate(
            hostName: hostName,
            extensionID: allowedExtensionID,
            profileID: "profile-a",
            lookupResult: lookup,
            authorizationResult: auth,
            approvedRootPaths: [root.path],
            control: .revoke,
            sequence: 2,
            now: Date(timeIntervalSince1970: 2)
        )
        let deniedPreflight = makePreflight(
            operationKind: .longLivedNativePort,
            lookupPolicy: policy,
            trustedHostPolicyRecord: denied.record
        )
        let revokedPreflight = makePreflight(
            operationKind: .longLivedNativePort,
            lookupPolicy: policy,
            trustedHostPolicyRecord: revoked.record
        )
        let discovery = ChromeMV3NativeHostDiscoveryPolicyReport.make(
            lookupPolicy: policy,
            requestedHostNames: [hostName]
        )

        XCTAssertEqual(denied.record.trustState, .userDenied)
        XCTAssertEqual(revoked.record.trustState, .revoked)
        XCTAssertFalse(deniedPreflight.canConnectNativeNow)
        XCTAssertFalse(revokedPreflight.canConnectNativeNow)
        XCTAssertFalse(discovery.arbitrarySystemScanPerformed)
        XCTAssertFalse(discovery.nativeHostScanningAllowed)
        XCTAssertTrue(discovery.roots.allSatisfy { $0.hostsFound.isEmpty })
    }

    func testDisabledModuleBlocksNativeMessagingPreflight() {
        let lookupPolicy = ChromeMV3NativeHostLookupPolicy.macOS(
            extensionModuleEnabled: false
        )
        let preflight = makePreflight(
            operationKind: .longLivedNativePort,
            lookupPolicy: lookupPolicy,
            productPolicy: productPolicy(
                extensionModuleEnabled: false,
                userConsentRequired: false
            )
        )

        XCTAssertEqual(preflight.hostLookupResult.status, .disabledModule)
        XCTAssertTrue(preflight.authorizationResult.blockedByDisabledModule)
        XCTAssertFalse(preflight.canConnectNativeNow)
        XCTAssertFalse(preflight.processLaunchAllowedNow)
    }

    func testMessageFramingPolicyIsDeterministicAndDiagnosesOversize() {
        let policy = ChromeMV3NativeMessagingFramingPolicy.chromeStdioJSON

        let valid = policy.validateFrame(
            declaredPayloadLength: 2,
            actualPayloadByteCount: 2,
            direction: .inboundFromHost
        )
        let oversized = policy.validateFrame(
            declaredPayloadLength: policy.inboundHostMessageLimitBytes + 1,
            actualPayloadByteCount: policy.inboundHostMessageLimitBytes + 1,
            direction: .inboundFromHost
        )

        XCTAssertEqual(policy.lengthPrefixBytes, 4)
        XCTAssertEqual(policy.inboundHostMessageLimitBytes, 1_048_576)
        XCTAssertEqual(policy.outboundHostMessageLimitBytes, 67_108_864)
        XCTAssertTrue(valid.valid)
        XCTAssertFalse(oversized.valid)
        XCTAssertTrue(
            oversized.diagnostics.contains {
                $0.code == .oversizedMessage
            }
        )
    }

    func testNativePortLifecycleIsModeledButNoPortOpens() {
        let lifecycle = ChromeMV3NativeMessagingPortLifecycleContract.model(
            operationID: "operation-a",
            operationKind: .longLivedNativePort,
            hostName: hostName,
            extensionID: allowedExtensionID,
            profileID: "profile-a"
        )

        XCTAssertEqual(lifecycle.portKind, .nativeMessaging)
        XCTAssertTrue(lifecycle.futurePortWouldBeLongLived)
        XCTAssertFalse(lifecycle.canOpenPortNow)
        XCTAssertFalse(lifecycle.keepaliveStartsNow)
        XCTAssertFalse(lifecycle.processLaunchAllowedNow)
        XCTAssertFalse(lifecycle.portLifecycleImplemented)
        XCTAssertEqual(
            Set(lifecycle.disconnectReasons),
            Set(ChromeMV3NativeMessagingDisconnectReason.allCases)
        )
    }

    func testServiceWorkerKeepaliveImplicationIsModeledButNoWakeStarts()
        throws
    {
        let preflight = makePreflight(
            operationKind: .longLivedNativePort,
            lookupPolicy: .macOS()
        )
        let keepalive = preflight.serviceWorkerKeepaliveImplication

        XCTAssertEqual(keepalive.kind, .nativeMessagingPort)
        XCTAssertTrue(keepalive.wouldKeepAliveInFuture)
        XCTAssertFalse(keepalive.implementedNow)
        XCTAssertFalse(preflight.canWakeServiceWorkerNow)
        XCTAssertTrue(
            keepalive.blockers.contains {
                $0.contains("Native messaging keepalive")
            }
        )
    }

    func testPasswordManagerLikeFixtureReportsNativeMessagingBlockers()
        throws
    {
        let report = ChromeMV3NativeMessagingReadinessReportGenerator
            .makeReport(
                extensionID: allowedExtensionID,
                profileID: "profile-a",
                nativeMessagingPermissionDetected: true,
                permissionState: .deferred,
                requestedHostName: nil,
                passwordManagerLikeFixtureDetected: true
            )
        let password = report.passwordManagerNativeMessagingSummary

        XCTAssertTrue(password.nativeMessagingPermissionDetected)
        XCTAssertFalse(password.expectedHostNameKnown)
        XCTAssertTrue(password.hostManifestRequired)
        XCTAssertTrue(password.hostAuthorizationRequired)
        XCTAssertTrue(password.nativePortRequiredForUnlockFillFlow)
        XCTAssertTrue(password.serviceWorkerKeepaliveNeededButBlocked)
        XCTAssertFalse(password.processLaunchImplemented)
        XCTAssertFalse(password.passwordManagerNativeMessagingReady)
    }

    func testNativeMessagingReadinessReportKeepsAllRuntimeFlagsFalse()
        throws
    {
        let first = ChromeMV3NativeMessagingReadinessReportGenerator.makeReport(
            extensionID: allowedExtensionID,
            profileID: "profile-a",
            nativeMessagingPermissionDetected: true,
            permissionState: .deferred,
            requestedHostName: hostName,
            passwordManagerLikeFixtureDetected: true
        )
        let second = ChromeMV3NativeMessagingReadinessReportGenerator.makeReport(
            extensionID: allowedExtensionID,
            profileID: "profile-a",
            nativeMessagingPermissionDetected: true,
            permissionState: .deferred,
            requestedHostName: hostName,
            passwordManagerLikeFixtureDetected: true
        )
        let firstData = try ChromeMV3DeterministicJSON.encodedData(first)
        let secondData = try ChromeMV3DeterministicJSON.encodedData(second)

        XCTAssertEqual(first, second)
        XCTAssertEqual(firstData, secondData)
        XCTAssertFalse(first.canConnectNativeNow)
        XCTAssertFalse(first.canSendNativeMessageNow)
        XCTAssertFalse(first.processLaunchAllowedNow)
        XCTAssertFalse(first.canOpenPortNow)
        XCTAssertFalse(first.canWakeServiceWorkerNow)
        XCTAssertFalse(first.canLoadContextNow)
        XCTAssertFalse(first.runtimeLoadable)
        XCTAssertFalse(
            first.passwordManagerNativeMessagingSummary
                .passwordManagerNativeMessagingReady
        )
    }

    func testNativeMessagingReadinessReportWriterWritesExpectedFile()
        throws
    {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let report = ChromeMV3NativeMessagingReadinessReportGenerator
            .makeReport(
                extensionID: allowedExtensionID,
                profileID: "profile-a",
                nativeMessagingPermissionDetected: true,
                permissionState: .deferred,
                requestedHostName: hostName
            )

        try ChromeMV3NativeMessagingReadinessReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )

        let reportURL = root.appendingPathComponent(
            ChromeMV3NativeMessagingReadinessReportWriter.reportFileName
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        let decoded = try JSONDecoder().decode(
            ChromeMV3NativeMessagingReadinessReport.self,
            from: Data(contentsOf: reportURL)
        )
        XCTAssertEqual(decoded, report)
    }

    @MainActor
    func testSumiExtensionsModuleWritesNativeMessagingReportOnlyWhenEnabled()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 module diagnostics require macOS 15.5.")
        }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ChromeMV3RuntimeBridgePrerequisitesReportWriter.write(
            makePrerequisitesReport(root: root),
            toRewrittenBundleRoot: root
        )
        let reportURL = root.appendingPathComponent(
            ChromeMV3NativeMessagingReadinessReportWriter.reportFileName
        )
        let disabledHarness = TestDefaultsHarness()
        defer { disabledHarness.reset() }
        let disabledRegistry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: disabledHarness.defaults)
        )
        let disabledModule = SumiExtensionsModule(
            moduleRegistry: disabledRegistry,
            browserConfiguration: BrowserConfiguration()
        )

        let disabledReport =
            disabledModule.chromeMV3NativeMessagingReadinessReportIfEnabled(
                fromRewrittenBundleRoot: root,
                requestedHostName: hostName,
                writeReport: true
            )

        XCTAssertNil(disabledReport)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportURL.path))

        let enabledHarness = TestDefaultsHarness()
        defer { enabledHarness.reset() }
        let enabledRegistry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: enabledHarness.defaults)
        )
        enabledRegistry.enable(.extensions)
        let enabledModule = SumiExtensionsModule(
            moduleRegistry: enabledRegistry,
            browserConfiguration: BrowserConfiguration()
        )

        let enabledReport = try XCTUnwrap(
            enabledModule.chromeMV3NativeMessagingReadinessReportIfEnabled(
                fromRewrittenBundleRoot: root,
                requestedHostName: hostName,
                writeReport: true
            )
        )
        let diagnostics = enabledModule.chromeMV3InventoryDiagnosticsIfEnabled(
            rootURL: root
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertEqual(
            diagnostics?.nativeMessagingReadinessReportSummary,
            enabledReport.summary
        )
        XCTAssertFalse(enabledModule.hasLoadedRuntime)
    }

    func testSourceLevelGuardsForNativeMessagingSecurityLayer() throws {
        let sources = try Self.sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
            "SumiTests",
        ])
        .filter {
            $0.relativePath.hasPrefix("Sumi/Models/Extension/ChromeMV3/")
                || $0.relativePath.hasPrefix("SumiTests/ChromeMV3")
        }
        let productSourceJoined = sources
            .filter {
                $0.relativePath.hasPrefix(
                    "Sumi/Models/Extension/ChromeMV3/"
                )
            }
            .map(\.contents)
            .joined(separator: "\n")
        let boundaryGuardJoined = sources
            .filter {
                $0.relativePath
                    != "Sumi/Models/Extension/ChromeMV3/ChromeMV3TabsScriptingJSMVP.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3StorageLocalRuntime.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerSyntheticFixture.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionEventAPIsRuntime.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3SidePanelOffscreenIdentitySyntheticWebKitHarness.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3NativeMessagingInternalRuntime.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3PopupOptionsJSBridge.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3ProductPopupOptionsUI.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3ContentScriptProductAttachment.swift"
            }
            .map(\.contents)
            .joined(separator: "\n")

        for forbidden in [
            "WKWebExtension" + "Context(",
            "load" + "ExtensionContext",
            "add" + "UserScript",
            "Pro" + "cess(",
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer",
        ] {
            XCTAssertFalse(boundaryGuardJoined.contains(forbidden), forbidden)
        }

        for forbiddenRegex in [
            "runtime" + "Loadable\\s*[:=].*" + "tr" + "ue",
            "canCreate" + "ContextNow\\s*[:=].*" + "tr" + "ue",
            "canLoad" + "ContextNow\\s*[:=].*" + "tr" + "ue",
            "nativeMessagingAvailableInPublicProduct\\s*[:=].*" + "tr"
                + "ue",
            "arbitraryHostLaunchAllowed\\s*[:=].*" + "tr" + "ue",
            "nativeHostScanningAllowed\\s*[:=].*" + "tr" + "ue",
            "productRuntimeAvailable\\s*[:=].*" + "tr" + "ue",
            "productRuntimeExposed\\s*[:=].*" + "tr" + "ue",
        ] {
            XCTAssertNil(
                productSourceJoined.range(
                    of: forbiddenRegex,
                    options: .regularExpression
                ),
                forbiddenRegex
            )
        }
    }

    private func makePreflight(
        operationKind: ChromeMV3NativeMessagingOperationKind,
        lookupPolicy: ChromeMV3NativeHostLookupPolicy,
        productPolicy: ChromeMV3NativeMessagingProductPolicy? = nil,
        trustedHostPolicyRecord:
            ChromeMV3NativeTrustedHostApprovalRecord? = nil
    ) -> ChromeMV3NativeMessagingOperationPreflight {
        ChromeMV3NativeMessagingPreflightEvaluator.evaluate(
            input: ChromeMV3NativeMessagingPreflightInput(
                extensionID: allowedExtensionID,
                profileID: "profile-a",
                hostName: hostName,
                operationKind: operationKind,
                sourceContext: .serviceWorker,
                permissionState: .grantedByManifest,
                productPolicy:
                    productPolicy ?? self.productPolicy(
                        userConsentRequired: false
                    ),
                trustedHostPolicyRecord: trustedHostPolicyRecord
            ),
            lookupPolicy: lookupPolicy
        )
    }

    private func decode(
        _ object: [String: Any]
    ) -> ChromeMV3NativeHostManifest {
        ChromeMV3NativeHostManifestDecoder.decode(
            object: object,
            sourceLocation:
                ChromeMV3NativeHostManifestSourceLocation.explicitTestRoot(
                    rootPath: "/tmp/native-hosts",
                    hostName: hostName
                ),
            rawHash: nil,
            requestedHostName: hostName
        )
    }

    private func writeManifest(to root: URL) throws {
        try manifestData().write(
            to: root.appendingPathComponent("\(hostName).json")
        )
    }

    private func manifestData() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: validManifestObject(),
            options: [.sortedKeys]
        )
    }

    private func validManifestObject() -> [String: Any] {
        [
            "name": hostName,
            "description": "Native host fixture",
            "path": "/usr/local/bin/sumi-native-host",
            "type": "stdio",
            "allowed_origins": [
                ChromeMV3NativeMessagingAllowedOrigin.originString(
                    extensionID: allowedExtensionID
                ),
            ],
        ]
    }

    private func productPolicy(
        extensionModuleEnabled: Bool = true,
        userConsentRequired: Bool
    ) -> ChromeMV3NativeMessagingProductPolicy {
        ChromeMV3NativeMessagingProductPolicy(
            extensionModuleEnabled: extensionModuleEnabled,
            nativeMessagingAllowedByProductPolicy: true,
            userConsentRequired: userConsentRequired,
            userConsentGranted: userConsentRequired == false
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makePrerequisitesReport(
        root: URL
    ) -> ChromeMV3RuntimeBridgePrerequisitesReport {
        ChromeMV3RuntimeBridgePrerequisitesReport(
            schemaVersion: 1,
            id: "runtime-prerequisites-native-messaging-test",
            reportFileName:
                ChromeMV3RuntimeBridgePrerequisitesReportWriter.reportFileName,
            candidateID: allowedExtensionID,
            generatedRewrittenRootPath: root.path,
            contextReadinessReportID: "context-readiness-test",
            contextReadinessReportPath:
                root.appendingPathComponent(
                    ChromeMV3ContextReadinessReportWriter.reportFileName
                ).path,
            contextReadinessReportHash: String(repeating: "a", count: 64),
            contextReadinessConsumerDiagnostic:
                ChromeMV3ContextReadinessReportConsumptionDiagnostic(
                    schemaVersion: 1,
                    reportFileName:
                        ChromeMV3ContextReadinessReportWriter.reportFileName,
                    reportPath:
                        root.appendingPathComponent(
                            ChromeMV3ContextReadinessReportWriter.reportFileName
                        ).path,
                    state: .ready,
                    canImplementRecommendedBranch: true,
                    nextRequiredPromptCategory:
                        .addRuntimeBridgePrerequisites,
                    rawNextRequiredPromptCategory:
                        "addRuntimeBridgePrerequisites",
                    allowedNextRequiredPromptCategories: [
                        "addRuntimeBridgePrerequisites",
                    ],
                    blockingReasons: [],
                    warnings: [],
                    requiredActions: []
                ),
            manifestFacts: manifestFacts(root: root),
            runtimeMessagingPrerequisites: runtimeMessagingPrerequisites(),
            nativeMessagingPrerequisites: nativeMessagingPrerequisites(),
            storagePrerequisites: storagePrerequisites(),
            permissionsActiveTabPrerequisites: permissionsPrerequisites(),
            serviceWorkerLifecyclePrerequisites: lifecyclePrerequisites(),
            passwordManagerPrerequisiteSummary: passwordSummary(),
            unsupportedDeferredAPIs:
                ChromeMV3UnsupportedDeferredAPISummary(
                    unsupportedAPIs: [],
                    deferredAPIs: [.nativeMessaging],
                    unsupportedDeferredAPIsRemainRuntimeBlockers: true
                ),
            modeledOnlyComponents: ["native messaging security model"],
            blockedComponents: ["native messaging runtime"],
            requiredFutureComponents: ["native host launch policy"],
            unsupportedOrDeferredAPIs: [.nativeMessaging],
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            contextCreationBlockedReason:
                "Context creation remains blocked.",
            contextLoadingBlockedReason:
                "Context loading remains blocked.",
            runtimeLoadableFalseReason:
                "runtimeLoadable remains false.",
            nextRequiredCategoryAfterThisReport:
                .implementRuntimeBridgeComponents,
            documentationSources: [],
            warnings: []
        )
    }

    private func manifestFacts(
        root: URL
    ) -> ChromeMV3RuntimeBridgeManifestFacts {
        ChromeMV3RuntimeBridgeManifestFacts(
            manifestReadStatus: .loaded,
            manifestPath: root.appendingPathComponent("manifest.json").path,
            manifestSHA256: String(repeating: "b", count: 64),
            declaredPermissions: ["nativeMessaging", "storage"],
            optionalPermissions: [],
            hostPermissions: ["https://example.com/*"],
            optionalHostPermissions: [],
            contentScriptsPresent: true,
            contentScriptMatchPatterns: ["https://example.com/*"],
            actionPopupPresent: true,
            backgroundServiceWorkerPresent: true,
            storagePermissionPresent: true,
            nativeMessagingPermissionPresent: true,
            activeTabPermissionPresent: false,
            permissionsAPIPresent: false,
            warnings: []
        )
    }

    private func runtimeMessagingPrerequisites()
        -> ChromeMV3RuntimeMessagingContract
    {
        ChromeMV3RuntimeMessagingContract(
            status: .modeled,
            implementedNow: false,
            dispatchImplemented: false,
            listenerDeliveryImplemented: false,
            callbackCompatibilityRequired: true,
            promiseCompatibilityRequired: true,
            lastErrorRequirement:
                "Chrome-style lastError contract required.",
            timeoutPolicyRequired: true,
            timeoutPolicy: "No runtime schedule in this layer.",
            routes: [
                ChromeMV3RuntimeMessagingRouteContract(
                    route: "contentScriptToServiceWorker",
                    requiredAPI: "runtime.sendMessage",
                    requiresServiceWorkerWakePolicy: true,
                    requiresTabAddressing: true,
                    implementedNow: false,
                    blockedReason: "Modeled only."
                ),
            ],
            portLifecycleRequirements: ["Port model required."],
            disconnectReasons: ["tabClosed"],
            contentScriptMessagingRestrictions: [
                "Content scripts message extension contexts.",
            ],
            requiredBeforePasswordManagerSupport: true,
            requiredBeforeRuntimeLoadability: true,
            blockers: ["Runtime messaging is not implemented."],
            futureTestsNeeded: []
        )
    }

    private func nativeMessagingPrerequisites()
        -> ChromeMV3NativeMessagingPrerequisites
    {
        ChromeMV3NativeMessagingPrerequisites(
            status: .blocked,
            nativeMessagingDetected: true,
            nativeMessagingBlocked: true,
            hostManifestLookupImplemented: true,
            hostValidationImplemented: true,
            userConsentImplemented: false,
            processLaunchImplemented: false,
            stdioFramingRequired: true,
            inboundHostMessageLimitBytes: 1_048_576,
            outboundHostMessageLimitBytes: 67_108_864,
            portLifecycleModeled: true,
            hostExitBehaviorModeled: true,
            disabledModuleBehavior: "No native messaging runtime.",
            noLaunchWhileExtensionsDisabled: true,
            noLaunchBeforeExplicitImplementation: true,
            requiredBeforePasswordManagerSupport: true,
            futureSecurityReviewRequired: true,
            blockers: ["Native messaging remains blocked."],
            hostManifestLookupRequirements: [],
            allowedHostValidationRequirements: [],
            futureTestsNeeded: []
        )
    }

    private func storagePrerequisites() -> ChromeMV3StoragePrerequisites {
        ChromeMV3StoragePrerequisites(
            status: .notImplemented,
            storagePermissionPresent: true,
            implementedNow: false,
            webKitBehaviorSufficientWithoutHostLayer: false,
            hostBackedLayerDecisionRequired: true,
            profileIsolationVerified: false,
            workerUnloadReloadStateVerified: false,
            passwordManagerStateRequirements: [],
            areas: ChromeMV3StorageAreaName.allCases.map {
                ChromeMV3StorageAreaPrerequisite(
                    area: $0,
                    required: true,
                    implementedNow: false,
                    persistenceExpectation: "Modeled.",
                    contentScriptExposureDefault: "Modeled.",
                    decisionRequired: "Future decision required.",
                    blockers: ["Storage is not implemented."]
                )
            },
            blockers: ["Storage is not implemented."],
            futureTestsNeeded: []
        )
    }

    private func permissionsPrerequisites()
        -> ChromeMV3PermissionsActiveTabPrerequisites
    {
        ChromeMV3PermissionsActiveTabPrerequisites(
            status: .notImplemented,
            requiredPermissions: ["nativeMessaging", "storage"],
            optionalPermissions: [],
            hostPermissions: ["https://example.com/*"],
            optionalHostPermissions: [],
            activeTabDeclared: false,
            permissionBrokerImplemented: true,
            activeTabImplemented: true,
            hostPermissionEvaluationImplemented: true,
            userGestureRequirementModeled: true,
            grantLifetimeRequirement: "Modeled.",
            tabNavigationInvalidationRequirement: "Modeled.",
            permissionPromptUIFutureRequirement: true,
            contentScriptExecutionInteraction: "Blocked.",
            passwordManagerHostAccessRequirement: "Required.",
            requiredBeforeContentScriptExecution: true,
            requiredBeforePasswordManagerSupport: true,
            blockers: ["Real permission prompts are not implemented."],
            futureTestsNeeded: []
        )
    }

    private func lifecyclePrerequisites()
        -> ChromeMV3ServiceWorkerLifecycleReadiness
    {
        ChromeMV3ServiceWorkerLifecycleReadiness(
            status: .notImplemented,
            lifecycleCoordinatorImplemented: true,
            serviceWorkerWakeImplemented: false,
            idleUnloadPolicyModeled: true,
            permanentBackgroundForbidden: true,
            requiredBeforeContextLoad: true,
            requiredBeforeContextLoadReason: "Required.",
            requiredBeforeRuntimeLoadability: true,
            wakeReasonsRequired: ["runtime message"],
            eventDispatchPrerequisites: ["message dispatch"],
            idleReleasePolicy: "Modeled.",
            hardTimeoutPolicy: "Modeled.",
            longLivedPortPolicy: "Modeled.",
            nativeMessagingPortPolicy: "Blocked.",
            alarmWakePolicy: "Modeled.",
            statePersistenceRequirements: [],
            diagnosticsRequired: [],
            blockers: ["Service-worker wake is not implemented."],
            futureTestsNeeded: []
        )
    }

    private func passwordSummary()
        -> ChromeMV3PasswordManagerPrerequisiteSummary
    {
        ChromeMV3PasswordManagerPrerequisiteSummary(
            contentScriptsPresent: true,
            actionPopupPresent: true,
            hostPermissionsPresent: true,
            storagePermissionPresent: true,
            nativeMessagingPermissionPresent: true,
            runtimeMessagingMissing: true,
            permissionActiveTabMissing: true,
            storageBackendMissingOrDeferred: true,
            nativeMessagingMissing: true,
            controlledInputPageWorldBehaviorNotVerified: true,
            serviceWorkerLifecycleNotVerified: true,
            passwordManagerSupportReady: false,
            blockers: ["Password-manager native messaging is not ready."],
            deferredChecks: []
        )
    }

    private static func sourceFiles(
        in relativeDirectories: [String]
    ) throws -> [(relativePath: String, contents: String)] {
        let root = projectRoot()
        var files: [(relativePath: String, contents: String)] = []
        for relativeDirectory in relativeDirectories {
            let directory = root.appendingPathComponent(
                relativeDirectory,
                isDirectory: true
            )
            guard
                let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey]
                )
            else { continue }

            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [
                    .isRegularFileKey,
                ])
                guard values.isRegularFile == true,
                      url.pathExtension == "swift"
                else { continue }
                let relativePath = String(
                    url.standardizedFileURL.path.dropFirst(
                        root.standardizedFileURL.path.count + 1
                    )
                )
                files.append(
                    (
                        relativePath,
                        try String(contentsOf: url, encoding: .utf8)
                    )
                )
            }
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private static func projectRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.isEmpty == false {
            if FileManager.default.fileExists(
                atPath: url.appendingPathComponent("Sumi.xcodeproj").path
            ) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    }
}
