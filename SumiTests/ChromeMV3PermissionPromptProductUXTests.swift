import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3PermissionPromptProductUXTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testDisabledModuleAndExtensionBlockPromptGeneration() {
        let disabledModule = ChromeMV3PermissionPromptGateRecord.evaluate(
            moduleEnabled: false,
            extensionEnabled: true,
            developerPreviewGate: true
        )
        let disabledExtension = ChromeMV3PermissionPromptGateRecord.evaluate(
            moduleEnabled: true,
            extensionEnabled: false,
            developerPreviewGate: true
        )

        XCTAssertFalse(
            disabledModule.permissionPromptAvailableInDeveloperPreview
        )
        XCTAssertTrue(disabledModule.blockers.contains(.disabledModule))
        XCTAssertFalse(
            disabledExtension.permissionPromptAvailableInDeveloperPreview
        )
        XCTAssertTrue(disabledExtension.blockers.contains(.disabledExtension))
        XCTAssertFalse(disabledModule.silentGrantAllowed)
        XCTAssertFalse(disabledExtension.silentGrantAllowed)
    }

    func testPermissionsRequestWithoutPresenterReturnsPromptUnavailable()
        throws
    {
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                configuration(manifestOptionalPermissions: ["history"])
        )

        let response = handler.handle(request(
            namespace: "permissions",
            methodName: "request",
            arguments: [.object([
                "permissions": .array([.string("history")]),
            ])]
        ))

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorCode, "productUIUnavailable")
        XCTAssertEqual(
            handler.diagnosticsSnapshot.permissionPromptResults
                .map(\.disposition),
            [.unavailable]
        )
        XCTAssertFalse(
            handler.permissionRuntimeSnapshot.permissionStore.summary
                .grantedOptionalAPIPermissions.contains("history")
        )
    }

    func testPermissionsRequestAcceptedThroughPresenterGrantsAndPersists()
        throws
    {
        let root = try makeTemporaryDirectory()
        let presenter = ChromeMV3TestPermissionPromptPresenter(
            disposition: .accepted
        )
        let store = ChromeMV3DeveloperPreviewPermissionStateStore(
            rootURL: root
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                configuration(manifestOptionalPermissions: ["history"]),
            permissionPromptPresenter: presenter,
            permissionStateStore: store
        )

        let response = handler.handle(request(
            namespace: "permissions",
            methodName: "request",
            arguments: [.object([
                "permissions": .array([.string("history")]),
            ])]
        ))
        let persisted = try XCTUnwrap(store.loadRecord(
            profileID: "profile",
            extensionID: "extension"
        ))

        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(boolValue(response.resultPayload), true)
        XCTAssertEqual(response.permissionEventPayload?.eventKind, .onAdded)
        XCTAssertTrue(
            handler.permissionRuntimeSnapshot.permissionStore.summary
                .grantedOptionalAPIPermissions.contains("history")
        )
        XCTAssertTrue(
            persisted.permissionRuntimeSnapshot.permissionStore.summary
                .grantedOptionalAPIPermissions.contains("history")
        )
        XCTAssertEqual(persisted.promptResults.map(\.disposition), [.accepted])
        XCTAssertTrue(
            persisted.promptLifecycleRecords.map(\.stage)
                .contains(.promptCreated)
        )
        XCTAssertTrue(
            persisted.promptLifecycleRecords.map(\.stage)
                .contains(.promptPresented)
        )
        XCTAssertTrue(
            persisted.promptLifecycleRecords.map(\.stage)
                .contains(.accepted)
        )
        XCTAssertTrue(
            persisted.promptLifecycleRecords.map(\.stage)
                .contains(.downstreamInvalidated)
        )
        XCTAssertTrue(
            persisted.promptLifecycleRecords.map(\.stage)
                .contains(.resultPersisted)
        )
    }

    func testPermissionsRequestDeniedAndDismissedDoNotGrant() throws {
        for disposition in [
            ChromeMV3PermissionPromptResultDisposition.denied,
            .dismissed,
        ] {
            let handler = ChromeMV3PopupOptionsJSBridgeHandler(
                configuration:
                    configuration(manifestOptionalPermissions: ["history"]),
                permissionPromptPresenter:
                    ChromeMV3TestPermissionPromptPresenter(
                        disposition: disposition
                    )
            )

            let response = handler.handle(request(
                namespace: "permissions",
                methodName: "request",
                arguments: [.object([
                    "permissions": .array([.string("history")]),
                ])]
            ))

            XCTAssertTrue(response.succeeded)
            XCTAssertEqual(boolValue(response.resultPayload), false)
            XCTAssertFalse(
                handler.permissionRuntimeSnapshot.permissionStore.summary
                    .grantedOptionalAPIPermissions.contains("history")
            )
            XCTAssertEqual(
                handler.diagnosticsSnapshot.permissionPromptResults
                    .map(\.disposition),
                [disposition]
            )
        }
    }

    func testUndeclaredOptionalPermissionIsRejected() {
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(),
            permissionPromptPresenter:
                ChromeMV3TestPermissionPromptPresenter(disposition: .accepted)
        )

        let response = handler.handle(request(
            namespace: "permissions",
            methodName: "request",
            arguments: [.object([
                "permissions": .array([.string("history")]),
            ])]
        ))

        XCTAssertFalse(response.succeeded)
        XCTAssertEqual(response.lastErrorCode, "permissionNotDeclaredOptional")
        XCTAssertTrue(
            handler.diagnosticsSnapshot.permissionPromptResults
                .contains { $0.disposition == .blocked }
        )
    }

    func testPermissionsRemoveRejectsRequiredAndRevokesOptionalGrants() {
        let presenter = ChromeMV3TestPermissionPromptPresenter(
            disposition: .accepted
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                configuration(
                    manifestPermissions: ["tabs"],
                    manifestOptionalPermissions: ["history"],
                    manifestOptionalHostPermissions: ["https://example.com/*"]
                ),
            permissionPromptPresenter: presenter
        )

        let requiredRemove = handler.handle(request(
            namespace: "permissions",
            methodName: "remove",
            arguments: [.object([
                "permissions": .array([.string("tabs")]),
            ])]
        ))
        _ = handler.handle(request(
            namespace: "permissions",
            methodName: "request",
            arguments: [.object([
                "permissions": .array([.string("history")]),
                "origins": .array([.string("https://example.com/*")]),
            ])]
        ))
        let optionalRemove = handler.handle(request(
            namespace: "permissions",
            methodName: "remove",
            arguments: [.object([
                "permissions": .array([.string("history")]),
                "origins": .array([.string("https://example.com/*")]),
            ])]
        ))

        let summary = handler.permissionRuntimeSnapshot.permissionStore.summary
        XCTAssertFalse(requiredRemove.succeeded)
        XCTAssertEqual(requiredRemove.lastErrorCode, "requiredManifestPermission")
        XCTAssertTrue(optionalRemove.succeeded)
        XCTAssertFalse(
            summary.grantedOptionalAPIPermissions.contains("history")
        )
        XCTAssertFalse(
            summary.grantedOptionalHostPermissions
                .contains("https://example.com/*")
        )
        XCTAssertTrue(summary.revokedPermissions.contains("history"))
        XCTAssertTrue(
            summary.revokedPermissions.contains("https://example.com/*")
        )
    }

    func testPermissionsOnAddedDispatchesToAlreadyOpenListenerOnly() {
        let dispatcher = ChromeMV3PermissionEventDispatchRegistry()
        var deliveredPayloads: [ChromeMV3PermissionsAPIEventPayload] = []
        dispatcher.registerChromeMV3PermissionEventPage(
            surfaceID: "profile:extension:options",
            profileID: "profile",
            extensionID: "extension",
            surface: .optionsPage,
            dispatchHandler: { payload in
                deliveredPayloads.append(payload)
                return true
            }
        )
        dispatcher.updateChromeMV3PermissionEventListenerCount(
            surfaceID: "profile:extension:options",
            profileID: "profile",
            extensionID: "extension",
            surface: .optionsPage,
            eventKind: .onAdded,
            listenerCount: 1
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                configuration(manifestOptionalPermissions: ["history"]),
            permissionPromptPresenter:
                ChromeMV3TestPermissionPromptPresenter(disposition: .accepted),
            permissionEventDispatcher: dispatcher
        )

        let response = handler.handle(request(
            namespace: "permissions",
            methodName: "request",
            arguments: [.object([
                "permissions": .array([.string("history")]),
            ])]
        ))
        let record = dispatcher.permissionEventDispatchRecords.last

        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(record?.outcome, .delivered)
        XCTAssertEqual(record?.eventPayload.eventKind, .onAdded)
        XCTAssertEqual(record?.deliveredSurfaceIDs, ["profile:extension:options"])
        XCTAssertEqual(record?.serviceWorkerWakeAttempted, false)
        XCTAssertEqual(record?.hiddenExtensionPageCreated, false)
        XCTAssertEqual(deliveredPayloads.map(\.eventKind), [.onAdded])
    }

    func testPermissionsOnRemovedDispatchesToAlreadyOpenListenerOnly() {
        let dispatcher = ChromeMV3PermissionEventDispatchRegistry()
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                configuration(manifestOptionalPermissions: ["history"]),
            permissionPromptPresenter:
                ChromeMV3TestPermissionPromptPresenter(disposition: .accepted),
            permissionEventDispatcher: dispatcher
        )
        _ = handler.handle(request(
            namespace: "permissions",
            methodName: "request",
            arguments: [.object([
                "permissions": .array([.string("history")]),
            ])]
        ))
        dispatcher.registerChromeMV3PermissionEventPage(
            surfaceID: "profile:extension:options",
            profileID: "profile",
            extensionID: "extension",
            surface: .optionsPage,
            dispatchHandler: { _ in true }
        )
        dispatcher.updateChromeMV3PermissionEventListenerCount(
            surfaceID: "profile:extension:options",
            profileID: "profile",
            extensionID: "extension",
            surface: .optionsPage,
            eventKind: .onRemoved,
            listenerCount: 1
        )

        let response = handler.handle(request(
            namespace: "permissions",
            methodName: "remove",
            arguments: [.object([
                "permissions": .array([.string("history")]),
            ])]
        ))
        let record = dispatcher.permissionEventDispatchRecords.last

        XCTAssertTrue(response.succeeded)
        XCTAssertEqual(record?.outcome, .delivered)
        XCTAssertEqual(record?.eventPayload.eventKind, .onRemoved)
        XCTAssertEqual(record?.deliveredSurfaceIDs, ["profile:extension:options"])
        XCTAssertEqual(record?.serviceWorkerWakeAttempted, false)
        XCTAssertEqual(record?.hiddenExtensionPageCreated, false)
    }

    func testPopupOptionsLoadsPersistedPermissionStateFromRootPath() throws {
        let root = try makeTemporaryDirectory()
        let store = ChromeMV3DeveloperPreviewPermissionStateStore(rootURL: root)
        let grantingHandler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                configuration(
                    manifestOptionalPermissions: ["history"],
                    manifestOptionalHostPermissions: ["https://example.com/*"]
                ),
            permissionPromptPresenter:
                ChromeMV3TestPermissionPromptPresenter(disposition: .accepted),
            permissionStateStore: store
        )
        _ = grantingHandler.handle(request(
            namespace: "permissions",
            methodName: "request",
            arguments: [.object([
                "permissions": .array([.string("history")]),
                "origins": .array([.string("https://example.com/*")]),
            ])]
        ))

        let reloadedHandler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                configuration(
                    permissionStateRootPath: root.path,
                    manifestOptionalPermissions: ["history"],
                    manifestOptionalHostPermissions: ["https://example.com/*"]
                )
        )
        let contains = reloadedHandler.handle(request(
            namespace: "permissions",
            methodName: "contains",
            arguments: [.object([
                "permissions": .array([.string("history")]),
                "origins": .array([.string("https://example.com/*")]),
            ])]
        ))
        let all = reloadedHandler.handle(request(
            namespace: "permissions",
            methodName: "getAll"
        ))
        let allObject = try XCTUnwrap(objectValue(all.resultPayload))

        XCTAssertEqual(boolValue(contains.resultPayload), true)
        XCTAssertTrue(stringArrayValue(allObject["permissions"]).contains("history"))
        XCTAssertTrue(
            stringArrayValue(allObject["origins"]).contains {
                $0.contains("example.com")
            }
        )
    }

    func testPermissionEventWithoutListenerProducesSkippedDiagnostic() {
        let dispatcher = ChromeMV3PermissionEventDispatchRegistry()
        dispatcher.registerChromeMV3PermissionEventPage(
            surfaceID: "profile:extension:options",
            profileID: "profile",
            extensionID: "extension",
            surface: .optionsPage,
            dispatchHandler: { _ in XCTFail("No listener should dispatch"); return false }
        )
        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                configuration(manifestOptionalPermissions: ["history"]),
            permissionPromptPresenter:
                ChromeMV3TestPermissionPromptPresenter(disposition: .accepted),
            permissionEventDispatcher: dispatcher
        )

        _ = handler.handle(request(
            namespace: "permissions",
            methodName: "request",
            arguments: [.object([
                "permissions": .array([.string("history")]),
            ])]
        ))
        let record = dispatcher.permissionEventDispatchRecords.last

        XCTAssertEqual(record?.outcome, .skipped)
        XCTAssertEqual(record?.listenerCount, 0)
        XCTAssertTrue(
            record?.diagnostics.contains {
                $0.contains("no permissions.onAdded listener")
            } == true
        )
        XCTAssertEqual(record?.serviceWorkerWakeAttempted, false)
        XCTAssertEqual(record?.hiddenExtensionPageCreated, false)
    }

    func testActiveTabRequiresExplicitGestureAndRedactionExpires() throws {
        var owner = ChromeMV3PermissionRuntimeStateOwner(
            permissionStore:
                ChromeMV3PermissionDecisionStore(
                    snapshot:
                        ChromeMV3PermissionDecisionStoreSnapshot(
                            extensionID: "extension",
                            profileID: "profile",
                            declaredAPIPermissions: ["activeTab"]
                        )
                )
        )
        let gate = ChromeMV3PermissionPromptGateRecord.evaluate(
            moduleEnabled: true,
            extensionEnabled: true,
            developerPreviewGate: true
        )
        let blocked = ChromeMV3DeveloperPreviewActiveTabUX.grant(
            request:
                ChromeMV3ActiveTabUXRequest(
                    extensionID: "extension",
                    profileID: "profile",
                    tabID: 1,
                    url: "https://example.com/login",
                    sourceSurface: .actionClick,
                    explicitUserGesture: false,
                    sequence: 1
                ),
            gateRecord: gate,
            owner: &owner
        )
        XCTAssertFalse(blocked.granted)

        let handler = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration(manifestPermissions: ["activeTab"])
        )
        let before = handler.handle(tabsQueryRequest())
        let grant = handler.grantActiveTabFromExplicitUserAction(
            tabID: 1,
            sequence: 10
        )
        let afterGrant = handler.handle(tabsQueryRequest())
        _ = handler.applyPermissionLifecycleEvent(
            ChromeMV3PermissionLifecycleEvent(
                kind: .tabNavigated,
                extensionID: "extension",
                profileID: "profile",
                tabID: 1,
                oldURL: "https://example.com/login",
                newURL: "https://chromium.org/",
                sequence: 11
            )
        )
        let afterExpiry = handler.handle(tabsQueryRequest())

        XCTAssertNil(try firstTabObject(before.resultPayload)["url"])
        XCTAssertTrue(grant.granted)
        XCTAssertEqual(
            stringValue(try firstTabObject(afterGrant.resultPayload)["url"]),
            "https://example.com/login"
        )
        XCTAssertNil(try firstTabObject(afterExpiry.resultPayload)["url"])
        XCTAssertEqual(
            handler.permissionRuntimeSnapshot.activeTabStore.summary
                .activeGrantCount,
            0
        )
    }

    func testActiveTabExpiresOnTabCloseAndExtensionDisable() {
        for kind in [
            ChromeMV3PermissionLifecycleEventKind.tabClosed,
            .extensionDisabled,
        ] {
            let handler = ChromeMV3PopupOptionsJSBridgeHandler(
                configuration: configuration(manifestPermissions: ["activeTab"])
            )
            XCTAssertTrue(
                handler.grantActiveTabFromExplicitUserAction(
                    tabID: 1,
                    sequence: 20
                ).granted
            )

            _ = handler.applyPermissionLifecycleEvent(
                ChromeMV3PermissionLifecycleEvent(
                    kind: kind,
                    extensionID: "extension",
                    profileID: "profile",
                    tabID: 1,
                    oldURL: "https://example.com/login",
                    newURL: nil,
                    sequence: 21
                )
            )

            XCTAssertEqual(
                handler.permissionRuntimeSnapshot.activeTabStore.summary
                    .activeGrantCount,
                0
            )
        }
    }

    func testTabsConnectDistinguishesPermissionDeniedFromNoReceivingEnd() {
        let missingPermission = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration: configuration()
        )
        let noReceiver = ChromeMV3PopupOptionsJSBridgeHandler(
            configuration:
                configuration(manifestHostPermissions: ["https://example.com/*"])
        )

        let permissionResponse = missingPermission.handle(request(
            namespace: "tabs",
            methodName: "connect",
            arguments: [.number(1)]
        ))
        let receiverResponse = noReceiver.handle(request(
            namespace: "tabs",
            methodName: "connect",
            arguments: [.number(1)]
        ))

        XCTAssertFalse(permissionResponse.succeeded)
        XCTAssertEqual(permissionResponse.lastErrorCode, "hostPermissionMissing")
        XCTAssertFalse(receiverResponse.succeeded)
        XCTAssertEqual(receiverResponse.lastErrorCode, "noReceivingEnd")
    }

    func testPermissionPromptSourceGuards() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let paths = [
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3PermissionPromptProductUX.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3PopupOptionsJSBridge.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ContentScriptProductAttachment.swift",
        ]
        let source = try paths.map {
            try String(
                contentsOf: root.appendingPathComponent($0),
                encoding: .utf8
            )
        }.joined(separator: "\n")

        XCTAssertFalse(source.contains("Ti" + "mer"))
        XCTAssertFalse(source.contains("DispatchSource" + "Ti" + "mer"))
        XCTAssertFalse(source.contains("silentGrantAllowed: true"))
        XCTAssertFalse(
            source.contains("permissionPromptAvailableInPublicProduct: true")
        )
        XCTAssertFalse(
            source.contains("activeTabUXAvailableInPublicProduct: true")
        )
        XCTAssertFalse(source.contains("productRuntimeAvailable = true"))
        XCTAssertFalse(
            source.contains("productRuntime" + "Exposed = " + "true")
        )
    }

    private func configuration(
        extensionID: String = "extension",
        profileID: String = "profile",
        permissionStateRootPath: String? = nil,
        manifestPermissions: [String] = [],
        manifestOptionalPermissions: [String] = [],
        manifestHostPermissions: [String] = [],
        manifestOptionalHostPermissions: [String] = []
    ) -> ChromeMV3PopupOptionsJSBridgeConfiguration {
        ChromeMV3PopupOptionsJSBridgeConfiguration(
            extensionID: extensionID,
            profileID: profileID,
            surfaceID: "\(profileID):\(extensionID):actionPopup",
            surface: .actionPopup,
            extensionBaseURLString: "chrome-extension://\(extensionID)/",
            permissionStateRootPath: permissionStateRootPath,
            moduleState: .enabled,
            bridgeAvailable: true,
            popupOptionsJSBridgeAvailableInDeveloperPreview: true,
            popupOptionsJSBridgeAvailableInPublicProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            contentScriptAttachmentAvailableInProduct: false,
            runtimeLoadable: false,
            manifestPermissions: manifestPermissions,
            manifestOptionalPermissions: manifestOptionalPermissions,
            manifestHostPermissions: manifestHostPermissions,
            manifestOptionalHostPermissions: manifestOptionalHostPermissions,
            activeTabGrants: [],
            allowlist: .defaultPolicy,
            diagnostics: [
                "Permission prompt product UX test configuration.",
            ]
        )
    }

    private func request(
        namespace: String,
        methodName: String,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID: UUID().uuidString,
            namespace: namespace,
            methodName: methodName,
            invocationMode: .promise,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }

    private func tabsQueryRequest() -> ChromeMV3RuntimeJSBridgeHostRequest {
        request(
            namespace: "tabs",
            methodName: "query",
            arguments: [.object(["active": .bool(true)])]
        )
    }

    private func firstTabObject(
        _ value: ChromeMV3StorageValue?
    ) throws -> [String: ChromeMV3StorageValue] {
        guard case .array(let array)? = value,
              case .object(let object)? = array.first
        else {
            throw NSError(
                domain: "ChromeMV3PermissionPromptProductUXTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Expected a tab result object."]
            )
        }
        return object
    }

    private func boolValue(_ value: ChromeMV3StorageValue?) -> Bool? {
        guard case .bool(let bool)? = value else { return nil }
        return bool
    }

    private func objectValue(
        _ value: ChromeMV3StorageValue?
    ) -> [String: ChromeMV3StorageValue]? {
        guard case .object(let object)? = value else { return nil }
        return object
    }

    private func stringArrayValue(
        _ value: ChromeMV3StorageValue?
    ) -> [String] {
        guard case .array(let values)? = value else { return [] }
        return values.compactMap { value in
            guard case .string(let string) = value else { return nil }
            return string
        }
    }

    private func stringValue(_ value: ChromeMV3StorageValue?) -> String? {
        guard case .string(let string)? = value else { return nil }
        return string
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiPermissionPromptProductUXTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }
}
