import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3PermissionRuntimeImplementationTests: XCTestCase {
    private let extensionID = "permission-runtime-tests-extension"
    private let profileID = "permission-runtime-tests-profile"

    func testRuntimeStateOwnerLoadsAndExportsDeterministicSnapshots()
        throws
    {
        var owner = permissionOwner()
        let first = try ChromeMV3DeterministicJSON.encodedData(
            owner.snapshot
        )
        let second = try ChromeMV3DeterministicJSON.encodedData(
            owner.snapshot
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(owner.snapshot.namespace.profileID, profileID)
        XCTAssertEqual(owner.snapshot.namespace.extensionID, extensionID)
        XCTAssertTrue(
            owner.snapshot.permissionImplementationAvailableInInternalRuntime
        )
        XCTAssertFalse(owner.snapshot.permissionUIAvailableInProduct)
        XCTAssertFalse(owner.snapshot.activeTabAvailableInProduct)
        XCTAssertFalse(owner.snapshot.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(owner.snapshot.runtimeLoadable)

        let accepted = owner.request(
            input: permissionInput(permissions: ["history"]),
            modeledPromptResult: .accepted
        )
        XCTAssertTrue(accepted.returnedBoolean)

        let reloaded = ChromeMV3PermissionRuntimeStateOwner(
            snapshot: owner.snapshot
        )
        let reloadedFirst = try ChromeMV3DeterministicJSON.encodedData(
            reloaded.snapshot
        )
        let reloadedSecond = try ChromeMV3DeterministicJSON.encodedData(
            reloaded.snapshot
        )

        XCTAssertEqual(reloadedFirst, reloadedSecond)
        XCTAssertEqual(
            reloaded.snapshot.permissionStore.summary
                .grantedOptionalAPIPermissions,
            ["history"]
        )
        XCTAssertEqual(reloaded.snapshot.transactionRecords.count, 1)
        XCTAssertFalse(reloaded.snapshot.permissionDiffs.isEmpty)
    }

    func testChromePermissionsBridgeMutatesModeledInternalState()
        throws
    {
        var owner = permissionOwner()
        let promptRequired = owner.request(
            input: permissionInput(permissions: ["bookmarks"]),
            modeledPromptResult: .notProvided
        )
        let denied = owner.request(
            input: permissionInput(permissions: ["bookmarks"]),
            modeledPromptResult: .denied
        )
        let accepted = owner.request(
            input: permissionInput(
                permissions: ["history"],
                origins: ["https://example.com/*"]
            ),
            modeledPromptResult: .accepted
        )
        let contains = owner.contains(
            input: permissionInput(
                permissions: ["history"],
                origins: ["https://example.com/*"]
            )
        )
        let all = owner.getAll()
        let removeRequired = owner.remove(
            input: permissionInput(permissions: ["tabs"])
        )
        let removeOptional = owner.remove(
            input: permissionInput(
                permissions: ["history"],
                origins: ["https://example.com/*"]
            )
        )
        let containsAfterRemove = owner.contains(
            input: permissionInput(
                permissions: ["history"],
                origins: ["https://example.com/*"]
            )
        )

        XCTAssertFalse(promptRequired.returnedBoolean)
        XCTAssertEqual(
            promptRequired.eventRecords.first?.eventKind,
            .promptRequiredButProductUIUnavailable
        )
        XCTAssertFalse(denied.returnedBoolean)
        XCTAssertEqual(denied.eventRecords.first?.eventKind, .permissionDenied)
        XCTAssertTrue(accepted.returnedBoolean)
        XCTAssertEqual(
            accepted.eventRecords.first?.eventKind,
            .permissionAdded
        )
        XCTAssertFalse(
            accepted.eventRecords.first?.serviceWorkerWakeRequired ?? true
        )
        XCTAssertTrue(contains.wouldReturn)
        XCTAssertTrue(all.permissions.contains("history"))
        XCTAssertTrue(all.origins.contains("https://example.com/*"))
        XCTAssertFalse(removeRequired.returnedBoolean)
        XCTAssertEqual(
            removeRequired.eventRecords.first?.eventKind,
            .permissionDenied
        )
        XCTAssertTrue(removeOptional.returnedBoolean)
        XCTAssertEqual(
            removeOptional.eventRecords.first?.eventKind,
            .permissionRemoved
        )
        XCTAssertFalse(containsAfterRemove.wouldReturn)
        XCTAssertTrue(
            owner.snapshot.eventRecords.contains {
                $0.eventKind == .promptRequiredButProductUIUnavailable
            }
        )
    }

    func testOptionalHostGrantAndRevokeControlsTabsQueryAndMessaging()
        throws
    {
        var owner = permissionOwner(
            declaredAPIPermissions: ["activeTab", "scripting"],
            optionalHostPermissions: ["https://example.com/*"]
        )
        let configuration = bridgeConfiguration()
        let registry = ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
            extensionID: extensionID,
            profileID: profileID,
            includeProductNormalTab: true
        )

        let redacted = tabsHandler(
            owner: owner,
            configuration: configuration,
            registry: registry
        ).handle(tabsQueryRequest())
        XCTAssertNil(firstTabObject(redacted)?["url"])
        XCTAssertNil(firstTabObject(redacted)?["title"])

        let grant = owner.request(
            input: permissionInput(origins: ["https://example.com/*"]),
            modeledPromptResult: .accepted
        )
        XCTAssertTrue(grant.returnedBoolean)

        let grantedHandler = tabsHandler(
            owner: owner,
            configuration: configuration,
            registry: registry
        )
        let exposed = grantedHandler.handle(tabsQueryRequest())
        let send = grantedHandler.handle(tabsSendMessageRequest())
        let connect = grantedHandler.handle(tabsConnectRequest())
        let script = grantedHandler.handle(executeScriptRequest(tabID: 1))

        XCTAssertEqual(
            firstTabObject(exposed)?["url"],
            .string("https://example.com/login")
        )
        XCTAssertEqual(
            firstTabObject(exposed)?["title"],
            .string("Example Login")
        )
        XCTAssertTrue(send.succeeded)
        XCTAssertTrue(connect.succeeded)
        XCTAssertTrue(script.succeeded)

        let remove = owner.remove(
            input: permissionInput(origins: ["https://example.com/*"])
        )
        XCTAssertTrue(remove.returnedBoolean)
        let revokedHandler = tabsHandler(
            owner: owner,
            configuration: configuration,
            registry: registry
        )
        let reRedacted = revokedHandler.handle(tabsQueryRequest())
        let blockedSend = revokedHandler.handle(tabsSendMessageRequest())
        let blockedScript = revokedHandler.handle(executeScriptRequest(tabID: 1))

        XCTAssertNil(firstTabObject(reRedacted)?["url"])
        XCTAssertNil(firstTabObject(reRedacted)?["title"])
        XCTAssertFalse(blockedSend.succeeded)
        XCTAssertEqual(
            blockedSend.lastErrorCode,
            ChromeMV3RuntimeLastErrorCase.permissionDenied.rawValue
        )
        XCTAssertFalse(blockedScript.succeeded)
    }

    func testActiveTabGrantAllowsSyntheticTargetsUntilLifecycleExpiry()
        throws
    {
        var owner = permissionOwner(
            declaredAPIPermissions: ["activeTab", "scripting"],
            optionalAPIPermissions: [],
            optionalHostPermissions: []
        )
        let grant = owner.grantActiveTabFromGesture(
            ChromeMV3ActiveTabGestureEvent(
                extensionID: extensionID,
                profileID: profileID,
                tabID: 1,
                url: "https://example.com/login",
                reason: .actionClick,
                userGestureModeled: true,
                sequence: 10
            )
        )
        let configuration = bridgeConfiguration()
        let registry = ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
            extensionID: extensionID,
            profileID: profileID,
            includeProductNormalTab: true
        )
        let handler = tabsHandler(
            owner: owner,
            configuration: configuration,
            registry: registry
        )

        XCTAssertTrue(grant.granted)
        XCTAssertEqual(grant.eventRecord?.eventKind, .activeTabGranted)
        XCTAssertEqual(
            firstTabObject(handler.handle(tabsQueryRequest()))?["url"],
            .string("https://example.com/login")
        )
        XCTAssertTrue(handler.handle(tabsSendMessageRequest()).succeeded)
        XCTAssertTrue(handler.handle(tabsConnectRequest()).succeeded)
        XCTAssertTrue(handler.handle(executeScriptRequest(tabID: 1)).succeeded)

        let expired = owner.applyLifecycleEvent(
            ChromeMV3PermissionLifecycleEvent(
                kind: .tabNavigated,
                extensionID: extensionID,
                profileID: profileID,
                tabID: 1,
                oldURL: "https://example.com/login",
                newURL: "https://chromium.org/",
                sequence: 11
            )
        )
        let expiredHandler = tabsHandler(
            owner: owner,
            configuration: configuration,
            registry: registry
        )
        let blocked = expiredHandler.handle(tabsSendMessageRequest())

        XCTAssertEqual(expired.eventRecords.first?.eventKind, .activeTabExpired)
        XCTAssertEqual(
            expired.eventRecords.first?.activeTabExpiryCause,
            .tabNavigation
        )
        XCTAssertFalse(blocked.succeeded)
        XCTAssertEqual(
            blocked.lastErrorCode,
            ChromeMV3RuntimeLastErrorCase.activeTabMissing.rawValue
        )
    }

    func testActiveTabExpiresOnTabCloseExtensionDisableProfileCloseAndReset()
        throws
    {
        for (kind, trigger) in [
            (
                ChromeMV3PermissionLifecycleEventKind.tabClosed,
                ChromeMV3ActiveTabExpiryTrigger.tabClose
            ),
            (
                ChromeMV3PermissionLifecycleEventKind.extensionDisabled,
                ChromeMV3ActiveTabExpiryTrigger.extensionDisable
            ),
            (
                ChromeMV3PermissionLifecycleEventKind.profileClosed,
                ChromeMV3ActiveTabExpiryTrigger.profileClose
            ),
        ] {
            var owner = activeTabOwnerWithGrant(sequence: 30)
            let result = owner.applyLifecycleEvent(
                ChromeMV3PermissionLifecycleEvent(
                    kind: kind,
                    extensionID: extensionID,
                    profileID: profileID,
                    tabID: 1,
                    sequence: 31
                )
            )
            XCTAssertEqual(result.eventRecords.first?.eventKind, .activeTabExpired)
            XCTAssertEqual(
                result.eventRecords.first?.activeTabExpiryCause,
                trigger
            )
            XCTAssertEqual(
                owner.snapshot.activeTabStore.summary.activeGrantCount,
                0
            )
        }

        var resetOwner = activeTabOwnerWithGrant(sequence: 40)
        let reset = resetOwner.resetActiveTabGrants(sequence: 41)
        XCTAssertEqual(reset.eventRecords.first?.eventKind, .activeTabExpired)
        XCTAssertEqual(
            reset.eventRecords.first?.activeTabExpiryCause,
            .explicitReset
        )
    }

    func testScriptingRequiresScriptingPermissionAndBlocksProductNormalTabs()
        throws
    {
        let configuration = bridgeConfiguration()
        let registry = ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
            extensionID: extensionID,
            profileID: profileID,
            includeProductNormalTab: true
        )
        let missingScripting = tabsHandler(
            owner: permissionOwner(
                declaredAPIPermissions: ["activeTab"],
                declaredHostPermissions: ["https://example.com/*"],
                optionalAPIPermissions: [],
                optionalHostPermissions: []
            ),
            configuration: configuration,
            registry: registry
        ).handle(executeScriptRequest(tabID: 1))
        let productTarget = tabsHandler(
            owner: permissionOwner(
                declaredAPIPermissions: ["activeTab", "scripting"],
                declaredHostPermissions: ["https://example.com/*"],
                optionalAPIPermissions: [],
                optionalHostPermissions: []
            ),
            configuration: configuration,
            registry: registry
        ).handle(executeScriptRequest(tabID: 99))

        XCTAssertFalse(missingScripting.succeeded)
        XCTAssertEqual(
            missingScripting.lastErrorCode,
            ChromeMV3RuntimeLastErrorCase.permissionDenied.rawValue
        )
        XCTAssertFalse(productTarget.succeeded)
        XCTAssertEqual(
            productTarget.lastErrorCode,
            ChromeMV3RuntimeLastErrorCase.unsupportedAPI.rawValue
        )
        XCTAssertFalse(productTarget.serviceWorkerWakeAvailable)
        XCTAssertFalse(productTarget.nativeMessagingAvailable)
        XCTAssertFalse(productTarget.runtimeLoadable)
    }

    @MainActor
    func testWebKitSyntheticHarnessObservesPermissionGrantRevokeAndRedaction()
        async throws
    {
        guard #available(macOS 15.5, *) else { return }
        let configuration = bridgeConfiguration()
        let result = await ChromeMV3TabsScriptingJSSyntheticHarness.run(
            scriptBody: """
            const before = await chrome.tabs.query({active: true});
            const granted = await chrome.permissions.request({
              origins: ["https://example.com/*"],
              __sumiUserGestureModeled: true,
              __sumiModeledPromptResult: "accepted"
            });
            const afterGrant = await chrome.tabs.query({active: true});
            const send = await chrome.tabs.sendMessage(
              1,
              {type: "after-grant"},
              {frameId: 0}
            );
            const port = chrome.tabs.connect(1, {name: "after-grant", frameId: 0});
            port.disconnect();
            const executed = await chrome.scripting.executeScript({
              target: {tabId: 1, frameIds: [0]},
              func: () => document.title,
              args: []
            });
            const removed = await chrome.permissions.remove({
              origins: ["https://example.com/*"]
            });
            const afterRemove = await chrome.tabs.query({active: true});
            let blockedMessage = null;
            try {
              await chrome.tabs.sendMessage(1, {type: "after-remove"}, {frameId: 0});
            } catch (error) {
              blockedMessage = error && error.message;
            }
            return {
              granted,
              removed,
              beforeRedacted: before[0].url === undefined && before[0].title === undefined,
              afterGrantVisible:
                afterGrant[0].url === "https://example.com/login"
                && afterGrant[0].title === "Example Login",
              sendOK: send && send.target === "syntheticContentScriptModel",
              connectOK: port && port.name === "after-grant",
              executeOK:
                Array.isArray(executed)
                && executed[0].result.source === "controlledSyntheticModel",
              afterRemoveRedacted:
                afterRemove[0].url === undefined && afterRemove[0].title === undefined,
              blockedAfterRemove: typeof blockedMessage === "string"
            };
            """,
            configuration: configuration,
            tabRegistry:
                ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                    extensionID: extensionID,
                    profileID: profileID,
                    includeProductNormalTab: true
                ),
            permissionRuntimeOwner:
                permissionOwner(
                    declaredAPIPermissions: ["activeTab", "scripting"],
                    optionalAPIPermissions: [],
                    optionalHostPermissions: ["https://example.com/*"]
                )
        )
        let object = try XCTUnwrap(try decodedObject(result.scriptResultJSON))

        XCTAssertTrue(
            result.scriptEvaluationSucceeded,
            result.diagnostics.joined(separator: "\n")
        )
        XCTAssertEqual(object["granted"] as? Bool, true)
        XCTAssertEqual(object["removed"] as? Bool, true)
        XCTAssertEqual(object["beforeRedacted"] as? Bool, true)
        XCTAssertEqual(object["afterGrantVisible"] as? Bool, true)
        XCTAssertEqual(object["sendOK"] as? Bool, true)
        XCTAssertEqual(object["connectOK"] as? Bool, true)
        XCTAssertEqual(object["executeOK"] as? Bool, true)
        XCTAssertEqual(object["afterRemoveRedacted"] as? Bool, true)
        XCTAssertEqual(object["blockedAfterRemove"] as? Bool, true)
        XCTAssertFalse(result.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(result.runtimeLoadable)
    }

    @MainActor
    func testImplementationReportIsDeterministicWritableAndDisabledModuleBlocks()
        throws
    {
        guard #available(macOS 15.5, *) else { return }
        let report = ChromeMV3PermissionImplementationReportGenerator
            .makeReport(
                extensionID: extensionID,
                profileID: profileID,
                webKitSyntheticPermissionVerificationStatus:
                    "verifiedByFocusedTest"
            )
        let first = try ChromeMV3DeterministicJSON.encodedData(report)
        let second = try ChromeMV3DeterministicJSON.encodedData(report)
        let root = try makeTemporaryDirectory()
        let written = try ChromeMV3PermissionImplementationReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(written, report)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath:
                    root.appendingPathComponent(
                        ChromeMV3PermissionImplementationReportWriter
                            .reportFileName
                    ).path
            )
        )
        XCTAssertTrue(
            report.summary.permissionImplementationAvailableInInternalRuntime
        )
        XCTAssertFalse(report.permissionUIAvailableInProduct)
        XCTAssertFalse(report.activeTabAvailableInProduct)
        XCTAssertFalse(report.normalTabRuntimeBridgeAvailable)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertFalse(report.serviceWorkerWakeAvailable)
        XCTAssertFalse(report.nativeMessagingAvailable)
        XCTAssertFalse(report.productRuntimeExposed)

        let suiteName =
            "ChromeMV3PermissionRuntimeImplementationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let module = SumiExtensionsModule(
            moduleRegistry:
                SumiModuleRegistry(
                    settingsStore: SumiModuleSettingsStore(
                        userDefaults: defaults
                    )
                )
        )
        module.setEnabled(false)
        XCTAssertNil(
            module.chromeMV3PermissionImplementationReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        )
    }

    func testSourceLevelGuardsKeepProductBoundariesBlocked() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let productionRoot = root.appendingPathComponent(
            "Sumi/Models/Extension/ChromeMV3"
        )
        let extensionModule = root.appendingPathComponent(
            "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift"
        )
        let swiftFiles = try productionSwiftFiles(under: productionRoot)
            + [extensionModule]
        let source = try swiftFiles.map {
            try String(contentsOf: $0, encoding: .utf8)
        }.joined(separator: "\n")
        let native = "connect" + "Native"
        let proc = "Process" + #"\("#
        let dispatchClock = "DispatchSource" + ("Ti" + "mer")
        let clock = "\\b" + ("Ti" + "mer") + "\\b"
        let positiveBooleanLiteral = "tr" + "ue"
        let forbidden = [
            native,
            proc,
            dispatchClock,
            clock,
            "runtimeLoadable.*" + positiveBooleanLiteral,
            "permissionUIAvailableInProduct.*" + positiveBooleanLiteral,
            "activeTabAvailableInProduct.*" + positiveBooleanLiteral,
            "normalTabRuntimeBridgeAvailable.*" + positiveBooleanLiteral,
            "serviceWorkerWakeAvailable.*" + positiveBooleanLiteral,
            "nativeMessagingAvailable.*" + positiveBooleanLiteral,
            "productRuntimeExposed.*" + positiveBooleanLiteral,
        ]

        for pattern in forbidden {
            XCTAssertNil(
                source.range(of: pattern, options: .regularExpression),
                pattern
            )
        }
    }

    private func permissionOwner(
        declaredAPIPermissions: [String] = ["activeTab", "scripting", "tabs"],
        declaredHostPermissions: [String] = [],
        optionalAPIPermissions: [String] = ["bookmarks", "history"],
        optionalHostPermissions: [String] = ["https://example.com/*"]
    ) -> ChromeMV3PermissionRuntimeStateOwner {
        ChromeMV3PermissionRuntimeStateOwner(
            permissionStore:
                ChromeMV3PermissionDecisionStore(
                    snapshot:
                        ChromeMV3PermissionDecisionStoreSnapshot(
                            extensionID: extensionID,
                            profileID: profileID,
                            declaredAPIPermissions:
                                declaredAPIPermissions,
                            declaredHostPermissions:
                                declaredHostPermissions,
                            optionalAPIPermissions:
                                optionalAPIPermissions,
                            optionalHostPermissions:
                                optionalHostPermissions
                        )
                )
        )
    }

    private func activeTabOwnerWithGrant(
        sequence: Int
    ) -> ChromeMV3PermissionRuntimeStateOwner {
        var owner = permissionOwner(
            declaredAPIPermissions: ["activeTab", "scripting"],
            optionalAPIPermissions: [],
            optionalHostPermissions: []
        )
        _ = owner.grantActiveTabFromGesture(
            ChromeMV3ActiveTabGestureEvent(
                extensionID: extensionID,
                profileID: profileID,
                tabID: 1,
                url: "https://example.com/login",
                reason: .testFixture,
                userGestureModeled: true,
                sequence: sequence
            )
        )
        return owner
    }

    private func permissionInput(
        permissions: [String] = [],
        origins: [String] = []
    ) -> ChromeMV3PermissionsAPIRequestInput {
        ChromeMV3PermissionsAPIRequestInput(
            extensionID: extensionID,
            profileID: profileID,
            sourceContext: .actionPopup,
            userGestureModeled: true,
            permissions: permissions,
            origins: origins
        )
    }

    private func bridgeConfiguration()
        -> ChromeMV3TabsScriptingJSBridgeConfiguration
    {
        ChromeMV3TabsScriptingJSBridgeConfiguration.syntheticHarness(
            extensionID: extensionID,
            profileID: profileID
        )
    }

    private func tabsHandler(
        owner: ChromeMV3PermissionRuntimeStateOwner,
        configuration: ChromeMV3TabsScriptingJSBridgeConfiguration,
        registry: ChromeMV3SyntheticTabRegistry
    ) -> ChromeMV3TabsScriptingJSBridgeHandler {
        ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            tabRegistry: registry,
            permissionRuntimeOwner: owner
        )
    }

    private func tabsQueryRequest() -> ChromeMV3RuntimeJSBridgeHostRequest {
        request(
            namespace: "tabs",
            methodName: "query",
            arguments: [.object(["active": .bool(true)])]
        )
    }

    private func tabsSendMessageRequest()
        -> ChromeMV3RuntimeJSBridgeHostRequest
    {
        request(
            namespace: "tabs",
            methodName: "sendMessage",
            arguments: [
                .number(1),
                .object(["type": .string("permission-runtime-test")]),
                .object(["frameId": .number(0)]),
            ]
        )
    }

    private func tabsConnectRequest() -> ChromeMV3RuntimeJSBridgeHostRequest {
        request(
            namespace: "tabs",
            methodName: "connect",
            invocationMode: .fireAndForget,
            arguments: [
                .number(1),
                .object([
                    "name": .string("permission-runtime-test"),
                    "frameId": .number(0),
                ]),
            ]
        )
    }

    private func executeScriptRequest(
        tabID: Int
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        request(
            namespace: "scripting",
            methodName: "executeScript",
            arguments: [
                .object([
                    "target": .object([
                        "tabId": .number(Double(tabID)),
                        "frameIds": .array([.number(0)]),
                    ]),
                    "functionSource": .string(
                        "function getTitle() { return document.title; }"
                    ),
                    "args": .array([]),
                ]),
            ]
        )
    }

    private func request(
        namespace: String,
        methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode = .promise,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID:
                "permission-runtime-tests-\(namespace)-\(methodName)",
            namespace: namespace,
            methodName: methodName,
            invocationMode: invocationMode,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }

    private func firstTabObject(
        _ response: ChromeMV3TabsScriptingJSBridgeHostResponse
    ) -> [String: ChromeMV3StorageValue]? {
        guard case .array(let tabs)? = response.resultPayload,
              let first = tabs.first,
              case .object(let object) = first
        else { return nil }
        return object
    }

    private func decodedObject(_ json: String?) throws -> [String: Any]? {
        guard let json else { return nil }
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        return root
    }

    private func productionSwiftFiles(under root: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        var files: [URL] = []
        while let file = enumerator?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(file)
            }
        }
        return files.sorted { $0.path < $1.path }
    }
}
