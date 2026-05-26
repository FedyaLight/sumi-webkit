//
//  ChromeMV3TabsScriptingJSMVP.swift
//  Sumi
//
//  DEBUG/internal chrome.tabs and limited chrome.scripting JavaScript bridge
//  MVP for controlled synthetic extension surfaces. This is not product
//  Chrome MV3 runtime support, not normal-tab runtime exposure, not broad
//  scripting API parity, and not native messaging.
//

import CryptoKit
import Foundation

enum ChromeMV3TabsScriptingJSBridgeSurfaceKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case actionPopup
    case approvedTestSurface
    case extensionPageFixture
    case optionsPage
    case optionsUI

    static func < (
        lhs: ChromeMV3TabsScriptingJSBridgeSurfaceKind,
        rhs: ChromeMV3TabsScriptingJSBridgeSurfaceKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var runtimeSurfaceKind: ChromeMV3RuntimeJSBridgeSurfaceKind {
        switch self {
        case .actionPopup:
            return .actionPopup
        case .approvedTestSurface:
            return .approvedTestSurface
        case .extensionPageFixture:
            return .extensionPageFixture
        case .optionsPage:
            return .optionsPage
        case .optionsUI:
            return .optionsUI
        }
    }

    var sourceContext: ChromeMV3JSBridgeSourceContext {
        runtimeSurfaceKind.sourceContext
    }
}

struct ChromeMV3TabsScriptingJSBridgeConfiguration:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var surfaceID: String
    var surfaceKind: ChromeMV3TabsScriptingJSBridgeSurfaceKind
    var extensionBaseURLString: String?
    var moduleState: ChromeMV3ProfileHostModuleState
    var explicitInternalTabsScriptingJSBridgeAllowed: Bool
    var tabsJSBridgeAvailableInSyntheticHarness: Bool
    var tabsJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var scriptingAvailableInProduct: Bool
    var serviceWorkerWakeAvailable: Bool
    var serviceWorkerLifecycleAvailableInInternalFixture: Bool
    var serviceWorkerWakeAvailableInProduct: Bool
    var serviceWorkerPermanentBackgroundAvailable: Bool
    var nativeMessagingAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    var sourceContext: ChromeMV3JSBridgeSourceContext {
        surfaceKind.sourceContext
    }

    static func syntheticHarness(
        extensionID: String = "tabs-scripting-js-mvp-extension",
        profileID: String = "tabs-scripting-js-mvp-profile",
        surfaceID: String = "tabs-scripting-js-mvp-synthetic-surface",
        surfaceKind: ChromeMV3TabsScriptingJSBridgeSurfaceKind =
            .extensionPageFixture,
        extensionBaseURLString: String? =
            "chrome-extension://tabs-scripting-js-mvp-extension/",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        explicitInternalTabsScriptingJSBridgeAllowed: Bool = true
    ) -> ChromeMV3TabsScriptingJSBridgeConfiguration {
        let normalizedExtensionID = normalizedTabsScripting(
            extensionID,
            fallback: "tabs-scripting-js-mvp-extension"
        )
        let normalizedProfileID = normalizedTabsScripting(
            profileID,
            fallback: "tabs-scripting-js-mvp-profile"
        )
        let allowed = explicitInternalTabsScriptingJSBridgeAllowed
            && moduleState == .enabled
        return ChromeMV3TabsScriptingJSBridgeConfiguration(
            extensionID: normalizedExtensionID,
            profileID: normalizedProfileID,
            surfaceID: normalizedTabsScripting(
                surfaceID,
                fallback: "tabs-scripting-synthetic-surface"
            ),
            surfaceKind: surfaceKind,
            extensionBaseURLString: extensionBaseURLString,
            moduleState: moduleState,
            explicitInternalTabsScriptingJSBridgeAllowed:
                explicitInternalTabsScriptingJSBridgeAllowed,
            tabsJSBridgeAvailableInSyntheticHarness: allowed,
            tabsJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            scriptingAvailableInProduct: false,
            serviceWorkerWakeAvailable: false,
            serviceWorkerLifecycleAvailableInInternalFixture: allowed,
            serviceWorkerWakeAvailableInProduct: false,
            serviceWorkerPermanentBackgroundAvailable: false,
            nativeMessagingAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedTabsScripting([
                    "tabs/scripting JS bridge is confined to a DEBUG/internal synthetic surface.",
                    "Product tabs/scripting exposure remains unavailable.",
                    "Normal-tab runtime bridge remains unavailable.",
                    "Service-worker wake and native messaging remain unavailable.",
                    "runtimeLoadable remains false.",
                ])
        )
    }
}

enum ChromeMV3SyntheticTabControllerConfigurationStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case controlledSyntheticSameController
    case controlledSyntheticNoController
    case productNormalTabUnavailable

    static func < (
        lhs: ChromeMV3SyntheticTabControllerConfigurationStatus,
        rhs: ChromeMV3SyntheticTabControllerConfigurationStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3SyntheticContentScriptEndpointKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case dynamicExecuteScriptModel
    case staticFixture

    static func < (
        lhs: ChromeMV3SyntheticContentScriptEndpointKind,
        rhs: ChromeMV3SyntheticContentScriptEndpointKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3SyntheticTabFrameRecord:
    Codable,
    Equatable,
    Sendable
{
    var frameID: Int
    var documentID: String
    var url: String
    var origin: String?
    var parentFrameID: Int?
    var staticContentScriptEndpointRegistered: Bool
    var connectEndpointRegistered: Bool
    var controlledSyntheticExecutionAllowed: Bool
    var modeledExecuteScriptResult: ChromeMV3StorageValue?
    var diagnostics: [String]

    init(
        frameID: Int,
        documentID: String,
        url: String,
        parentFrameID: Int? = nil,
        staticContentScriptEndpointRegistered: Bool = true,
        connectEndpointRegistered: Bool = true,
        controlledSyntheticExecutionAllowed: Bool = true,
        modeledExecuteScriptResult: ChromeMV3StorageValue? = nil,
        diagnostics: [String] = []
    ) {
        self.frameID = frameID
        self.documentID = normalizedTabsScripting(
            documentID,
            fallback: "document-\(frameID)"
        )
        self.url = url
        self.origin = ChromeMV3PermissionBrokerURL.origin(from: url)
        self.parentFrameID = parentFrameID
        self.staticContentScriptEndpointRegistered =
            staticContentScriptEndpointRegistered
        self.connectEndpointRegistered = connectEndpointRegistered
        self.controlledSyntheticExecutionAllowed =
            controlledSyntheticExecutionAllowed
        self.modeledExecuteScriptResult =
            modeledExecuteScriptResult
            ?? .object([
                "ok": .bool(true),
                "target": .string("controlledSyntheticFrame"),
                "frameId": .number(Double(frameID)),
            ])
        self.diagnostics = uniqueSortedTabsScripting(diagnostics)
    }
}

struct ChromeMV3SyntheticTabRecord:
    Codable,
    Equatable,
    Sendable
{
    var id: Int
    var windowID: Int
    var profileID: String
    var url: String
    var origin: String?
    var title: String
    var active: Bool
    var highlighted: Bool
    var pinned: Bool
    var status: String
    var index: Int
    var incognito: Bool
    var controlledSyntheticSurface: Bool
    var productNormalTab: Bool
    var sameControllerConfigurationStatus:
        ChromeMV3SyntheticTabControllerConfigurationStatus
    var frames: [ChromeMV3SyntheticTabFrameRecord]
    var diagnostics: [String]

    init(
        id: Int,
        windowID: Int = 1,
        profileID: String,
        url: String,
        title: String,
        active: Bool = false,
        highlighted: Bool = false,
        pinned: Bool = false,
        status: String = "complete",
        index: Int = 0,
        incognito: Bool = false,
        controlledSyntheticSurface: Bool = true,
        productNormalTab: Bool = false,
        sameControllerConfigurationStatus:
            ChromeMV3SyntheticTabControllerConfigurationStatus =
                .controlledSyntheticSameController,
        frames: [ChromeMV3SyntheticTabFrameRecord] = [],
        diagnostics: [String] = []
    ) {
        self.id = id
        self.windowID = windowID
        self.profileID = normalizedTabsScripting(
            profileID,
            fallback: "unknown-profile"
        )
        self.url = url
        self.origin = ChromeMV3PermissionBrokerURL.origin(from: url)
        self.title = title
        self.active = active
        self.highlighted = highlighted
        self.pinned = pinned
        self.status = status.isEmpty ? "complete" : status
        self.index = index
        self.incognito = incognito
        self.controlledSyntheticSurface = controlledSyntheticSurface
        self.productNormalTab = productNormalTab
        self.sameControllerConfigurationStatus =
            sameControllerConfigurationStatus
        let mainFrame =
            ChromeMV3SyntheticTabFrameRecord(
                frameID: 0,
                documentID: "document-0",
                url: url
            )
        self.frames = (frames.isEmpty ? [mainFrame] : frames).sorted {
            $0.frameID < $1.frameID
        }
        self.diagnostics = uniqueSortedTabsScripting(diagnostics)
    }

    func frame(
        frameID: Int?,
        documentID: String?
    ) -> ChromeMV3SyntheticTabFrameRecord? {
        let selectedFrameID = frameID ?? 0
        return frames.first {
            $0.frameID == selectedFrameID
                && (documentID == nil || $0.documentID == documentID)
        }
    }
}

enum ChromeMV3SyntheticTabRedactionStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case exposedByActiveTab
    case exposedByHostPermission
    case exposedByTabsPermission
    case redactedNoPermission

    static func < (
        lhs: ChromeMV3SyntheticTabRedactionStatus,
        rhs: ChromeMV3SyntheticTabRedactionStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3SyntheticTabRedactionDecision:
    Codable,
    Equatable,
    Sendable
{
    var tabID: Int
    var status: ChromeMV3SyntheticTabRedactionStatus
    var urlVisible: Bool
    var titleVisible: Bool
    var hostAccessDecision: ChromeMV3HostAccessDecision
    var diagnostics: [String]
}

struct ChromeMV3SyntheticTabQueryResult:
    Codable,
    Equatable,
    Sendable
{
    var tabs: [ChromeMV3StorageValue]
    var redactionDecisions: [ChromeMV3SyntheticTabRedactionDecision]
    var diagnostics: [String]
}

struct ChromeMV3SyntheticContentScriptEndpointSummary:
    Codable,
    Equatable,
    Sendable
{
    var endpointCount: Int
    var staticFixtureEndpointCount: Int
    var dynamicExecuteScriptEndpointCount: Int
    var messageEndpointCount: Int
    var connectEndpointCount: Int
    var endpointIDs: [String]
    var tabsWithEndpoints: [Int]
    var productNormalTabEndpointsAvailable: Bool
    var diagnostics: [String]
}

struct ChromeMV3SyntheticTabRegistrySummary:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var controlledSyntheticTabCount: Int
    var productNormalTabCount: Int
    var registeredTabIDs: [Int]
    var queryVisibleTabIDs: [Int]
    var frameCount: Int
    var sameControllerSyntheticTabIDs: [Int]
    var productNormalTabsExcludedFromQuery: Bool
    var mutatesRealTabManagerState: Bool
    var startsBackgroundObservers: Bool
    var diagnostics: [String]
}

struct ChromeMV3SyntheticExecuteScriptRecord:
    Codable,
    Equatable,
    Sendable
{
    var executionID: String
    var tabID: Int
    var frameIDs: [Int]
    var injectionKind: String
    var argumentCount: Int
    var resultPayload: ChromeMV3StorageValue
    var executedInProductTab: Bool
    var executedByWebKitNow: Bool
    var diagnostics: [String]
}

final class ChromeMV3SyntheticTabRegistry {
    private let extensionID: String
    private let profileID: String
    private var tabsByID: [Int: ChromeMV3SyntheticTabRecord]
    private var dynamicScriptRecords: [ChromeMV3SyntheticExecuteScriptRecord]

    init(
        extensionID: String,
        profileID: String,
        tabs: [ChromeMV3SyntheticTabRecord] = []
    ) {
        self.extensionID = normalizedTabsScripting(
            extensionID,
            fallback: "unknown-extension"
        )
        self.profileID = normalizedTabsScripting(
            profileID,
            fallback: "unknown-profile"
        )
        self.tabsByID = Dictionary(uniqueKeysWithValues: tabs.map {
            ($0.id, $0)
        })
        self.dynamicScriptRecords = []
    }

    static func passwordManagerFixture(
        extensionID: String,
        profileID: String,
        includeProductNormalTab: Bool = false
    ) -> ChromeMV3SyntheticTabRegistry {
        let controlledTab = ChromeMV3SyntheticTabRecord(
            id: 1,
            windowID: 1,
            profileID: profileID,
            url: "https://example.com/login",
            title: "Example Login",
            active: true,
            highlighted: true,
            pinned: false,
            index: 0,
            frames: [
                ChromeMV3SyntheticTabFrameRecord(
                    frameID: 0,
                    documentID: "document-0",
                    url: "https://example.com/login",
                    modeledExecuteScriptResult:
                        .object([
                            "ok": .bool(true),
                            "title": .string("Example Login"),
                            "source": .string("controlledSyntheticModel"),
                        ]),
                    diagnostics: [
                        "Main frame has a static content-script fixture endpoint.",
                    ]
                ),
            ],
            diagnostics: [
                "Controlled synthetic tab fixture does not reference TabManager.",
            ]
        )
        let productTab = ChromeMV3SyntheticTabRecord(
            id: 99,
            windowID: 1,
            profileID: profileID,
            url: "https://product.example/private",
            title: "Product Normal Tab",
            active: false,
            highlighted: false,
            pinned: false,
            index: 1,
            controlledSyntheticSurface: false,
            productNormalTab: true,
            sameControllerConfigurationStatus:
                .productNormalTabUnavailable,
            frames: [
                ChromeMV3SyntheticTabFrameRecord(
                    frameID: 0,
                    documentID: "product-document-0",
                    url: "https://product.example/private",
                    staticContentScriptEndpointRegistered: false,
                    connectEndpointRegistered: false,
                    controlledSyntheticExecutionAllowed: false,
                    modeledExecuteScriptResult: nil,
                    diagnostics: [
                        "Product normal tab is present only as a negative fixture.",
                    ]
                ),
            ],
            diagnostics: [
                "Product normal tab is not eligible for JS bridge query or scripting execution.",
            ]
        )
        return ChromeMV3SyntheticTabRegistry(
            extensionID: extensionID,
            profileID: profileID,
            tabs: includeProductNormalTab
                ? [controlledTab, productTab]
                : [controlledTab]
        )
    }

    func register(_ tab: ChromeMV3SyntheticTabRecord) {
        tabsByID[tab.id] = tab
    }

    func tab(id: Int) -> ChromeMV3SyntheticTabRecord? {
        tabsByID[id]
    }

    func query(
        _ queryInfo: [String: ChromeMV3StorageValue],
        permissionBroker: ChromeMV3PermissionBroker
    ) -> ChromeMV3SyntheticTabQueryResult {
        let visibleTabs = tabsByID.values
            .filter { $0.controlledSyntheticSurface && $0.productNormalTab == false }
            .filter { matches($0, queryInfo: queryInfo, broker: permissionBroker) }
            .sorted {
                if $0.windowID != $1.windowID {
                    return $0.windowID < $1.windowID
                }
                return $0.index < $1.index
            }
        let decisions = visibleTabs.map {
            redactionDecision(tab: $0, permissionBroker: permissionBroker)
        }
        return ChromeMV3SyntheticTabQueryResult(
            tabs:
                zip(visibleTabs, decisions).map {
                    tabValue(tab: $0.0, redaction: $0.1)
                },
            redactionDecisions: decisions,
            diagnostics:
                uniqueSortedTabsScripting(
                    decisions.flatMap(\.diagnostics)
                        + [
                            "tabs.query evaluated controlled synthetic tabs only.",
                            "Product normal tabs are not returned by this registry.",
                        ]
                )
        )
    }

    func redactionDecision(
        tab: ChromeMV3SyntheticTabRecord,
        permissionBroker: ChromeMV3PermissionBroker
    ) -> ChromeMV3SyntheticTabRedactionDecision {
        let hostDecision = permissionBroker.hostAccessDecision(
            url: tab.url,
            tabID: tab.id
        )
        let tabsPermission = permissionBroker.hasAPIPermission("tabs")
        let status: ChromeMV3SyntheticTabRedactionStatus
        if tabsPermission {
            status = .exposedByTabsPermission
        } else if hostDecision.allowedByHostPermission
            || hostDecision.allowedByOptionalHostPermission
        {
            status = .exposedByHostPermission
        } else if hostDecision.allowedByActiveTab {
            status = .exposedByActiveTab
        } else {
            status = .redactedNoPermission
        }
        let visible = status != .redactedNoPermission
        return ChromeMV3SyntheticTabRedactionDecision(
            tabID: tab.id,
            status: status,
            urlVisible: visible,
            titleVisible: visible,
            hostAccessDecision: hostDecision,
            diagnostics:
                uniqueSortedTabsScripting(
                    hostDecision.diagnostics
                        + [
                            visible
                                ? "Sensitive tab URL/title fields are visible by \(status.rawValue)."
                                : "Sensitive tab URL/title fields are permission-redacted.",
                        ]
                )
        )
    }

    func target(
        tabID: Int,
        frameID: Int?,
        documentID: String?
    ) -> (tab: ChromeMV3SyntheticTabRecord, frame: ChromeMV3SyntheticTabFrameRecord)? {
        guard let tab = tab(id: tabID),
              let frame = tab.frame(frameID: frameID, documentID: documentID)
        else { return nil }
        return (tab, frame)
    }

    func listenerRegistrySnapshot()
        -> ChromeMV3RuntimeModelListenerRegistrySnapshot
    {
        var endpoints: [ChromeMV3RuntimeModelListenerEndpoint] = []
        for tab in tabsByID.values.sorted(by: { $0.id < $1.id }) {
            guard tab.controlledSyntheticSurface,
                  tab.productNormalTab == false
            else { continue }
            for frame in tab.frames.sorted(by: { $0.frameID < $1.frameID }) {
                if frame.staticContentScriptEndpointRegistered {
                    endpoints.append(
                        modelEndpoint(
                            tab: tab,
                            frame: frame,
                            surface: .tabsMessageContentScript,
                            endpointKind: .staticFixture
                        )
                    )
                    endpoints.append(
                        modelEndpoint(
                            tab: tab,
                            frame: frame,
                            surface: .runtimeOnMessageContentScript,
                            endpointKind: .staticFixture
                        )
                    )
                }
                if frame.connectEndpointRegistered {
                    endpoints.append(
                        modelEndpoint(
                            tab: tab,
                            frame: frame,
                            surface: .tabsConnectContentScript,
                            endpointKind: .staticFixture,
                            handlerOutcome: nil
                        )
                    )
                    endpoints.append(
                        modelEndpoint(
                            tab: tab,
                            frame: frame,
                            surface: .runtimeOnConnectContentScript,
                            endpointKind: .staticFixture,
                            handlerOutcome: nil
                        )
                    )
                }
            }
        }
        for record in dynamicScriptRecords {
            for frameID in record.frameIDs {
                guard let pair = target(
                    tabID: record.tabID,
                    frameID: frameID,
                    documentID: Optional<String>.none
                ) else { continue }
                endpoints.append(
                    modelEndpoint(
                        tab: pair.tab,
                        frame: pair.frame,
                        surface: .runtimeOnMessageContentScript,
                        endpointKind: .dynamicExecuteScriptModel
                    )
                )
            }
        }
        return ChromeMV3RuntimeModelListenerRegistrySnapshot.make(
            extensionID: extensionID,
            profileID: profileID,
            endpoints: endpoints,
            diagnostics: [
                "Synthetic tab registry adapted content-script endpoints for the existing runtime dispatcher.",
                "No product content script endpoint is registered.",
            ]
        )
    }

    func recordExecuteScript(
        tabID: Int,
        frameIDs: [Int],
        injectionKind: String,
        argumentCount: Int,
        resultPayload: ChromeMV3StorageValue
    ) -> ChromeMV3SyntheticExecuteScriptRecord {
        let record = ChromeMV3SyntheticExecuteScriptRecord(
            executionID:
                stableIDTabsScripting(
                    prefix: "execute-script",
                    parts: [
                        extensionID,
                        profileID,
                        String(tabID),
                        frameIDs.map(String.init).joined(separator: ","),
                        injectionKind,
                        String(dynamicScriptRecords.count + 1),
                    ]
                ),
            tabID: tabID,
            frameIDs: frameIDs,
            injectionKind: injectionKind,
            argumentCount: argumentCount,
            resultPayload: resultPayload,
            executedInProductTab: false,
            executedByWebKitNow: false,
            diagnostics: [
                "executeScript result is a controlled synthetic model envelope.",
                "No product tab script injection occurred.",
                "No arbitrary extension file was evaluated by Sumi.",
            ]
        )
        dynamicScriptRecords.append(record)
        return record
    }

    func tearDown() {
        tabsByID.removeAll()
        dynamicScriptRecords.removeAll()
    }

    var summary: ChromeMV3SyntheticTabRegistrySummary {
        let tabs = tabsByID.values.sorted { $0.id < $1.id }
        let controlled = tabs.filter {
            $0.controlledSyntheticSurface && $0.productNormalTab == false
        }
        let product = tabs.filter(\.productNormalTab)
        return ChromeMV3SyntheticTabRegistrySummary(
            extensionID: extensionID,
            profileID: profileID,
            controlledSyntheticTabCount: controlled.count,
            productNormalTabCount: product.count,
            registeredTabIDs: tabs.map(\.id),
            queryVisibleTabIDs: controlled.map(\.id),
            frameCount: controlled.flatMap(\.frames).count,
            sameControllerSyntheticTabIDs:
                controlled
                .filter {
                    $0.sameControllerConfigurationStatus
                        == ChromeMV3SyntheticTabControllerConfigurationStatus
                        .controlledSyntheticSameController
                }
                .map(\.id),
            productNormalTabsExcludedFromQuery: true,
            mutatesRealTabManagerState: false,
            startsBackgroundObservers: false,
            diagnostics:
                uniqueSortedTabsScripting(
                    tabs.flatMap(\.diagnostics)
                        + [
                            "Synthetic tab registry is deterministic and instance-local.",
                            "The registry does not observe or mutate TabManager.",
                            "The registry starts no background observers.",
                        ]
                )
        )
    }

    var contentScriptEndpointSummary:
        ChromeMV3SyntheticContentScriptEndpointSummary
    {
        let snapshot = listenerRegistrySnapshot()
        let endpoints = snapshot.endpoints
        return ChromeMV3SyntheticContentScriptEndpointSummary(
            endpointCount: endpoints.count,
            staticFixtureEndpointCount:
                endpoints.filter {
                    $0.diagnostics.contains {
                        $0.contains("static fixture endpoint")
                    }
                }.count,
            dynamicExecuteScriptEndpointCount:
                dynamicScriptRecords.reduce(0) {
                    $0 + $1.frameIDs.count
                },
            messageEndpointCount:
                endpoints.filter {
                    $0.listenerSurface.surface == .tabsMessageContentScript
                        || $0.listenerSurface.surface
                        == .runtimeOnMessageContentScript
                }.count,
            connectEndpointCount:
                endpoints.filter {
                    $0.listenerSurface.surface == .tabsConnectContentScript
                        || $0.listenerSurface.surface
                        == .runtimeOnConnectContentScript
                }.count,
            endpointIDs: endpoints.map(\.endpointID).sorted(),
            tabsWithEndpoints:
                endpoints.compactMap(\.listenerSurface.tabID).uniqueSorted(),
            productNormalTabEndpointsAvailable: false,
            diagnostics:
                uniqueSortedTabsScripting(
                    snapshot.diagnostics
                        + endpoints.flatMap(\.diagnostics)
                        + dynamicScriptRecords.flatMap(\.diagnostics)
                        + [
                            "Content-script endpoints are modeled per synthetic tab/frame.",
                            "Static fixture endpoints and dynamically executed script records are reported separately.",
                        ]
                )
        )
    }

    private func matches(
        _ tab: ChromeMV3SyntheticTabRecord,
        queryInfo: [String: ChromeMV3StorageValue],
        broker: ChromeMV3PermissionBroker
    ) -> Bool {
        if let active = queryInfo["active"]?.boolValue,
           tab.active != active
        {
            return false
        }
        if let highlighted = queryInfo["highlighted"]?.boolValue,
           tab.highlighted != highlighted
        {
            return false
        }
        if let pinned = queryInfo["pinned"]?.boolValue,
           tab.pinned != pinned
        {
            return false
        }
        if let status = queryInfo["status"]?.stringValue,
           tab.status != status
        {
            return false
        }
        if let windowID = queryInfo["windowId"]?.intValue,
           tab.windowID != windowID
        {
            return false
        }
        if let currentWindow = queryInfo["currentWindow"]?.boolValue,
           currentWindow && tab.windowID != 1
        {
            return false
        }
        if let title = queryInfo["title"]?.stringValue,
           redactionDecision(tab: tab, permissionBroker: broker)
            .titleVisible,
           tab.title.range(of: title, options: [.caseInsensitive]) == nil
        {
            return false
        }
        if let url = queryInfo["url"] {
            let patterns: [String]
            if let single = url.stringValue {
                patterns = [single]
            } else if case .array(let values) = url {
                patterns = values.compactMap(\.stringValue)
            } else {
                patterns = []
            }
            if patterns.isEmpty == false,
               redactionDecision(tab: tab, permissionBroker: broker)
                .urlVisible,
               patterns.contains(where: {
                   ChromeMV3HostMatchPattern($0).matches(url: tab.url)
               }) == false
            {
                return false
            }
        }
        return true
    }

    private func tabValue(
        tab: ChromeMV3SyntheticTabRecord,
        redaction: ChromeMV3SyntheticTabRedactionDecision
    ) -> ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "active": .bool(tab.active),
            "highlighted": .bool(tab.highlighted),
            "id": .number(Double(tab.id)),
            "incognito": .bool(tab.incognito),
            "index": .number(Double(tab.index)),
            "pinned": .bool(tab.pinned),
            "status": .string(tab.status),
            "windowId": .number(Double(tab.windowID)),
        ]
        if redaction.urlVisible {
            object["url"] = .string(tab.url)
        }
        if redaction.titleVisible {
            object["title"] = .string(tab.title)
        }
        return .object(object)
    }

    private func modelEndpoint(
        tab: ChromeMV3SyntheticTabRecord,
        frame: ChromeMV3SyntheticTabFrameRecord,
        surface: ChromeMV3RuntimeListenerSurfaceKind,
        endpointKind: ChromeMV3SyntheticContentScriptEndpointKind,
        handlerOutcome:
            ChromeMV3RuntimeModelHandlerOutcome? =
                .response(
                    .object([
                        "detectedFields": .object([
                            "formId": .string("synthetic-login-form"),
                            "loginPageURL": .string("https://example.com/login"),
                            "password": .object([
                                "autocomplete": .string("current-password"),
                                "fieldId": .string("password"),
                                "name": .string("password"),
                                "selector": .string("#password"),
                                "type": .string("password"),
                            ]),
                            "submit": .object([
                                "buttonId": .string("submit-login"),
                                "selector": .string("#submit-login"),
                                "type": .string("submit"),
                            ]),
                            "username": .object([
                                "autocomplete": .string("username"),
                                "fieldId": .string("username"),
                                "name": .string("username"),
                                "selector": .string("#username"),
                                "type": .string("email"),
                            ]),
                        ]),
                        "fillResult": .object([
                            "fieldsFilled": .array([
                                .string("username"),
                                .string("password"),
                            ]),
                            "formId": .string("synthetic-login-form"),
                            "submitted": .bool(false),
                            "success": .bool(true),
                        ]),
                        "ok": .bool(true),
                        "supportedCommands": .array([
                            .string("detectFields"),
                            .string("fillFields"),
                        ]),
                        "target": .string("syntheticContentScriptModel"),
                    ])
                )
    ) -> ChromeMV3RuntimeModelListenerEndpoint {
        let listenerSurface = ChromeMV3RuntimeListenerSurface.make(
            surface: surface,
            extensionID: extensionID,
            profileID: profileID,
            tabID: tab.id,
            frameID: frame.frameID
        )
        let outcome = handlerOutcome.map { outcome in
            ChromeMV3RuntimeModelHandlerOutcome(
                kind: outcome.kind,
                responsePayload:
                    outcome.responsePayload.map {
                        enrichedContentScriptResponse(
                            payload: $0,
                            tab: tab,
                            frame: frame
                        )
                    },
                error: outcome.error,
                diagnostics: outcome.diagnostics
            )
        }
        return ChromeMV3RuntimeModelListenerEndpoint.make(
            surface: listenerSurface,
            endpointKind: .contentScriptModel,
            canReceiveModelMessages: true,
            bypassesServiceWorkerWakeForModelOnlyDispatch: true,
            handlerOutcome: outcome,
            seed:
                "tabs-scripting-\(endpointKind.rawValue)-\(surface.rawValue)-\(tab.id)-\(frame.frameID)",
            diagnostics: [
                "Synthetic \(endpointKind.rawValue) content-script endpoint is scoped to tab \(tab.id), frame \(frame.frameID).",
                "Endpoint is a static fixture endpoint: \(endpointKind == .staticFixture).",
                "No product normal-tab endpoint is registered.",
            ]
        )
    }

    private func enrichedContentScriptResponse(
        payload: ChromeMV3StorageValue,
        tab: ChromeMV3SyntheticTabRecord,
        frame: ChromeMV3SyntheticTabFrameRecord
    ) -> ChromeMV3StorageValue {
        guard case .object(var object) = payload else { return payload }
        object["tabId"] = .number(Double(tab.id))
        object["frameId"] = .number(Double(frame.frameID))
        object["documentId"] = .string(frame.documentID)
        return .object(object)
    }
}

struct ChromeMV3TabsScriptingNormalizedTabTarget:
    Codable,
    Equatable,
    Sendable
{
    var tabID: Int
    var frameID: Int?
    var documentID: String?
}

struct ChromeMV3ScriptingExecuteScriptNormalizedRequest:
    Codable,
    Equatable,
    Sendable
{
    var target: ChromeMV3TabsScriptingNormalizedTabTarget
    var frameIDs: [Int]?
    var injectionKind: String
    var files: [String]
    var functionSource: String?
    var arguments: [ChromeMV3StorageValue]
}

struct ChromeMV3TabsScriptingArgumentError:
    Error,
    Equatable,
    Sendable
{
    var message: String
}

struct ChromeMV3TabsScriptingJSBridgeHostResponse:
    Codable,
    Equatable,
    Sendable
{
    var bridgeCallID: String
    var namespace: String
    var methodName: String
    var succeeded: Bool
    var resultPayload: ChromeMV3StorageValue?
    var lastErrorMessage: String?
    var lastErrorCode: String?
    var callbackWouldSetLastError: Bool
    var promiseWouldReject: Bool
    var runtimeDispatcherResult:
        ChromeMV3RuntimeMessageDispatcherResult?
    var permissionsContainsResult:
        ChromeMV3PermissionsAPIContainsResult?
    var permissionsGetAllResult:
        ChromeMV3PermissionsAPIGetAllResult?
    var permissionsRequestResult:
        ChromeMV3PermissionsAPIRequestResult?
    var permissionsRemoveResult:
        ChromeMV3PermissionsAPIRemoveResult?
    var tabRegistrySummary: ChromeMV3SyntheticTabRegistrySummary
    var contentScriptEndpointSummary:
        ChromeMV3SyntheticContentScriptEndpointSummary
    var tabsJSBridgeAvailableInSyntheticHarness: Bool
    var tabsJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var scriptingAvailableInProduct: Bool
    var serviceWorkerWakeAvailable: Bool
    var serviceWorkerLifecycleAvailableInInternalFixture: Bool
    var serviceWorkerWakeAvailableInProduct: Bool
    var serviceWorkerPermanentBackgroundAvailable: Bool
    var nativeMessagingAvailable: Bool
    var runtimeLoadable: Bool
    var serviceWorkerLifecycleWakeResult:
        ChromeMV3ServiceWorkerInternalWakeResult?
    var diagnostics: [String]

    var foundationObject: [String: Any] {
        [
            "bridgeCallID": bridgeCallID,
            "namespace": namespace,
            "methodName": methodName,
            "succeeded": succeeded,
            "resultPayload":
                resultPayload?.tabsScriptingFoundationObject
                ?? NSNull(),
            "lastErrorMessage": lastErrorMessage ?? NSNull(),
            "lastErrorCode": lastErrorCode ?? NSNull(),
            "permissionEventPayload": permissionEventFoundationObject,
            "callbackWouldSetLastError": callbackWouldSetLastError,
            "promiseWouldReject": promiseWouldReject,
            "tabsJSBridgeAvailableInSyntheticHarness":
                tabsJSBridgeAvailableInSyntheticHarness,
            "tabsJSBridgeAvailableInProduct":
                tabsJSBridgeAvailableInProduct,
            "normalTabRuntimeBridgeAvailable":
                normalTabRuntimeBridgeAvailable,
            "scriptingAvailableInProduct": scriptingAvailableInProduct,
            "serviceWorkerWakeAvailable": serviceWorkerWakeAvailable,
            "serviceWorkerLifecycleAvailableInInternalFixture":
                serviceWorkerLifecycleAvailableInInternalFixture,
            "serviceWorkerWakeAvailableInProduct":
                serviceWorkerWakeAvailableInProduct,
            "serviceWorkerPermanentBackgroundAvailable":
                serviceWorkerPermanentBackgroundAvailable,
            "nativeMessagingAvailable": nativeMessagingAvailable,
            "serviceWorkerLifecycleWakeResult":
                serviceWorkerLifecycleWakeResultFoundationObject,
            "runtimeLoadable": runtimeLoadable,
            "diagnostics": diagnostics,
        ]
    }

    private var serviceWorkerLifecycleWakeResultFoundationObject: Any {
        guard let serviceWorkerLifecycleWakeResult,
              let data = try? JSONEncoder().encode(
                serviceWorkerLifecycleWakeResult
              ),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return NSNull() }
        return object
    }

    private var permissionEventFoundationObject: Any {
        let payload =
            permissionsRequestResult?.eventPayloadIfAccepted
            ?? permissionsRemoveResult?.eventPayloadIfApplied
        guard let payload else { return NSNull() }
        return ChromeMV3StorageValue.permissionEventPayload(payload)
            .tabsScriptingFoundationObject
    }
}

final class ChromeMV3TabsScriptingJSBridgeHandler {
    let configuration: ChromeMV3TabsScriptingJSBridgeConfiguration
    let tabRegistry: ChromeMV3SyntheticTabRegistry
    private var permissionRuntimeOwner: ChromeMV3PermissionRuntimeStateOwner
    private(set) var handledRequestCount = 0
    private(set) var queryRequestCount = 0
    private(set) var permissionsRequestCount = 0
    private(set) var sendMessageDispatchCount = 0
    private(set) var modelPortCreateCount = 0
    private(set) var modelPortDisconnectCount = 0
    private(set) var modelPortPostMessageCount = 0
    private(set) var executeScriptRequestCount = 0
    private(set) var rejectedRequestCount = 0
    private let serviceWorkerLifecycleOwner:
        ChromeMV3ServiceWorkerInternalLifecycleRuntimeOwner?
    private let sharedLifecycleSession:
        ChromeMV3ServiceWorkerSharedLifecycleSession?
    private let lifecycleComponentID: String

    init(
        configuration: ChromeMV3TabsScriptingJSBridgeConfiguration,
        tabRegistry: ChromeMV3SyntheticTabRegistry? = nil,
        permissionBroker: ChromeMV3PermissionBroker? = nil,
        permissionRuntimeOwner:
            ChromeMV3PermissionRuntimeStateOwner? = nil,
        sharedLifecycleSession:
            ChromeMV3ServiceWorkerSharedLifecycleSession? = nil
    ) {
        self.configuration = configuration
        self.sharedLifecycleSession = sharedLifecycleSession
        self.lifecycleComponentID =
            "tabs-scripting-harness:\(configuration.surfaceID)"
        self.tabRegistry =
            tabRegistry
            ?? ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                includeProductNormalTab: false
            )
        self.permissionRuntimeOwner =
            permissionRuntimeOwner
            ?? permissionBroker.map {
                ChromeMV3PermissionRuntimeStateOwner(permissionBroker: $0)
            }
            ?? ChromeMV3PermissionRuntimeStateOwner(
                permissionBroker:
                    ChromeMV3TabsScriptingPermissionFixtures
                    .hostAndScripting(
                        extensionID: configuration.extensionID,
                        profileID: configuration.profileID
                    )
            )
        if configuration.serviceWorkerLifecycleAvailableInInternalFixture {
            let owner: ChromeMV3ServiceWorkerInternalLifecycleRuntimeOwner
            if let sharedLifecycleSession {
                _ = sharedLifecycleSession.attachComponent(
                    kind: .tabsScriptingHarness,
                    componentID: lifecycleComponentID,
                    eventSurfaces: [.tabsOnMessage, .tabsOnConnect],
                    keepaliveSources: [.tabsPort]
                )
                owner = sharedLifecycleSession.runtimeOwner
            } else {
                owner = ChromeMV3ServiceWorkerInternalLifecycleRuntimeOwner(
                    configuration: .internalFixture(
                        extensionID: configuration.extensionID,
                        profileID: configuration.profileID,
                        moduleState: configuration.moduleState,
                        explicitInternalLifecycleAllowed:
                            configuration
                            .explicitInternalTabsScriptingJSBridgeAllowed
                    )
                )
            }
            owner.registerListener(
                event: .tabsOnMessage,
                listenerID: "tabs-js-tabs-on-message"
            )
            owner.registerListener(
                event: .tabsOnConnect,
                listenerID: "tabs-js-tabs-on-connect"
            )
            self.serviceWorkerLifecycleOwner = owner
        } else {
            self.serviceWorkerLifecycleOwner = nil
        }
    }

    var permissionBroker: ChromeMV3PermissionBroker {
        permissionRuntimeOwner.permissionBroker
    }

    var permissionRuntimeSnapshot:
        ChromeMV3PermissionRuntimeStateOwnerSnapshot
    {
        permissionRuntimeOwner.snapshot
    }

    @discardableResult
    func grantActiveTabFromGesture(
        tabID: Int,
        url: String,
        reason: ChromeMV3ActiveTabGrantReason = .testFixture,
        userGestureModeled: Bool = true,
        sequence: Int = 1
    ) -> ChromeMV3ActiveTabRuntimeGrantResult {
        permissionRuntimeOwner.grantActiveTabFromGesture(
            ChromeMV3ActiveTabGestureEvent(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                tabID: tabID,
                url: url,
                reason: reason,
                userGestureModeled: userGestureModeled,
                sequence: sequence
            )
        )
    }

    @discardableResult
    func expireActiveTabForNavigation(
        tabID: Int,
        oldURL: String,
        newURL: String,
        sequence: Int = 2
    ) -> ChromeMV3PermissionRuntimeLifecycleApplication {
        permissionRuntimeOwner.applyLifecycleEvent(
            ChromeMV3PermissionLifecycleEvent(
                kind: .tabNavigated,
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                tabID: tabID,
                oldURL: oldURL,
                newURL: newURL,
                sequence: sequence
            )
        )
    }

    @discardableResult
    func resetActiveTabGrants(
        sequence: Int = 3
    ) -> ChromeMV3PermissionRuntimeLifecycleApplication {
        permissionRuntimeOwner.resetActiveTabGrants(sequence: sequence)
    }

    func handle(_ body: Any) -> ChromeMV3TabsScriptingJSBridgeHostResponse {
        handledRequestCount += 1
        switch ChromeMV3RuntimeJSBridgeHostRequest.parse(body) {
        case .success(let request):
            return handle(request)
        case .failure(let error):
            rejectedRequestCount += 1
            return response(
                request: nil,
                methodName: "parse",
                succeeded: false,
                lastErrorMessage: error.message,
                lastErrorCode: ChromeMV3JSBridgeErrorCode.invalidArguments
                    .rawValue,
                diagnostics: [error.message]
            )
        }
    }

    func handle(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3TabsScriptingJSBridgeHostResponse {
        guard configuration.moduleState == .enabled,
              configuration.explicitInternalTabsScriptingJSBridgeAllowed
        else {
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled
                    .lastErrorMessage,
                lastErrorCode: ChromeMV3JSBridgeErrorCode.extensionDisabled
                    .rawValue,
                diagnostics: [
                    "tabs/scripting JS bridge request blocked because the extensions module or explicit DEBUG/internal gate is disabled.",
                ]
            )
        }

        switch (request.namespace, request.methodName) {
        case ("permissions", "contains"):
            return permissionsContains(request)
        case ("permissions", "getAll"):
            return permissionsGetAll(request)
        case ("permissions", "request"):
            return permissionsRequest(request)
        case ("permissions", "remove"):
            return permissionsRemove(request)
        case ("tabs", "query"):
            return query(request)
        case ("tabs", "sendMessage"):
            return sendMessage(request)
        case ("tabs", "connect"):
            return connect(request)
        case ("tabs", "Port.disconnect"):
            modelPortDisconnectCount += 1
            let disconnected =
                serviceWorkerLifecycleOwner?.disconnectKeepalive(
                    portID: request.portID,
                    reason: .reset
                ) ?? false
            return response(
                request: request,
                succeeded: true,
                payload: .object([
                    "portID": .string(request.portID ?? "unknown-port"),
                    "disconnectReason": .string("disconnectCalled"),
                    "serviceWorkerKeepaliveDisconnected":
                        .bool(disconnected),
                    "runtimeLoadable": .bool(false),
                ]),
                diagnostics: [
                    "Synthetic tabs Port disconnect was recorded without opening a native or runtime Port.",
                    disconnected
                        ? "Internal fixture tabs Port keepalive was released."
                        : "No internal fixture tabs Port keepalive matched the disconnect.",
                ]
            )
        case ("tabs", "Port.postMessage"):
            modelPortPostMessageCount += 1
            return response(
                request: request,
                succeeded: true,
                payload: .object([
                    "portID": .string(request.portID ?? "unknown-port"),
                    "postMessageDeliveredByNativeRuntime": .bool(false),
                    "messageExchangeMode": .string("syntheticTabsPortOnly"),
                ]),
                diagnostics: [
                    "Synthetic tabs Port postMessage is model-only; native/runtime delivery is unavailable.",
                ]
            )
        case ("scripting", "executeScript"):
            return executeScript(request)
        default:
            rejectedRequestCount += 1
            let namespaceSupported =
                request.namespace == "permissions"
                    || request.namespace == "tabs"
                    || request.namespace == "scripting"
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    (namespaceSupported
                        ? ChromeMV3JSBridgeErrorCode.methodUnsupported
                        : ChromeMV3JSBridgeErrorCode.namespaceUnsupported)
                    .lastErrorMessage,
                lastErrorCode:
                    (namespaceSupported
                        ? ChromeMV3JSBridgeErrorCode.methodUnsupported
                        : ChromeMV3JSBridgeErrorCode.namespaceUnsupported)
                    .rawValue,
                diagnostics: [
                    "Unsupported tabs/scripting JS MVP bridge route: \(request.namespace).\(request.methodName).",
                ]
            )
        }
    }

    func tearDown() {
        tabRegistry.tearDown()
        if sharedLifecycleSession != nil {
            _ = sharedLifecycleSession?.detachComponent(
                componentID: lifecycleComponentID,
                reason: .reset
            )
        } else {
            serviceWorkerLifecycleOwner?.tearDownForExtensionDisable()
        }
    }

    private func permissionsContains(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3TabsScriptingJSBridgeHostResponse {
        permissionsRequestCount += 1
        switch permissionsInput(request, requiresObjectArgument: true) {
        case .failure(let error):
            rejectedRequestCount += 1
            return invalidArguments(request, error.message)
        case .success(let input):
            let result = permissionRuntimeOwner.contains(input: input)
            return response(
                request: request,
                succeeded: true,
                payload: .bool(result.wouldReturn),
                permissionsContainsResult: result,
                diagnostics: result.diagnostics
            )
        }
    }

    private func permissionsGetAll(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3TabsScriptingJSBridgeHostResponse {
        permissionsRequestCount += 1
        guard request.arguments.isEmpty else {
            rejectedRequestCount += 1
            return invalidArguments(
                request,
                "permissions.getAll does not accept arguments."
            )
        }
        let result = permissionRuntimeOwner.getAll()
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "permissions": .array(
                    result.permissions.map(ChromeMV3StorageValue.string)
                ),
                "origins": .array(
                    result.origins.map(ChromeMV3StorageValue.string)
                ),
            ]),
            permissionsGetAllResult: result,
            diagnostics: result.diagnostics
        )
    }

    private func permissionsRequest(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3TabsScriptingJSBridgeHostResponse {
        permissionsRequestCount += 1
        switch permissionsInput(request, requiresObjectArgument: true) {
        case .failure(let error):
            rejectedRequestCount += 1
            return invalidArguments(request, error.message)
        case .success(let input):
            let promptResult = modeledPromptResult(
                from: request.arguments.first
            )
            let application = permissionRuntimeOwner.request(
                input: input,
                modeledPromptResult: promptResult
            )
            let alreadyGranted = application.result.wouldBeAllowedByModel
            let allowedByPromptModel =
                application.result.wouldGrantIfUserAccepted
                    && (promptResult == .accepted || promptResult == .denied)
            guard alreadyGranted || allowedByPromptModel else {
                rejectedRequestCount += 1
                let failure = permissionsRequestFailure(
                    for: application.result
                )
                return response(
                    request: request,
                    succeeded: false,
                    payload: .bool(false),
                    lastErrorMessage: failure.message,
                    lastErrorCode: failure.code,
                    permissionsRequestResult: application.result,
                    diagnostics:
                        uniqueSortedTabsScripting(
                            application.diagnostics
                                + failure.diagnostics
                        )
                )
            }
            return response(
                request: request,
                succeeded: true,
                payload: .bool(application.returnedBoolean),
                permissionsRequestResult: application.result,
                diagnostics: application.diagnostics
            )
        }
    }

    private func permissionsRequestFailure(
        for result: ChromeMV3PermissionsAPIRequestResult
    ) -> (code: String, message: String, diagnostics: [String]) {
        let classifications = result.itemDecisions.map(\.classification)
        if result.wouldRequirePrompt {
            return (
                "productUIUnavailable",
                "Permission promptRequired, but product permission UI is unavailable in the internal synthetic harness.",
                [
                    "Request requires a permission prompt.",
                    "permissionUIAvailableInProduct remains false.",
                    "Provide an explicit modeled prompt result in internal tests.",
                ]
            )
        }
        if classifications.contains(.missingUserGesture) {
            return (
                "promptRequiredUserGestureMissing",
                "chrome.permissions.request requires a modeled user gesture before prompting.",
                ["Request was blocked because no modeled user gesture was supplied."]
            )
        }
        if classifications.contains(.notDeclaredOptional) {
            return (
                "permissionNotDeclaredOptional",
                "Requested permission or origin is not declared optional.",
                ["Only declared optional permissions can be granted by this synthetic bridge."]
            )
        }
        if classifications.contains(.unsupportedPermission) {
            return (
                "unsupportedPermission",
                "Requested permission or origin is unsupported by the modeled contract.",
                ["Unsupported permission request was rejected deterministically."]
            )
        }
        if classifications.contains(.deniedByPolicy) {
            return (
                "permissionDenied",
                "Requested permission is denied by the internal permission state.",
                ["Denied permission request was rejected deterministically."]
            )
        }
        return (
            "permissionRequestRejected",
            "chrome.permissions.request was rejected by internal permission state.",
            ["Permission request was not grantable by the synthetic bridge."]
        )
    }

    private func permissionsRemove(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3TabsScriptingJSBridgeHostResponse {
        permissionsRequestCount += 1
        switch permissionsInput(request, requiresObjectArgument: true) {
        case .failure(let error):
            rejectedRequestCount += 1
            return invalidArguments(request, error.message)
        case .success(let input):
            let application = permissionRuntimeOwner.remove(input: input)
            return response(
                request: request,
                succeeded: true,
                payload: .bool(application.returnedBoolean),
                permissionsRemoveResult: application.result,
                diagnostics: application.diagnostics
            )
        }
    }

    private func query(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3TabsScriptingJSBridgeHostResponse {
        queryRequestCount += 1
        guard request.arguments.count <= 1 else {
            rejectedRequestCount += 1
            return invalidArguments(
                request,
                "tabs.query accepts one queryInfo object."
            )
        }
        guard let queryInfo = request.arguments.first?.objectValue
            ?? (request.arguments.isEmpty ? [:] : nil)
        else {
            rejectedRequestCount += 1
            return invalidArguments(
                request,
                "tabs.query queryInfo must be an object."
            )
        }
        let result = tabRegistry.query(
            queryInfo,
            permissionBroker: permissionBroker
        )
        return response(
            request: request,
            succeeded: true,
            payload: .array(result.tabs),
            diagnostics:
                uniqueSortedTabsScripting(
                    result.diagnostics
                        + [
                            "tabs.query returned deterministic permission-redacted synthetic Tab records.",
                        ]
                )
        )
    }

    private func sendMessage(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3TabsScriptingJSBridgeHostResponse {
        sendMessageDispatchCount += 1
        let normalized = normalizeTabsMessageTarget(request)
        switch normalized {
        case .failure(let error):
            rejectedRequestCount += 1
            return invalidArguments(request, error.message)
        case .success(let target):
            guard let pair = tabRegistry.target(
                tabID: target.tabID,
                frameID: target.frameID,
                documentID: target.documentID
            ) else {
                rejectedRequestCount += 1
                return runtimeError(
                    request,
                    target.documentID == nil && target.frameID == nil
                        ? .targetTabMissing
                        : tabRegistry.tab(id: target.tabID) == nil
                            ? .targetTabMissing
                            : .targetFrameMissing,
                    diagnostics: [
                        "tabs.sendMessage target tab/frame was not found in the synthetic tab registry.",
                    ]
                )
            }
            let permissionError = hostPermissionError(
                tab: pair.tab,
                requestName: "tabs.sendMessage"
            )
            if let permissionError {
                rejectedRequestCount += 1
                return runtimeError(
                    request,
                    permissionError,
                    diagnostics: [
                        "tabs.sendMessage target failed host/activeTab permission checks.",
                    ]
                )
            }
            let route = ChromeMV3RuntimeMessagingRoute.make(
                kind: .tabsSendMessage,
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                tabID: pair.tab.id,
                frameID: pair.frame.frameID,
                documentID: pair.frame.documentID,
                sourceURL: pair.frame.url,
                targetURL: pair.frame.url
            )
            let dispatcherResult = dispatch(
                request: request,
                route: route,
                expectsResponse: true
            )
            let lifecycleResult = serviceWorkerLifecycleOwner?.requestWake(
                reason: .tabsMessage,
                listenerEvent: .tabsOnMessage,
                payload: request.arguments.dropFirst().first,
                payloadSummary: "tabs.sendMessage",
                sourceContext: configuration.sourceContext.runtimeContext,
                sourceComponentID: lifecycleComponentID,
                sourceComponentKind: .tabsScriptingHarness
            )
            if let error = dispatcherResult.selectedLastError?.error {
                rejectedRequestCount += 1
                return runtimeError(
                    request,
                    error,
                    runtimeDispatcherResult: dispatcherResult,
                    serviceWorkerLifecycleWakeResult: lifecycleResult,
                    diagnostics: dispatcherResult.diagnostics
                )
            }
            return response(
                request: request,
                succeeded: true,
                payload: dispatcherResult.responsePayload ?? .null,
                runtimeDispatcherResult: dispatcherResult,
                serviceWorkerLifecycleWakeResult: lifecycleResult,
                diagnostics:
                    uniqueSortedTabsScripting(
                        dispatcherResult.diagnostics
                            + [
                                "tabs.sendMessage routed through the existing Swift runtime dispatcher using a synthetic content-script endpoint.",
                            ]
                    )
            )
        }
    }

    private func connect(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3TabsScriptingJSBridgeHostResponse {
        let normalized = normalizeTabsConnectTarget(request)
        switch normalized {
        case .failure(let error):
            rejectedRequestCount += 1
            return invalidArguments(request, error.message)
        case .success(let target):
            guard let pair = tabRegistry.target(
                tabID: target.tabID,
                frameID: target.frameID,
                documentID: target.documentID
            ) else {
                rejectedRequestCount += 1
                return runtimeError(
                    request,
                    tabRegistry.tab(id: target.tabID) == nil
                        ? .targetTabMissing
                        : .targetFrameMissing,
                    diagnostics: [
                        "tabs.connect target tab/frame was not found in the synthetic tab registry.",
                    ]
                )
            }
            let permissionError = hostPermissionError(
                tab: pair.tab,
                requestName: "tabs.connect"
            )
            if let permissionError {
                rejectedRequestCount += 1
                return runtimeError(
                    request,
                    permissionError,
                    diagnostics: [
                        "tabs.connect target failed host/activeTab permission checks.",
                    ]
                )
            }
            guard pair.frame.connectEndpointRegistered else {
                rejectedRequestCount += 1
                return runtimeError(
                    request,
                    .noReceivingEnd,
                    diagnostics: [
                        "No modeled content-script runtime.onConnect endpoint exists for the requested tab/frame.",
                    ]
                )
            }
            let route = ChromeMV3RuntimeMessagingRoute.make(
                kind: .tabsConnect,
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                tabID: pair.tab.id,
                frameID: pair.frame.frameID,
                documentID: pair.frame.documentID,
                sourceURL: pair.frame.url,
                targetURL: pair.frame.url
            )
            let dispatcherResult = dispatch(
                request: request,
                route: route,
                expectsResponse: false
            )
            guard let preflight = dispatcherResult.modelPortPreflight else {
                let lifecycleResult = serviceWorkerLifecycleOwner?.requestWake(
                    reason: .tabsConnect,
                    listenerEvent: .tabsOnConnect,
                    payload: request.arguments.dropFirst().first,
                    payloadSummary: "tabs.connect",
                    sourceContext: configuration.sourceContext.runtimeContext,
                    sourceComponentID: lifecycleComponentID,
                    sourceComponentKind: .tabsScriptingHarness
                )
                rejectedRequestCount += 1
                return runtimeError(
                    request,
                    .routeNotImplemented,
                    runtimeDispatcherResult: dispatcherResult,
                    serviceWorkerLifecycleWakeResult: lifecycleResult,
                    diagnostics: dispatcherResult.diagnostics
                )
            }
            modelPortCreateCount += 1
            let lifecycleResult = serviceWorkerLifecycleOwner?.requestWake(
                reason: .tabsConnect,
                listenerEvent: .tabsOnConnect,
                payload: request.arguments.dropFirst().first,
                payloadSummary: "tabs.connect",
                sourceContext: configuration.sourceContext.runtimeContext,
                keepaliveKind: .tabsPort,
                portID: preflight.portID,
                sourceComponentID: lifecycleComponentID,
                sourceComponentKind: .tabsScriptingHarness
            )
            return response(
                request: request,
                succeeded: true,
                payload: .object([
                    "portID": .string(preflight.portID),
                    "portKind": .string(preflight.portKind.rawValue),
                    "tabId": .number(Double(pair.tab.id)),
                    "frameId": .number(Double(pair.frame.frameID)),
                    "documentId": .string(pair.frame.documentID),
                    "canOpenRuntimePortNow": .bool(false),
                    "canOpenNativePortNow": .bool(false),
                    "canWakeServiceWorkerNow": .bool(false),
                    "modelPortCreated": .bool(true),
                    "runtimeLoadable": .bool(false),
                ]),
                runtimeDispatcherResult: dispatcherResult,
                serviceWorkerLifecycleWakeResult: lifecycleResult,
                diagnostics:
                    uniqueSortedTabsScripting(
                        dispatcherResult.diagnostics
                            + [
                                "tabs.connect routed through dispatcher Port preflight and created only a synthetic model Port.",
                                "The dispatcher still reports no real runtime Port opening.",
                            ]
                    )
            )
        }
    }

    private func executeScript(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3TabsScriptingJSBridgeHostResponse {
        executeScriptRequestCount += 1
        let normalized = normalizeExecuteScript(request)
        switch normalized {
        case .failure(let error):
            rejectedRequestCount += 1
            return invalidArguments(request, error.message)
        case .success(let input):
            guard permissionBroker.hasAPIPermission("scripting") else {
                rejectedRequestCount += 1
                return runtimeError(
                    request,
                    .permissionDenied,
                    diagnostics: [
                        "scripting.executeScript requires the modeled scripting API permission.",
                    ]
                )
            }
            guard let tab = tabRegistry.tab(id: input.target.tabID) else {
                rejectedRequestCount += 1
                return runtimeError(
                    request,
                    .targetTabMissing,
                    diagnostics: [
                        "scripting.executeScript target tab is missing from the synthetic registry.",
                    ]
                )
            }
            guard tab.controlledSyntheticSurface,
                  tab.productNormalTab == false,
                  tab.sameControllerConfigurationStatus
                    == ChromeMV3SyntheticTabControllerConfigurationStatus
                    .controlledSyntheticSameController
            else {
                rejectedRequestCount += 1
                return runtimeError(
                    request,
                    .unsupportedAPI,
                    diagnostics: [
                        "scripting.executeScript is blocked outside controlled synthetic tabs.",
                        "No product normal-tab script injection is performed.",
                    ]
                )
            }
            let permissionError = hostPermissionError(
                tab: tab,
                requestName: "scripting.executeScript"
            )
            if let permissionError {
                rejectedRequestCount += 1
                return runtimeError(
                    request,
                    permissionError,
                    diagnostics: [
                        "scripting.executeScript target failed host/activeTab permission checks.",
                    ]
                )
            }
            let selectedFrames: [ChromeMV3SyntheticTabFrameRecord]
            if let frameIDs = input.frameIDs {
                selectedFrames = frameIDs.compactMap {
                    tab.frame(frameID: $0, documentID: Optional<String>.none)
                }
                guard selectedFrames.count == frameIDs.count else {
                    rejectedRequestCount += 1
                    return runtimeError(
                        request,
                        .targetFrameMissing,
                        diagnostics: [
                            "scripting.executeScript requested a frame not modeled in the synthetic tab.",
                        ]
                    )
                }
            } else {
                guard let frame = tab.frame(
                    frameID: input.target.frameID,
                    documentID: input.target.documentID
                ) else {
                    rejectedRequestCount += 1
                    return runtimeError(
                        request,
                        .targetFrameMissing,
                        diagnostics: [
                            "scripting.executeScript target frame is missing.",
                        ]
                    )
                }
                selectedFrames = [frame]
            }
            guard selectedFrames.allSatisfy(\.controlledSyntheticExecutionAllowed)
            else {
                rejectedRequestCount += 1
                return runtimeError(
                    request,
                    .unsupportedAPI,
                    diagnostics: [
                        "scripting.executeScript frame is not eligible for controlled synthetic execution.",
                    ]
                )
            }
            let results = selectedFrames.sorted { $0.frameID < $1.frameID }
                .map {
                    ChromeMV3StorageValue.object([
                        "documentId": .string($0.documentID),
                        "frameId": .number(Double($0.frameID)),
                        "result": $0.modeledExecuteScriptResult ?? .null,
                    ])
                }
            let payload = ChromeMV3StorageValue.array(results)
            let record = tabRegistry.recordExecuteScript(
                tabID: tab.id,
                frameIDs: selectedFrames.map(\.frameID).sorted(),
                injectionKind: input.injectionKind,
                argumentCount: input.arguments.count,
                resultPayload: payload
            )
            return response(
                request: request,
                succeeded: true,
                payload: payload,
                diagnostics:
                    uniqueSortedTabsScripting(
                        record.diagnostics
                            + [
                                "scripting.executeScript returned one modeled result envelope per frame.",
                                "Function/file input was represented but not evaluated in a product tab.",
                            ]
                    )
            )
        }
    }

    private func dispatch(
        request: ChromeMV3RuntimeJSBridgeHostRequest,
        route: ChromeMV3RuntimeMessagingRoute,
        expectsResponse: Bool
    ) -> ChromeMV3RuntimeMessageDispatcherResult {
        ChromeMV3RuntimeMessageDispatcher.dispatch(
            input: ChromeMV3RuntimeMessageDispatcherInput.make(
                route: route,
                listenerRegistrySnapshot:
                    tabRegistry.listenerRegistrySnapshot(),
                permissionBrokerSnapshot: permissionBroker,
                serviceWorkerLifecycleSnapshot:
                    .blocked(
                        extensionID: configuration.extensionID,
                        profileID: configuration.profileID
                    ),
                moduleState: configuration.moduleState,
                dispatchMode: .modelOnly,
                responseMode:
                    request.invocationMode == .callback
                        ? .callback
                        : request.invocationMode == .promise
                            ? .promise
                            : .none,
                expectsResponse: expectsResponse,
                userGestureAvailable: false,
                nativeHostName: nil,
                seed: request.bridgeCallID
            )
        )
    }

    private func normalizeTabsMessageTarget(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> Result<
        ChromeMV3TabsScriptingNormalizedTabTarget,
        ChromeMV3TabsScriptingArgumentError
    > {
        guard request.arguments.count >= 2 else {
            return argumentFailure(
                "tabs.sendMessage requires tabId and message arguments."
            )
        }
        guard request.arguments.count <= 3 else {
            return argumentFailure(
                "tabs.sendMessage accepts tabId, message, and optional options."
            )
        }
        guard let tabID = request.arguments[0].intValue else {
            return argumentFailure(
                "tabs.sendMessage tabId must be an integer."
            )
        }
        let options = request.arguments.count == 3
            ? request.arguments[2].objectValue
            : [:]
        if request.arguments.count == 3, options == nil {
            return argumentFailure(
                "tabs.sendMessage options must be an object."
            )
        }
        return .success(
            ChromeMV3TabsScriptingNormalizedTabTarget(
                tabID: tabID,
                frameID: options?["frameId"]?.intValue ?? 0,
                documentID: options?["documentId"]?.stringValue
            )
        )
    }

    private func normalizeTabsConnectTarget(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> Result<
        ChromeMV3TabsScriptingNormalizedTabTarget,
        ChromeMV3TabsScriptingArgumentError
    > {
        guard request.arguments.count >= 1 else {
            return argumentFailure("tabs.connect requires a tabId argument.")
        }
        guard request.arguments.count <= 2 else {
            return argumentFailure(
                "tabs.connect accepts tabId and optional connectInfo."
            )
        }
        guard let tabID = request.arguments[0].intValue else {
            return argumentFailure("tabs.connect tabId must be an integer.")
        }
        let connectInfo = request.arguments.count == 2
            ? request.arguments[1].objectValue
            : [:]
        if request.arguments.count == 2, connectInfo == nil {
            return argumentFailure(
                "tabs.connect connectInfo must be an object."
            )
        }
        return .success(
            ChromeMV3TabsScriptingNormalizedTabTarget(
                tabID: tabID,
                frameID: connectInfo?["frameId"]?.intValue ?? 0,
                documentID: connectInfo?["documentId"]?.stringValue
            )
        )
    }

    private func normalizeExecuteScript(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> Result<
        ChromeMV3ScriptingExecuteScriptNormalizedRequest,
        ChromeMV3TabsScriptingArgumentError
    > {
        guard request.arguments.count == 1,
              let details = request.arguments[0].objectValue
        else {
            return argumentFailure(
                "scripting.executeScript requires one details object."
            )
        }
        guard let target = details["target"]?.objectValue,
              let tabID = target["tabId"]?.intValue
        else {
            return argumentFailure(
                "scripting.executeScript details.target.tabId is required."
            )
        }
        let frameIDs: [Int]?
        if let value = target["frameIds"] {
            guard case .array(let values) = value else {
                return argumentFailure(
                    "scripting.executeScript target.frameIds must be an array."
                )
            }
            frameIDs = values.compactMap(\.intValue)
            if frameIDs?.count != values.count {
                return argumentFailure(
                    "scripting.executeScript target.frameIds entries must be integers."
                )
            }
        } else {
            frameIDs = nil
        }
        let files: [String]
        if let value = details["files"] {
            guard case .array(let values) = value else {
                return argumentFailure(
                    "scripting.executeScript files must be a string array."
                )
            }
            files = values.compactMap(\.stringValue)
            if files.count != values.count {
                return argumentFailure(
                    "scripting.executeScript files entries must be strings."
                )
            }
        } else {
            files = []
        }
        let functionSource = details["functionSource"]?.stringValue
            ?? details["func"]?.stringValue
        let hasFunction = functionSource?.isEmpty == false
        let hasFiles = files.isEmpty == false
        guard hasFiles != hasFunction else {
            return argumentFailure(
                "scripting.executeScript requires exactly one of files or functionSource."
            )
        }
        let arguments: [ChromeMV3StorageValue]
        if let value = details["args"] {
            guard case .array(let values) = value else {
                return argumentFailure(
                    "scripting.executeScript args must be an array."
                )
            }
            arguments = values
        } else {
            arguments = []
        }
        return .success(
            ChromeMV3ScriptingExecuteScriptNormalizedRequest(
                target:
                    ChromeMV3TabsScriptingNormalizedTabTarget(
                        tabID: tabID,
                        frameID: target["frameId"]?.intValue ?? 0,
                        documentID: target["documentId"]?.stringValue
                    ),
                frameIDs: frameIDs,
                injectionKind: hasFunction ? "function" : "files",
                files: files,
                functionSource: functionSource,
                arguments: arguments
            )
        )
    }

    private func hostPermissionError(
        tab: ChromeMV3SyntheticTabRecord,
        requestName: String
    ) -> ChromeMV3RuntimeLastErrorCase? {
        let decision = permissionBroker.hostAccessDecision(
            url: tab.url,
            tabID: tab.id
        )
        guard decision.hasHostAccess == false else { return nil }
        if decision.missingReason == .activeTabMissing {
            return .activeTabMissing
        }
        if decision.missingReason == .permissionDenied
            || decision.missingReason == .permissionRevoked
        {
            return .permissionDenied
        }
        if permissionBroker.activeTabPermissionDeclared {
            return .activeTabMissing
        }
        _ = requestName
        return .hostPermissionMissing
    }

    private func permissionsInput(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        requiresObjectArgument: Bool
    ) -> Result<
        ChromeMV3PermissionsAPIRequestInput,
        ChromeMV3TabsScriptingArgumentError
    > {
        if requiresObjectArgument {
            guard request.arguments.count == 1 else {
                return argumentFailure(
                    "permissions.\(request.methodName) requires one permissions object."
                )
            }
        }
        let object = request.arguments.first?.objectValue
        if requiresObjectArgument, object == nil {
            return argumentFailure(
                "permissions.\(request.methodName) argument must be an object."
            )
        }
        let permissions = stringArray(
            object?["permissions"],
            fieldName: "permissions"
        )
        if let message = permissions.error {
            return argumentFailure(message)
        }
        let origins = stringArray(object?["origins"], fieldName: "origins")
        if let message = origins.error {
            return argumentFailure(message)
        }
        return .success(
            ChromeMV3PermissionsAPIRequestInput(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                sourceContext:
                    configuration.sourceContext.permissionsContext,
                userGestureModeled:
                    object?["__sumiUserGestureModeled"]?.boolValue
                    ?? (configuration.sourceContext == .actionPopup),
                extensionModuleEnabled:
                    configuration.moduleState == .enabled,
                permissions: permissions.values,
                origins: origins.values
            )
        )
    }

    private func stringArray(
        _ value: ChromeMV3StorageValue?,
        fieldName: String
    ) -> (values: [String], error: String?) {
        guard let value else { return ([], nil) }
        guard case .array(let entries) = value else {
            return ([], "\(fieldName) must be a string array.")
        }
        var values: [String] = []
        for entry in entries {
            guard let string = entry.stringValue else {
                return (
                    [],
                    "\(fieldName) entries must be strings."
                )
            }
            values.append(string)
        }
        return (Array(Set(values)).sorted(), nil)
    }

    private func modeledPromptResult(
        from value: ChromeMV3StorageValue?
    ) -> ChromeMV3ModeledPermissionPromptResult {
        guard let object = value?.objectValue,
              let result = object["__sumiModeledPromptResult"]
        else { return .notProvided }
        if let bool = result.boolValue {
            return bool ? .accepted : .denied
        }
        switch result.stringValue?.lowercased() {
        case "accept", "accepted", "grant", "granted", "allow", "allowed":
            return .accepted
        case "deny", "denied", "reject", "rejected", "block", "blocked":
            return .denied
        default:
            return .notProvided
        }
    }

    private func argumentFailure<T>(
        _ message: String
    ) -> Result<T, ChromeMV3TabsScriptingArgumentError> {
        .failure(ChromeMV3TabsScriptingArgumentError(message: message))
    }

    private func invalidArguments(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        _ message: String
    ) -> ChromeMV3TabsScriptingJSBridgeHostResponse {
        response(
            request: request,
            succeeded: false,
            lastErrorMessage: message,
            lastErrorCode: ChromeMV3JSBridgeErrorCode.invalidArguments
                .rawValue,
            diagnostics: [message]
        )
    }

    private func runtimeError(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        _ error: ChromeMV3RuntimeLastErrorCase,
        runtimeDispatcherResult:
            ChromeMV3RuntimeMessageDispatcherResult? = nil,
        serviceWorkerLifecycleWakeResult:
            ChromeMV3ServiceWorkerInternalWakeResult? = nil,
        diagnostics: [String] = []
    ) -> ChromeMV3TabsScriptingJSBridgeHostResponse {
        let contract = ChromeMV3RuntimeLastErrorContract.contract(for: error)
        return response(
            request: request,
            succeeded: false,
            lastErrorMessage: contract.futureLastErrorMessage,
            lastErrorCode: error.rawValue,
            runtimeDispatcherResult: runtimeDispatcherResult,
            serviceWorkerLifecycleWakeResult:
                serviceWorkerLifecycleWakeResult,
            diagnostics: contract.diagnostics + diagnostics
        )
    }

    private func response(
        request: ChromeMV3RuntimeJSBridgeHostRequest?,
        methodName: String? = nil,
        succeeded: Bool,
        payload: ChromeMV3StorageValue? = nil,
        lastErrorMessage: String? = nil,
        lastErrorCode: String? = nil,
        runtimeDispatcherResult:
            ChromeMV3RuntimeMessageDispatcherResult? = nil,
        permissionsContainsResult:
            ChromeMV3PermissionsAPIContainsResult? = nil,
        permissionsGetAllResult:
            ChromeMV3PermissionsAPIGetAllResult? = nil,
        permissionsRequestResult:
            ChromeMV3PermissionsAPIRequestResult? = nil,
        permissionsRemoveResult:
            ChromeMV3PermissionsAPIRemoveResult? = nil,
        serviceWorkerLifecycleWakeResult:
            ChromeMV3ServiceWorkerInternalWakeResult? = nil,
        diagnostics: [String] = []
    ) -> ChromeMV3TabsScriptingJSBridgeHostResponse {
        let invocationMode = request?.invocationMode ?? .promise
        return ChromeMV3TabsScriptingJSBridgeHostResponse(
            bridgeCallID: request?.bridgeCallID
                ?? stableIDTabsScripting(
                    prefix: "tabs-scripting-js-response",
                    parts: [methodName ?? "unknown", succeeded.description]
                ),
            namespace: request?.namespace ?? "tabs",
            methodName: request?.methodName ?? methodName ?? "unknown",
            succeeded: succeeded,
            resultPayload: payload,
            lastErrorMessage: lastErrorMessage,
            lastErrorCode: lastErrorCode,
            callbackWouldSetLastError:
                invocationMode == .callback && succeeded == false,
            promiseWouldReject:
                invocationMode == .promise && succeeded == false,
            runtimeDispatcherResult: runtimeDispatcherResult,
            permissionsContainsResult: permissionsContainsResult,
            permissionsGetAllResult: permissionsGetAllResult,
            permissionsRequestResult: permissionsRequestResult,
            permissionsRemoveResult: permissionsRemoveResult,
            tabRegistrySummary: tabRegistry.summary,
            contentScriptEndpointSummary:
                tabRegistry.contentScriptEndpointSummary,
            tabsJSBridgeAvailableInSyntheticHarness:
                configuration.tabsJSBridgeAvailableInSyntheticHarness,
            tabsJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            scriptingAvailableInProduct: false,
            serviceWorkerWakeAvailable: false,
            serviceWorkerLifecycleAvailableInInternalFixture:
                configuration
                .serviceWorkerLifecycleAvailableInInternalFixture,
            serviceWorkerWakeAvailableInProduct: false,
            serviceWorkerPermanentBackgroundAvailable: false,
            nativeMessagingAvailable: false,
            runtimeLoadable: false,
            serviceWorkerLifecycleWakeResult:
                serviceWorkerLifecycleWakeResult,
            diagnostics:
                uniqueSortedTabsScripting(
                    configuration.diagnostics
                        + diagnostics
                        + (serviceWorkerLifecycleWakeResult?.diagnostics ?? [])
                        + [
                            "tabs/scripting JS bridge handler is DEBUG/internal and synthetic-surface gated.",
                            "No product normal-tab bridge is installed.",
                            "No native messaging, service-worker wake, or product runtime exposure occurred.",
                        ]
                )
        )
    }
}

struct ChromeMV3TabsScriptingJSShimCoverage:
    Codable,
    Equatable,
    Sendable
{
    var exposedChromeNamespaces: [String]
    var runtimeMembers: [String]
    var permissionsMethods: [String]
    var permissionsEvents: [String]
    var tabsMethods: [String]
    var scriptingMethods: [String]
    var portMembers: [String]
    var callbackModeSupported: Bool
    var promiseModeSupported: Bool
    var lastErrorScopedToCallbackTurn: Bool
    var unsupportedChromeNamespaces: [String]
}

enum ChromeMV3TabsScriptingJSShimSource {
    static let bridgeMessageHandlerName = "sumiChromeMV3TabsScripting"

    static var coverage: ChromeMV3TabsScriptingJSShimCoverage {
        ChromeMV3TabsScriptingJSShimCoverage(
            exposedChromeNamespaces: [
                "permissions",
                "runtime",
                "scripting",
                "tabs",
            ],
            runtimeMembers: ["lastError"],
            permissionsMethods: ["contains", "getAll", "remove", "request"],
            permissionsEvents: ["onAdded", "onRemoved"],
            tabsMethods: ["connect", "query", "sendMessage"],
            scriptingMethods: ["executeScript"],
            portMembers: [
                "disconnect",
                "name",
                "onDisconnect",
                "onMessage",
                "postMessage",
                "sender",
            ],
            callbackModeSupported: true,
            promiseModeSupported: true,
            lastErrorScopedToCallbackTurn: true,
            unsupportedChromeNamespaces: [
                "nativeMessaging",
                "storage",
            ]
        )
    }

    static func source(
        configuration: ChromeMV3TabsScriptingJSBridgeConfiguration
    ) -> String {
        let configJSON = jsonString([
            "extensionID": configuration.extensionID,
            "profileID": configuration.profileID,
            "surfaceID": configuration.surfaceID,
            "sourceContext": configuration.sourceContext.rawValue,
            "extensionBaseURLString":
                configuration.extensionBaseURLString ?? "",
            "bridgeMessageHandlerName": bridgeMessageHandlerName,
        ])
        return """
        (() => {
          "use strict";
          const config = \(configJSON);
          const bridgeName = config.bridgeMessageHandlerName;
          const chromeObject = {};
          const runtime = {};
          const permissions = {};
          const tabs = {};
          const scripting = {};
          let lastErrorValue;
          let nextBridgeCallNumber = 0;
          let nextPortNumber = 0;
          const portState = new WeakMap();

          function bridgeUnavailableResponse(namespace, methodName) {
            return {
              bridgeCallID: "tabs-scripting-js-unavailable",
              namespace,
              methodName,
              succeeded: false,
              resultPayload: null,
              lastErrorMessage: "tabs/scripting JS bridge handler is unavailable.",
              lastErrorCode: "jsBridgeUnavailable",
              callbackWouldSetLastError: false,
              promiseWouldReject: false,
              diagnostics: ["tabs/scripting JS bridge handler is unavailable."]
            };
          }

          function bridgePost(namespace, methodName, invocationMode, args, extra) {
            const handler = globalThis.webkit
              && globalThis.webkit.messageHandlers
              && globalThis.webkit.messageHandlers[bridgeName];
            if (!handler || typeof handler.postMessage !== "function") {
              return Promise.resolve(bridgeUnavailableResponse(namespace, methodName));
            }
            nextBridgeCallNumber += 1;
            const body = Object.assign({
              namespace,
              methodName,
              invocationMode,
              extensionID: config.extensionID,
              profileID: config.profileID,
              sourceContext: config.sourceContext,
              surfaceID: config.surfaceID,
              bridgeCallID: [
                "tabs-scripting-js",
                config.surfaceID,
                namespace,
                methodName,
                String(nextBridgeCallNumber)
              ].join("-"),
              arguments: args || []
            }, extra || {});
            return handler.postMessage(body);
          }

          function toJSONCompatible(value) {
            if (value === undefined) {
              return null;
            }
            return JSON.parse(JSON.stringify(value));
          }

          function invokeCallback(callback, message, args) {
            lastErrorValue = message ? { message } : undefined;
            try {
              callback.apply(undefined, args || []);
            } finally {
              lastErrorValue = undefined;
            }
          }

          function rejectFromResponse(response) {
            return Promise.reject(
              new Error(response.lastErrorMessage || "tabs/scripting JS bridge call failed.")
            );
          }

          function callbackOrPromise(namespace, methodName, args, callback) {
            const mode = callback ? "callback" : "promise";
            let bridgeArgs;
            try {
              bridgeArgs = args.map(toJSONCompatible);
            } catch (error) {
              const message = "Invalid Chrome MV3 JavaScript bridge arguments.";
              if (callback) {
                invokeCallback(callback, message, []);
                return undefined;
              }
              return Promise.reject(new Error(message));
            }
            const promise = bridgePost(namespace, methodName, mode, bridgeArgs);
            if (callback) {
              promise.then((response) => {
                if (response.succeeded) {
                  invokeCallback(callback, null, [response.resultPayload]);
                } else {
                  invokeCallback(callback, response.lastErrorMessage, []);
                }
              });
              return undefined;
            }
            return promise.then((response) => {
              if (response.succeeded) {
                return response.resultPayload;
              }
              return rejectFromResponse(response);
            });
          }

          function makePortEvent() {
            const listeners = [];
            return Object.freeze({
              addListener(listener) {
                if (typeof listener === "function" && !listeners.includes(listener)) {
                  listeners.push(listener);
                }
              },
              removeListener(listener) {
                const index = listeners.indexOf(listener);
                if (index >= 0) {
                  listeners.splice(index, 1);
                }
              },
              hasListener(listener) {
                return listeners.includes(listener);
              },
              dispatch() {
                const args = Array.prototype.slice.call(arguments);
                listeners.slice().forEach((listener) => listener.apply(undefined, args));
              }
            });
          }

          function makePermissionEvent() {
            const listeners = [];
            return Object.freeze({
              addListener(listener) {
                if (typeof listener === "function" && !listeners.includes(listener)) {
                  listeners.push(listener);
                }
              },
              removeListener(listener) {
                const index = listeners.indexOf(listener);
                if (index >= 0) {
                  listeners.splice(index, 1);
                }
              },
              hasListener(listener) {
                return listeners.includes(listener);
              },
              hasListeners() {
                return listeners.length > 0;
              }
            });
          }

          function createPort(name, sender) {
            const port = {};
            const state = {
              id: null,
              disconnected: false,
              onMessage: makePortEvent(),
              onDisconnect: makePortEvent()
            };
            Object.defineProperty(port, "name", {
              value: name || "",
              enumerable: true
            });
            if (sender) {
              Object.defineProperty(port, "sender", {
                value: sender,
                enumerable: true
              });
            }
            Object.defineProperty(port, "onMessage", {
              value: state.onMessage,
              enumerable: true
            });
            Object.defineProperty(port, "onDisconnect", {
              value: state.onDisconnect,
              enumerable: true
            });
            Object.defineProperty(port, "postMessage", {
              value(message) {
                if (state.disconnected) {
                  throw new Error("Attempting to use a disconnected port object");
                }
                bridgePost("tabs", "Port.postMessage", "fireAndForget", [toJSONCompatible(message)], {
                  portID: state.id
                }).catch(() => undefined);
              },
              enumerable: true
            });
            Object.defineProperty(port, "disconnect", {
              value() {
                if (state.disconnected) {
                  return;
                }
                state.disconnected = true;
                bridgePost("tabs", "Port.disconnect", "fireAndForget", [], {
                  portID: state.id
                }).catch(() => undefined);
                state.onDisconnect.dispatch(port);
              },
              enumerable: true
            });
            portState.set(port, state);
            return port;
          }

          Object.defineProperty(runtime, "lastError", {
            get() {
              return lastErrorValue;
            },
            enumerable: true
          });

          Object.defineProperty(permissions, "contains", {
            value(permissionsObject, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("permissions", "contains", [permissionsObject || {}], cb);
            },
            enumerable: true
          });

          Object.defineProperty(permissions, "getAll", {
            value(callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("permissions", "getAll", [], cb);
            },
            enumerable: true
          });

          Object.defineProperty(permissions, "request", {
            value(permissionsObject, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("permissions", "request", [permissionsObject || {}], cb);
            },
            enumerable: true
          });

          Object.defineProperty(permissions, "remove", {
            value(permissionsObject, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("permissions", "remove", [permissionsObject || {}], cb);
            },
            enumerable: true
          });

          Object.defineProperty(permissions, "onAdded", {
            value: makePermissionEvent(),
            enumerable: true
          });

          Object.defineProperty(permissions, "onRemoved", {
            value: makePermissionEvent(),
            enumerable: true
          });

          Object.defineProperty(tabs, "query", {
            value(queryInfo, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("tabs", "query", [queryInfo || {}], cb);
            },
            enumerable: true
          });

          Object.defineProperty(tabs, "sendMessage", {
            value(tabId, message, options, callback) {
              let cb = null;
              let opts = options;
              if (typeof opts === "function") {
                cb = opts;
                opts = undefined;
              } else if (typeof callback === "function") {
                cb = callback;
              }
              const args = opts === undefined ? [tabId, message] : [tabId, message, opts];
              return callbackOrPromise("tabs", "sendMessage", args, cb);
            },
            enumerable: true
          });

          Object.defineProperty(tabs, "connect", {
            value(tabId, connectInfo) {
              const info = connectInfo && typeof connectInfo === "object" ? connectInfo : {};
              const name = typeof info.name === "string" ? info.name : "";
              const port = createPort(name, {
                id: config.extensionID,
                url: config.extensionBaseURLString || undefined
              });
              const state = portState.get(port);
              nextPortNumber += 1;
              state.id = [config.surfaceID, "tabs-pending-port", String(nextPortNumber)].join(":");
              bridgePost("tabs", "connect", "fireAndForget", [tabId, info])
                .then((response) => {
                  if (!response.succeeded) {
                    state.disconnected = true;
                    state.onDisconnect.dispatch(port);
                    return;
                  }
                  const payload = response.resultPayload || {};
                  state.id = payload.portID || state.id;
                })
                .catch(() => {
                  state.disconnected = true;
                  state.onDisconnect.dispatch(port);
                });
              return port;
            },
            enumerable: true
          });

          function normalizeExecuteScriptDetails(details) {
            const source = Object.assign({}, details || {});
            if (typeof source.func === "function") {
              source.functionSource = Function.prototype.toString.call(source.func);
              delete source.func;
            }
            return source;
          }

          Object.defineProperty(scripting, "executeScript", {
            value(details, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise(
                "scripting",
                "executeScript",
                [normalizeExecuteScriptDetails(details)],
                cb
              );
            },
            enumerable: true
          });

          Object.defineProperty(chromeObject, "runtime", {
            value: Object.freeze(runtime),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "permissions", {
            value: Object.freeze(permissions),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "tabs", {
            value: Object.freeze(tabs),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "scripting", {
            value: Object.freeze(scripting),
            enumerable: true
          });
          Object.defineProperty(globalThis, "chrome", {
            value: Object.freeze(chromeObject),
            configurable: true
          });
        })();
        """
    }

    private static func jsonString(_ object: [String: String]) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

struct ChromeMV3TabsScriptingMVPBehaviorSummary:
    Codable,
    Equatable,
    Sendable
{
    var tabsScriptingModelHandlersAvailable: Bool
    var tabsQueryCallbackModeCovered: Bool
    var tabsQueryPromiseModeCovered: Bool
    var tabsQueryRedactionCovered: Bool
    var tabsSendMessageRoutesToDispatcher: Bool
    var tabsSendMessageNoReceivingEndMapped: Bool
    var tabsConnectCreatesModelPort: Bool
    var scriptingExecuteScriptModeled: Bool
    var scriptingProductTargetBlocked: Bool
    var callbackLastErrorScoped: Bool
    var promiseRejectsOnError: Bool
    var noNativeMessagingOpened: Bool
    var noServiceWorkerWake: Bool
}

struct ChromeMV3TabsScriptingWebKitExecutionSummary:
    Codable,
    Equatable,
    Sendable
{
    var status: String
    var tabsScriptingModelHandlersAvailable: Bool
    var tabsScriptingJSBridgeAvailableInSyntheticHarness: Bool
    var tabsScriptingJSExecutedInWebKitSyntheticHarness: Bool
    var tabsQueryCallbackExecuted: Bool
    var tabsQueryPromiseExecuted: Bool
    var tabsQueryRedactionExecuted: Bool
    var tabsSendMessageCallbackExecuted: Bool
    var tabsSendMessagePromiseExecuted: Bool
    var tabsSendMessageNoReceiverLastErrorExecuted: Bool
    var tabsConnectExecuted: Bool
    var tabsConnectDisconnectExecuted: Bool
    var scriptingExecuteScriptExecuted: Bool
    var scriptingProductTargetBlocked: Bool
    var callbackLastErrorScoped: Bool
    var promiseRejectsOnError: Bool
    var tabsJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var scriptingAvailableInProduct: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    static func notAttempted(
        tabsScriptingModelHandlersAvailable: Bool,
        tabsScriptingJSBridgeAvailableInSyntheticHarness: Bool
    ) -> ChromeMV3TabsScriptingWebKitExecutionSummary {
        ChromeMV3TabsScriptingWebKitExecutionSummary(
            status: "notAttemptedByModelReportGenerator",
            tabsScriptingModelHandlersAvailable:
                tabsScriptingModelHandlersAvailable,
            tabsScriptingJSBridgeAvailableInSyntheticHarness:
                tabsScriptingJSBridgeAvailableInSyntheticHarness,
            tabsScriptingJSExecutedInWebKitSyntheticHarness: false,
            tabsQueryCallbackExecuted: false,
            tabsQueryPromiseExecuted: false,
            tabsQueryRedactionExecuted: false,
            tabsSendMessageCallbackExecuted: false,
            tabsSendMessagePromiseExecuted: false,
            tabsSendMessageNoReceiverLastErrorExecuted: false,
            tabsConnectExecuted: false,
            tabsConnectDisconnectExecuted: false,
            scriptingExecuteScriptExecuted: false,
            scriptingProductTargetBlocked: false,
            callbackLastErrorScoped: false,
            promiseRejectsOnError: false,
            tabsJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            scriptingAvailableInProduct: false,
            runtimeLoadable: false,
            diagnostics: [
                "WebKit-executed tabs/scripting synthetic harness was not run by this model-only report generator.",
                "Model handler availability is reported separately from WebKit JS execution.",
            ]
        )
    }

    static func fromWebKitScriptResult(
        json: String?,
        scriptEvaluationSucceeded: Bool,
        tabsScriptingModelHandlersAvailable: Bool,
        tabsScriptingJSBridgeAvailableInSyntheticHarness: Bool,
        diagnostics: [String]
    ) -> ChromeMV3TabsScriptingWebKitExecutionSummary {
        let object = decodedObject(json)
        func bool(_ key: String) -> Bool {
            object?[key] as? Bool ?? false
        }
        return ChromeMV3TabsScriptingWebKitExecutionSummary(
            status:
                scriptEvaluationSucceeded
                    ? "executedInWebKitSyntheticHarness"
                    : "blockedOrFailedInWebKitSyntheticHarness",
            tabsScriptingModelHandlersAvailable:
                tabsScriptingModelHandlersAvailable,
            tabsScriptingJSBridgeAvailableInSyntheticHarness:
                tabsScriptingJSBridgeAvailableInSyntheticHarness,
            tabsScriptingJSExecutedInWebKitSyntheticHarness:
                scriptEvaluationSucceeded,
            tabsQueryCallbackExecuted: bool("tabsQueryCallbackOK"),
            tabsQueryPromiseExecuted: bool("tabsQueryPromiseOK"),
            tabsQueryRedactionExecuted: bool("tabsQueryRedactionOK"),
            tabsSendMessageCallbackExecuted:
                bool("tabsSendMessageCallbackOK"),
            tabsSendMessagePromiseExecuted:
                bool("tabsSendMessagePromiseOK"),
            tabsSendMessageNoReceiverLastErrorExecuted:
                bool("tabsSendMessageNoReceiverLastErrorOK"),
            tabsConnectExecuted: bool("tabsConnectOK"),
            tabsConnectDisconnectExecuted: bool("tabsConnectDisconnectOK"),
            scriptingExecuteScriptExecuted:
                bool("scriptingExecuteScriptOK"),
            scriptingProductTargetBlocked:
                bool("scriptingProductTargetBlockedOK"),
            callbackLastErrorScoped: bool("callbackLastErrorScopedOK"),
            promiseRejectsOnError: bool("promiseRejectsOnErrorOK"),
            tabsJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            scriptingAvailableInProduct: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedTabsScripting(
                    diagnostics
                        + [
                            scriptEvaluationSucceeded
                                ? "tabs/scripting JS calls were executed by WebKit in the controlled synthetic harness."
                                : "tabs/scripting WebKit synthetic harness produced a deterministic blocked/failed diagnostic.",
                            "WebKit JS execution status is not inferred from model handler success.",
                        ]
                )
        )
    }

    private static func decodedObject(_ json: String?) -> [String: Any]? {
        guard let json,
              let data = json.data(using: .utf8)
        else { return nil }
        guard let value = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return value as? [String: Any]
    }
}

struct ChromeMV3TabsScriptingMVPReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var tabsScriptingModelHandlersAvailable: Bool
    var tabsScriptingJSBridgeAvailableInSyntheticHarness: Bool
    var tabsScriptingJSExecutedInWebKitSyntheticHarness: Bool
    var tabsJSBridgeAvailableInSyntheticHarness: Bool
    var tabsJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var scriptingAvailableInProduct: Bool
    var serviceWorkerWakeAvailable: Bool
    var nativeMessagingAvailable: Bool
    var runtimeLoadable: Bool
    var tabsQueryMVPAvailable: Bool
    var tabsSendMessageMVPAvailable: Bool
    var tabsConnectMVPAvailable: Bool
    var scriptingExecuteScriptMVPAvailable: Bool
}

struct ChromeMV3TabsScriptingMVPReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var extensionID: String
    var profileID: String
    var shimCoverage: ChromeMV3TabsScriptingJSShimCoverage
    var bridgeHandlerCoveredMethods: [String]
    var syntheticTabRegistrySummary:
        ChromeMV3SyntheticTabRegistrySummary
    var contentScriptEndpointSummary:
        ChromeMV3SyntheticContentScriptEndpointSummary
    var behaviorSummary: ChromeMV3TabsScriptingMVPBehaviorSummary
    var webKitExecutionSummary:
        ChromeMV3TabsScriptingWebKitExecutionSummary
    var tabsQueryCases:
        [ChromeMV3TabsScriptingJSBridgeHostResponse]
    var tabsSendMessageCases:
        [ChromeMV3TabsScriptingJSBridgeHostResponse]
    var tabsConnectCases:
        [ChromeMV3TabsScriptingJSBridgeHostResponse]
    var scriptingExecuteScriptCases:
        [ChromeMV3TabsScriptingJSBridgeHostResponse]
    var permissionRedactionDecisions:
        [ChromeMV3SyntheticTabRedactionDecision]
    var controlledSurfaceTestStatus: String
    var tabsJSBridgeAvailableInSyntheticHarness: Bool
    var tabsJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var scriptingAvailableInProduct: Bool
    var nativeMessagingAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var runtimeLoadable: Bool
    var productRuntimeExposed: Bool
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    var diagnostics: [String]

    var summary: ChromeMV3TabsScriptingMVPReportSummary {
        ChromeMV3TabsScriptingMVPReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            tabsScriptingModelHandlersAvailable:
                behaviorSummary.tabsScriptingModelHandlersAvailable,
            tabsScriptingJSBridgeAvailableInSyntheticHarness:
                webKitExecutionSummary
                .tabsScriptingJSBridgeAvailableInSyntheticHarness,
            tabsScriptingJSExecutedInWebKitSyntheticHarness:
                webKitExecutionSummary
                .tabsScriptingJSExecutedInWebKitSyntheticHarness,
            tabsJSBridgeAvailableInSyntheticHarness:
                tabsJSBridgeAvailableInSyntheticHarness,
            tabsJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            scriptingAvailableInProduct: false,
            serviceWorkerWakeAvailable: false,
            nativeMessagingAvailable: false,
            runtimeLoadable: false,
            tabsQueryMVPAvailable:
                behaviorSummary.tabsQueryCallbackModeCovered
                    || behaviorSummary.tabsQueryPromiseModeCovered,
            tabsSendMessageMVPAvailable:
                behaviorSummary.tabsSendMessageRoutesToDispatcher,
            tabsConnectMVPAvailable:
                behaviorSummary.tabsConnectCreatesModelPort,
            scriptingExecuteScriptMVPAvailable:
                behaviorSummary.scriptingExecuteScriptModeled
        )
    }
}

enum ChromeMV3TabsScriptingMVPReportWriter {
    static let reportFileName =
        "runtime-tabs-scripting-mvp-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3TabsScriptingMVPReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3TabsScriptingMVPReport {
        guard directoryExists(rootURL.standardizedFileURL) else {
            return report
        }
        try ChromeMV3DeterministicJSON.write(
            report,
            to: rootURL.standardizedFileURL
                .appendingPathComponent(Self.reportFileName)
        )
        return report
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}

enum ChromeMV3TabsScriptingMVPReportGenerator {
    static func makeReport(
        extensionID: String = "tabs-scripting-js-mvp-extension",
        profileID: String = "tabs-scripting-js-mvp-profile",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        webKitExecutionSummary:
            ChromeMV3TabsScriptingWebKitExecutionSummary? = nil
    ) -> ChromeMV3TabsScriptingMVPReport {
        let configuration = ChromeMV3TabsScriptingJSBridgeConfiguration
            .syntheticHarness(
                extensionID: extensionID,
                profileID: profileID,
                moduleState: moduleState
            )
        let registry =
            ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                includeProductNormalTab: true
            )
        let noPermissionHandler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            tabRegistry:
                ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID,
                    includeProductNormalTab: false
                ),
            permissionBroker:
                ChromeMV3TabsScriptingPermissionFixtures.noHostAccess(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID
                )
        )
        let handler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            tabRegistry: registry,
            permissionBroker:
                ChromeMV3TabsScriptingPermissionFixtures
                .hostAndScripting(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID
                )
        )
        let queryRedacted = noPermissionHandler.handle(
            request(
                namespace: "tabs",
                methodName: "query",
                invocationMode: .promise,
                arguments: [.object(["active": .bool(true)])]
            )
        )
        let queryPromise = handler.handle(
            request(
                namespace: "tabs",
                methodName: "query",
                invocationMode: .promise,
                arguments: [.object(["active": .bool(true)])]
            )
        )
        let queryCallback = handler.handle(
            request(
                namespace: "tabs",
                methodName: "query",
                invocationMode: .callback,
                arguments: [.object(["currentWindow": .bool(true)])]
            )
        )
        let sendMessage = handler.handle(
            request(
                namespace: "tabs",
                methodName: "sendMessage",
                invocationMode: .promise,
                arguments: [
                    .number(1),
                    .object(["type": .string("fill-login")]),
                    .object(["frameId": .number(0)]),
                ]
            )
        )
        let missingEndpointRegistry =
            ChromeMV3SyntheticTabRegistry(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                tabs: [
                    ChromeMV3SyntheticTabRecord(
                        id: 7,
                        profileID: configuration.profileID,
                        url: "https://example.com/no-listener",
                        title: "No Listener",
                        active: true,
                        frames: [
                            ChromeMV3SyntheticTabFrameRecord(
                                frameID: 0,
                                documentID: "document-no-listener",
                                url: "https://example.com/no-listener",
                                staticContentScriptEndpointRegistered: false,
                                connectEndpointRegistered: false
                            ),
                        ]
                    ),
                ]
            )
        let missingEndpointHandler =
            ChromeMV3TabsScriptingJSBridgeHandler(
                configuration: configuration,
                tabRegistry: missingEndpointRegistry,
                permissionBroker:
                    ChromeMV3TabsScriptingPermissionFixtures
                    .hostAndScripting(
                        extensionID: configuration.extensionID,
                        profileID: configuration.profileID
                    )
            )
        let noReceiver = missingEndpointHandler.handle(
            request(
                namespace: "tabs",
                methodName: "sendMessage",
                invocationMode: .callback,
                arguments: [
                    .number(7),
                    .object(["type": .string("ping")]),
                    .object(["frameId": .number(0)]),
                ]
            )
        )
        let missingTab = handler.handle(
            request(
                namespace: "tabs",
                methodName: "sendMessage",
                invocationMode: .promise,
                arguments: [
                    .number(404),
                    .object(["type": .string("ping")]),
                ]
            )
        )
        let connect = handler.handle(
            request(
                namespace: "tabs",
                methodName: "connect",
                invocationMode: .fireAndForget,
                arguments: [
                    .number(1),
                    .object([
                        "name": .string("content"),
                        "frameId": .number(0),
                    ]),
                ]
            )
        )
        let disconnect = handler.handle(
            portRequest("Port.disconnect", portID: "tabs-port-1")
        )
        let postMessage = handler.handle(
            portRequest(
                "Port.postMessage",
                portID: "tabs-port-1",
                arguments: [.object(["kind": .string("port")])]
            )
        )
        let execute = handler.handle(
            request(
                namespace: "scripting",
                methodName: "executeScript",
                invocationMode: .promise,
                arguments: [
                    .object([
                        "target": .object([
                            "tabId": .number(1),
                            "frameIds": .array([.number(0)]),
                        ]),
                        "functionSource": .string("function getTitle() { return document.title; }"),
                        "args": .array([]),
                    ]),
                ]
            )
        )
        let productBlocked = handler.handle(
            request(
                namespace: "scripting",
                methodName: "executeScript",
                invocationMode: .promise,
                arguments: [
                    .object([
                        "target": .object(["tabId": .number(99)]),
                        "functionSource": .string("function unsafe() { return location.href; }"),
                    ]),
                ]
            )
        )
        let missingScriptingHandler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            tabRegistry:
                ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID
                ),
            permissionBroker:
                ChromeMV3TabsScriptingPermissionFixtures.hostOnly(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID
                )
        )
        let missingScriptingPermission = missingScriptingHandler.handle(
            request(
                namespace: "scripting",
                methodName: "executeScript",
                invocationMode: .callback,
                arguments: [
                    .object([
                        "target": .object(["tabId": .number(1)]),
                        "functionSource": .string("function read() { return true; }"),
                    ]),
                ]
            )
        )
        let queryCases = [queryRedacted, queryPromise, queryCallback]
        let sendCases = [sendMessage, noReceiver, missingTab]
        let connectCases = [connect, disconnect, postMessage]
        let executeCases = [
            execute,
            productBlocked,
            missingScriptingPermission,
        ]
        let allResponses = queryCases + sendCases + connectCases
            + executeCases
        let redaction = registry.query(
            ["active": .bool(true)],
            permissionBroker:
                ChromeMV3TabsScriptingPermissionFixtures.hostAndScripting(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID
                )
        ).redactionDecisions
            + noPermissionHandler.tabRegistry.query(
                ["active": .bool(true)],
                permissionBroker:
                    ChromeMV3TabsScriptingPermissionFixtures.noHostAccess(
                        extensionID: configuration.extensionID,
                        profileID: configuration.profileID
                    )
            ).redactionDecisions
        let modelHandlersAvailable =
            queryCallback.succeeded
                && queryPromise.succeeded
                && sendMessage.runtimeDispatcherResult?.modelHandlerInvoked
                    == true
                && connect.succeeded
                && execute.succeeded
        let behavior = ChromeMV3TabsScriptingMVPBehaviorSummary(
            tabsScriptingModelHandlersAvailable:
                modelHandlersAvailable,
            tabsQueryCallbackModeCovered: queryCallback.succeeded,
            tabsQueryPromiseModeCovered: queryPromise.succeeded,
            tabsQueryRedactionCovered:
                redaction.contains { $0.status == .redactedNoPermission },
            tabsSendMessageRoutesToDispatcher:
                sendMessage.runtimeDispatcherResult?.modelHandlerInvoked
                    == true,
            tabsSendMessageNoReceivingEndMapped:
                noReceiver.lastErrorCode
                    == ChromeMV3RuntimeLastErrorCase.noReceivingEnd.rawValue,
            tabsConnectCreatesModelPort: connect.succeeded,
            scriptingExecuteScriptModeled: execute.succeeded,
            scriptingProductTargetBlocked:
                productBlocked.lastErrorCode
                    == ChromeMV3RuntimeLastErrorCase.unsupportedAPI.rawValue,
            callbackLastErrorScoped:
                noReceiver.callbackWouldSetLastError
                    && missingScriptingPermission.callbackWouldSetLastError,
            promiseRejectsOnError:
                missingTab.promiseWouldReject
                    && productBlocked.promiseWouldReject,
            noNativeMessagingOpened:
                allResponses.allSatisfy {
                    $0.nativeMessagingAvailable == false
                },
            noServiceWorkerWake:
                allResponses.allSatisfy {
                    $0.serviceWorkerWakeAvailable == false
                }
        )
        let resolvedWebKitExecutionSummary =
            webKitExecutionSummary
            ?? ChromeMV3TabsScriptingWebKitExecutionSummary.notAttempted(
                tabsScriptingModelHandlersAvailable:
                    modelHandlersAvailable,
                tabsScriptingJSBridgeAvailableInSyntheticHarness:
                    configuration.tabsJSBridgeAvailableInSyntheticHarness
            )
        let reportID = stableIDTabsScripting(
            prefix: "runtime-tabs-scripting-mvp",
            parts: [
                configuration.extensionID,
                configuration.profileID,
                allResponses.map(\.bridgeCallID).joined(separator: "|"),
                resolvedWebKitExecutionSummary.status,
            ]
        )
        return ChromeMV3TabsScriptingMVPReport(
            schemaVersion: 1,
            id: reportID,
            reportFileName:
                ChromeMV3TabsScriptingMVPReportWriter.reportFileName,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            shimCoverage: ChromeMV3TabsScriptingJSShimSource.coverage,
            bridgeHandlerCoveredMethods: [
                "Port.disconnect",
                "Port.postMessage",
                "scripting.executeScript",
                "tabs.connect",
                "tabs.query",
                "tabs.sendMessage",
            ],
            syntheticTabRegistrySummary: registry.summary,
            contentScriptEndpointSummary:
                registry.contentScriptEndpointSummary,
            behaviorSummary: behavior,
            webKitExecutionSummary: resolvedWebKitExecutionSummary,
            tabsQueryCases: queryCases,
            tabsSendMessageCases: sendCases,
            tabsConnectCases: connectCases,
            scriptingExecuteScriptCases: executeCases,
            permissionRedactionDecisions: redaction.sorted {
                if $0.tabID != $1.tabID {
                    return $0.tabID < $1.tabID
                }
                return $0.status < $1.status
            },
            controlledSurfaceTestStatus:
                "tabs/scripting MVP is modeled for controlled synthetic tabs only; product normal-tab runtime remains unavailable.",
            tabsJSBridgeAvailableInSyntheticHarness:
                configuration.tabsJSBridgeAvailableInSyntheticHarness,
            tabsJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            scriptingAvailableInProduct: false,
            nativeMessagingAvailable: false,
            serviceWorkerWakeAvailable: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            documentationSources: documentationSources(),
            diagnostics:
                uniqueSortedTabsScripting(
                    allResponses.flatMap(\.diagnostics)
                        + resolvedWebKitExecutionSummary.diagnostics
                        + registry.summary.diagnostics
                        + [
                            "tabs/scripting MVP report is deterministic.",
                            "tabsScriptingModelHandlersAvailable is separate from tabsScriptingJSExecutedInWebKitSyntheticHarness.",
                            "No normal-tab bridge is installed.",
                            "No service-worker wake, native messaging, product UI, or broad scripting support is added.",
                        ]
                )
        )
    }

    private static func request(
        namespace: String,
        methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID:
                stableIDTabsScripting(
                    prefix: "tabs-scripting-report-call",
                    parts: [
                        namespace,
                        methodName,
                        invocationMode.rawValue,
                        arguments.map {
                            (try? $0.canonicalJSONString()) ?? "argument"
                        }.joined(separator: "|"),
                    ]
                ),
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

    private static func portRequest(
        _ methodName: String,
        portID: String,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID:
                stableIDTabsScripting(
                    prefix: "tabs-scripting-port-call",
                    parts: [methodName, portID]
                ),
            namespace: "tabs",
            methodName: methodName,
            invocationMode: .fireAndForget,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: portID,
            diagnostics: []
        )
    }

    private static func documentationSources()
        -> [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    {
        [
            source(
                kind: "chromeDocumentation",
                title: "Chrome tabs API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/tabs",
                note: "Defines tabs.query, tabs.sendMessage, tabs.connect, Tab fields, and permission-dependent sensitive field exposure."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome scripting API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/scripting",
                note: "Defines scripting.executeScript target and per-frame result semantics."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome activeTab permission",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/activeTab",
                note: "Defines temporary host access and scripting relationship for activeTab."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome message passing",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/messaging",
                note: "Defines tabs.sendMessage, one-time message responses, long-lived connections, and content-script trust boundaries."
            ),
            source(
                kind: "localAppleSDKHeaders",
                title: "MacOSX WebKit headers",
                url: nil,
                note: "Local headers document WKContentWorld, WKUserScript, WKScriptMessageHandlerWithReply, and evaluateJavaScript/callAsyncJavaScript scoping used only by the existing synthetic harness boundary."
            ),
            source(
                kind: "currentSumiCode",
                title: "Sumi Chrome MV3 runtime models",
                url: nil,
                note: "The MVP routes tab-targeted messaging through existing permission broker and runtime dispatcher contracts while keeping product runtime unavailable."
            ),
        ]
    }

    private static func source(
        kind: String,
        title: String,
        url: String?,
        note: String
    ) -> ChromeMV3WebKitObjectAcceptanceDocumentationSource {
        ChromeMV3WebKitObjectAcceptanceDocumentationSource(
            kind: kind,
            title: title,
            url: url,
            note: note
        )
    }
}

#if DEBUG
import WebKit

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3TabsScriptingJSScriptMessageHandler:
    NSObject,
    WKScriptMessageHandlerWithReply
{
    let handler: ChromeMV3TabsScriptingJSBridgeHandler

    init(handler: ChromeMV3TabsScriptingJSBridgeHandler) {
        self.handler = handler
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        _ = userContentController
        let response = handler.handle(message.body)
        return (response.foundationObject, nil)
    }
}

struct ChromeMV3TabsScriptingJSSyntheticHarnessResult:
    Codable,
    Equatable,
    Sendable
{
    var scriptEvaluationSucceeded: Bool
    var scriptResultJSON: String?
    var report: ChromeMV3TabsScriptingMVPReport
    var webKitExecutionSummary:
        ChromeMV3TabsScriptingWebKitExecutionSummary
    var tabRegistrySummary:
        ChromeMV3SyntheticTabRegistrySummary
    var contentScriptEndpointSummary:
        ChromeMV3SyntheticContentScriptEndpointSummary
    var tabRegistrySummaryAfterTeardown:
        ChromeMV3SyntheticTabRegistrySummary
    var contentScriptEndpointSummaryAfterTeardown:
        ChromeMV3SyntheticContentScriptEndpointSummary
    var handledRequestCount: Int
    var queryRequestCount: Int
    var sendMessageDispatchCount: Int
    var modelPortCreateCount: Int
    var modelPortDisconnectCount: Int
    var executeScriptRequestCount: Int
    var userScriptCount: Int
    var scriptMessageHandlerCount: Int
    var syntheticWebViewCreated: Bool
    var tabsScriptingJSBridgeAvailableInSyntheticHarness: Bool
    var tabsJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var scriptingAvailableInProduct: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3TabsScriptingJSSyntheticNavigationObserver:
    NSObject,
    WKNavigationDelegate
{
    private var continuation:
        CheckedContinuation<Result<Void, Error>, Never>?

    func wait() async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        _ = webView
        _ = navigation
        finish(.success(()))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = webView
        _ = navigation
        finish(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = webView
        _ = navigation
        finish(.failure(error))
    }

    private func finish(_ result: Result<Void, Error>) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@available(macOS 15.5, *)
enum ChromeMV3TabsScriptingJSSyntheticHarness {
    static let reportVerificationScriptBody = """
    const exposedNamespaces = Object.keys(chrome).sort();
    const permissionsKeys = Object.keys(chrome.permissions).sort();
    const tabsKeys = Object.keys(chrome.tabs).sort();
    const scriptingKeys = Object.keys(chrome.scripting).sort();
    const permissionsGetAll = await chrome.permissions.getAll();
    const permissionsContainsTabs =
      await chrome.permissions.contains({permissions: ["tabs"]});
    let queryCallbackTabs = null;
    let queryCallbackLastErrorInside = "unset";
    await new Promise((resolve) => {
      chrome.tabs.query({active: true}, function(tabs) {
        queryCallbackTabs = tabs;
        queryCallbackLastErrorInside = chrome.runtime.lastError || null;
        resolve();
      });
    });
    const queryCallbackLastErrorOutside = chrome.runtime.lastError || null;
    const queryPromiseTabs = await chrome.tabs.query({active: true});
    const sendPromiseResponse = await chrome.tabs.sendMessage(
      1,
      {type: "promise"},
      {frameId: 0}
    );
    let sendCallbackResponse = null;
    let sendCallbackLastErrorInside = "unset";
    await new Promise((resolve) => {
      chrome.tabs.sendMessage(1, {type: "callback"}, {frameId: 0}, function(response) {
        sendCallbackResponse = response;
        sendCallbackLastErrorInside = chrome.runtime.lastError || null;
        resolve();
      });
    });
    let noReceiverInside = null;
    let noReceiverArgCount = -1;
    await new Promise((resolve) => {
      chrome.tabs.sendMessage(7, {type: "missing"}, {frameId: 0}, function() {
        noReceiverArgCount = arguments.length;
        noReceiverInside = chrome.runtime.lastError && chrome.runtime.lastError.message;
        resolve();
      });
    });
    const noReceiverOutside = chrome.runtime.lastError || null;
    const port = chrome.tabs.connect(1, {name: "content", frameId: 0});
    let disconnectSeen = false;
    port.onDisconnect.addListener(() => {
      disconnectSeen = true;
    });
    await chrome.tabs.sendMessage(1, {type: "after-connect"}, {frameId: 0});
    port.disconnect();
    const executeResult = await chrome.scripting.executeScript({
      target: {tabId: 1, frameIds: [0]},
      func: () => document.title,
      args: []
    });
    let productBlockedMessage = null;
    try {
      await chrome.scripting.executeScript({
        target: {tabId: 99},
        func: () => location.href
      });
    } catch (error) {
      productBlockedMessage = error && error.message;
    }
    return {
      exposedNamespaces,
      permissionsKeys,
      tabsKeys,
      scriptingKeys,
      storageMissing: chrome.storage === undefined,
      permissionsMissing: chrome.permissions === undefined,
      nativeMessagingMissing: chrome.nativeMessaging === undefined,
      permissionsGetAll,
      permissionsContainsTabs,
      queryCallbackTabs,
      queryPromiseTabs,
      sendPromiseResponse,
      sendCallbackResponse,
      noReceiverInside,
      noReceiverOutside,
      productBlockedMessage,
      executeResult,
      tabsQueryCallbackOK:
        Array.isArray(queryCallbackTabs)
        && queryCallbackTabs.length === 1
        && queryCallbackTabs[0].id === 1
        && queryCallbackLastErrorInside === null
        && queryCallbackLastErrorOutside === null,
      tabsQueryPromiseOK:
        Array.isArray(queryPromiseTabs)
        && queryPromiseTabs.length === 1
        && queryPromiseTabs[0].id === 1,
      permissionsGetAllOK:
        permissionsGetAll
        && Array.isArray(permissionsGetAll.permissions)
        && permissionsGetAll.permissions.includes("tabs"),
      permissionsContainsOK: permissionsContainsTabs === true,
      tabsQueryRedactionOK: false,
      tabsSendMessagePromiseOK:
        sendPromiseResponse
        && sendPromiseResponse.target === "syntheticContentScriptModel"
        && sendPromiseResponse.tabId === 1,
      tabsSendMessageCallbackOK:
        sendCallbackResponse
        && sendCallbackResponse.target === "syntheticContentScriptModel"
        && sendCallbackLastErrorInside === null,
      tabsSendMessageNoReceiverLastErrorOK:
        noReceiverInside === "Could not establish connection. Receiving end does not exist."
        && noReceiverArgCount === 0
        && noReceiverOutside === null,
      tabsConnectOK:
        port.name === "content"
        && typeof port.postMessage === "function"
        && typeof port.disconnect === "function",
      tabsConnectDisconnectOK: disconnectSeen === true,
      scriptingExecuteScriptOK:
        Array.isArray(executeResult)
        && executeResult.length === 1
        && executeResult[0].frameId === 0
        && executeResult[0].result
        && executeResult[0].result.source === "controlledSyntheticModel",
      scriptingProductTargetBlockedOK:
        typeof productBlockedMessage === "string"
        && productBlockedMessage.length > 0,
      callbackLastErrorScopedOK:
        noReceiverInside === "Could not establish connection. Receiving end does not exist."
        && noReceiverOutside === null,
      promiseRejectsOnErrorOK:
        typeof productBlockedMessage === "string"
        && productBlockedMessage.length > 0
    };
    """

    @MainActor
    static func run(
        scriptBody: String,
        configuration: ChromeMV3TabsScriptingJSBridgeConfiguration =
            .syntheticHarness(),
        tabRegistry: ChromeMV3SyntheticTabRegistry? = nil,
        permissionBroker: ChromeMV3PermissionBroker? = nil,
        permissionRuntimeOwner:
            ChromeMV3PermissionRuntimeStateOwner? = nil,
        html: String =
            "<!doctype html><meta charset='utf-8'><title>Tabs Scripting JS MVP</title>"
    ) async -> ChromeMV3TabsScriptingJSSyntheticHarnessResult {
        let resolvedRegistry =
            tabRegistry
            ?? defaultTabRegistry(configuration: configuration)
        let bridgeHandler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            tabRegistry: resolvedRegistry,
            permissionBroker: permissionBroker
                ?? ChromeMV3TabsScriptingPermissionFixtures.hostAndScripting(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID
                ),
            permissionRuntimeOwner: permissionRuntimeOwner
        )
        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.sumiIsNormalTabWebViewConfiguration = false
        let scriptHandler = ChromeMV3TabsScriptingJSScriptMessageHandler(
            handler: bridgeHandler
        )
        webViewConfiguration.userContentController.addScriptMessageHandler(
            scriptHandler,
            contentWorld: .page,
            name: ChromeMV3TabsScriptingJSShimSource
                .bridgeMessageHandlerName
        )
        let shimSource = ChromeMV3TabsScriptingJSShimSource.source(
            configuration: configuration
        )
        let userScript = WKUserScript(
            source: shimSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webViewConfiguration.userContentController.addUserScript(userScript)

        let webView = WKWebView(
            frame: .zero,
            configuration: webViewConfiguration
        )
        let observer = ChromeMV3TabsScriptingJSSyntheticNavigationObserver()
        webView.navigationDelegate = observer
        _ = webView.loadHTMLString(html, baseURL: nil)
        let navigationResult = await observer.wait()
        var diagnostics: [String] = [
            "Synthetic WKWebView is hidden and is not registered as a product tab.",
            "tabs/scripting shim is installed as a WKUserScript only on this controlled synthetic harness configuration.",
            "tabs/scripting bridge handler is installed only on the synthetic harness WKUserContentController.",
        ]
        if case .failure(let error) = navigationResult {
            diagnostics.append(error.localizedDescription)
        }

        var scriptSucceeded = false
        var resultJSON: String?
        if case .success = navigationResult {
            do {
                let result = try await webView.callAsyncJavaScript(
                    scriptBody,
                    arguments: [:],
                    in: nil,
                    contentWorld: .page
                )
                resultJSON = ChromeMV3StorageValue(
                    tabsScriptingWebKitValue: result ?? NSNull()
                )
                .flatMap { try? $0.canonicalJSONString() }
                scriptSucceeded = true
            } catch {
                diagnostics.append(error.localizedDescription)
            }
        }

        let modelReport = ChromeMV3TabsScriptingMVPReportGenerator.makeReport(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            moduleState: configuration.moduleState
        )
        let webKitSummary =
            ChromeMV3TabsScriptingWebKitExecutionSummary
            .fromWebKitScriptResult(
                json: resultJSON,
                scriptEvaluationSucceeded: scriptSucceeded,
                tabsScriptingModelHandlersAvailable:
                    modelReport.behaviorSummary
                    .tabsScriptingModelHandlersAvailable,
                tabsScriptingJSBridgeAvailableInSyntheticHarness:
                    configuration.tabsJSBridgeAvailableInSyntheticHarness,
                diagnostics: diagnostics
            )
        let report = ChromeMV3TabsScriptingMVPReportGenerator.makeReport(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            moduleState: configuration.moduleState,
            webKitExecutionSummary: webKitSummary
        )
        let registrySummary = bridgeHandler.tabRegistry.summary
        let endpointSummary =
            bridgeHandler.tabRegistry.contentScriptEndpointSummary
        let handledRequestCount = bridgeHandler.handledRequestCount
        let queryRequestCount = bridgeHandler.queryRequestCount
        let sendMessageDispatchCount =
            bridgeHandler.sendMessageDispatchCount
        let modelPortCreateCount = bridgeHandler.modelPortCreateCount
        let modelPortDisconnectCount =
            bridgeHandler.modelPortDisconnectCount
        let executeScriptRequestCount =
            bridgeHandler.executeScriptRequestCount
        let userScriptCount =
            webViewConfiguration.userContentController.userScripts.count

        webView.navigationDelegate = nil
        webViewConfiguration.userContentController
            .removeScriptMessageHandler(
                forName:
                    ChromeMV3TabsScriptingJSShimSource
                    .bridgeMessageHandlerName,
                contentWorld: .page
            )
        webViewConfiguration.userContentController.removeAllUserScripts()
        bridgeHandler.tearDown()
        let teardownRegistrySummary = bridgeHandler.tabRegistry.summary
        let teardownEndpointSummary =
            bridgeHandler.tabRegistry.contentScriptEndpointSummary

        return ChromeMV3TabsScriptingJSSyntheticHarnessResult(
            scriptEvaluationSucceeded: scriptSucceeded,
            scriptResultJSON: resultJSON,
            report: report,
            webKitExecutionSummary: webKitSummary,
            tabRegistrySummary: registrySummary,
            contentScriptEndpointSummary: endpointSummary,
            tabRegistrySummaryAfterTeardown: teardownRegistrySummary,
            contentScriptEndpointSummaryAfterTeardown:
                teardownEndpointSummary,
            handledRequestCount: handledRequestCount,
            queryRequestCount: queryRequestCount,
            sendMessageDispatchCount: sendMessageDispatchCount,
            modelPortCreateCount: modelPortCreateCount,
            modelPortDisconnectCount: modelPortDisconnectCount,
            executeScriptRequestCount: executeScriptRequestCount,
            userScriptCount: userScriptCount,
            scriptMessageHandlerCount: 1,
            syntheticWebViewCreated: true,
            tabsScriptingJSBridgeAvailableInSyntheticHarness:
                configuration.tabsJSBridgeAvailableInSyntheticHarness,
            tabsJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            scriptingAvailableInProduct: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedTabsScripting(
                    diagnostics
                        + webKitSummary.diagnostics
                        + registrySummary.diagnostics
                        + endpointSummary.diagnostics
                )
        )
    }

    private static func defaultTabRegistry(
        configuration: ChromeMV3TabsScriptingJSBridgeConfiguration
    ) -> ChromeMV3SyntheticTabRegistry {
        let registry =
            ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                includeProductNormalTab: true
            )
        registry.register(
            ChromeMV3SyntheticTabRecord(
                id: 7,
                profileID: configuration.profileID,
                url: "https://example.com/no-listener",
                title: "No Listener",
                active: false,
                index: 2,
                frames: [
                    ChromeMV3SyntheticTabFrameRecord(
                        frameID: 0,
                        documentID: "document-no-listener",
                        url: "https://example.com/no-listener",
                        staticContentScriptEndpointRegistered: false,
                        connectEndpointRegistered: false,
                        diagnostics: [
                            "Missing endpoint fixture drives WebKit lastError callback coverage.",
                        ]
                    ),
                ],
                diagnostics: [
                    "Controlled synthetic tab has no content-script receiver.",
                ]
            )
        )
        return registry
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3PermissionsJSScriptMessageHandler:
    NSObject,
    WKScriptMessageHandlerWithReply
{
    let handler: ChromeMV3PermissionsJSBridgeHandler

    init(handler: ChromeMV3PermissionsJSBridgeHandler) {
        self.handler = handler
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        _ = userContentController
        let response = handler.handle(message.body)
        return (response.foundationObject, nil)
    }
}

struct ChromeMV3PermissionsJSSyntheticHarnessResult:
    Codable,
    Equatable,
    Sendable
{
    var scriptEvaluationSucceeded: Bool
    var scriptResultJSON: String?
    var report: ChromeMV3PermissionImplementationReport
    var webKitExecutionSummary:
        ChromeMV3PermissionsWebKitExecutionSummary
    var permissionRuntimeSnapshot:
        ChromeMV3PermissionRuntimeStateOwnerSnapshot
    var permissionRuntimeSnapshotAfterTeardown:
        ChromeMV3PermissionRuntimeStateOwnerSnapshot
    var handledRequestCount: Int
    var permissionsRequestCount: Int
    var rejectedRequestCount: Int
    var userScriptCount: Int
    var scriptMessageHandlerCount: Int
    var syntheticWebViewCreated: Bool
    var permissionsJSBridgeAvailableInSyntheticHarness: Bool
    var permissionsJSBridgeAvailableInProduct: Bool
    var permissionUIAvailableInProduct: Bool
    var activeTabAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var nativeMessagingAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

@available(macOS 15.5, *)
enum ChromeMV3PermissionsJSSyntheticHarness {
    static let reportVerificationScriptBody = """
    const exposedNamespaces = Object.keys(chrome).sort();
    const permissionsKeys = Object.keys(chrome.permissions).sort();
    const runtimeKeys = Object.keys(chrome.runtime).sort();
    const addedPayloads = [];
    const removedPayloads = [];
    chrome.permissions.onAdded.addListener((payload) => {
      addedPayloads.push(payload);
    });
    chrome.permissions.onRemoved.addListener((payload) => {
      removedPayloads.push(payload);
    });

    let containsCallbackResult = null;
    let containsCallbackLastErrorInside = "unset";
    await new Promise((resolve) => {
      chrome.permissions.contains({permissions: ["tabs"]}, function(result) {
        containsCallbackResult = result;
        containsCallbackLastErrorInside = chrome.runtime.lastError || null;
        resolve();
      });
    });
    const containsCallbackLastErrorOutside = chrome.runtime.lastError || null;
    const containsPromiseResult =
      await chrome.permissions.contains({permissions: ["tabs"]});
    const containsMissingBefore =
      await chrome.permissions.contains({permissions: ["bookmarks"]});

    let getAllCallbackResult = null;
    let getAllCallbackLastErrorInside = "unset";
    await new Promise((resolve) => {
      chrome.permissions.getAll(function(result) {
        getAllCallbackResult = result;
        getAllCallbackLastErrorInside = chrome.runtime.lastError || null;
        resolve();
      });
    });
    const getAllCallbackLastErrorOutside = chrome.runtime.lastError || null;
    const getAllInitial = await chrome.permissions.getAll();

    const acceptedPermission = await chrome.permissions.request({
      permissions: ["history"],
      __sumiUserGestureModeled: true,
      __sumiModeledPromptResult: "accepted"
    });
    const acceptedOrigin = await chrome.permissions.request({
      origins: ["https://example.com/"],
      __sumiUserGestureModeled: true,
      __sumiModeledPromptResult: "accepted"
    });
    const containsOriginAfterGrant =
      await chrome.permissions.contains({origins: ["https://example.com/"]});
    const getAllAfterGrant = await chrome.permissions.getAll();

    const deniedModeled = await chrome.permissions.request({
      permissions: ["bookmarks"],
      __sumiUserGestureModeled: true,
      __sumiModeledPromptResult: "denied"
    });
    const containsBookmarksAfterDenied =
      await chrome.permissions.contains({permissions: ["bookmarks"]});

    let promptRejectedMessage = null;
    try {
      await chrome.permissions.request({
        permissions: ["topSites"],
        __sumiUserGestureModeled: true
      });
    } catch (error) {
      promptRejectedMessage = error && error.message;
    }

    let undeclaredRejectedMessage = null;
    try {
      await chrome.permissions.request({
        permissions: ["downloads"],
        __sumiUserGestureModeled: true,
        __sumiModeledPromptResult: "accepted"
      });
    } catch (error) {
      undeclaredRejectedMessage = error && error.message;
    }

    const removedPermission =
      await chrome.permissions.remove({permissions: ["history"]});
    const containsHistoryAfterRemove =
      await chrome.permissions.contains({permissions: ["history"]});
    const removedOrigin =
      await chrome.permissions.remove({origins: ["https://example.com/"]});
    const containsOriginAfterRemove =
      await chrome.permissions.contains({origins: ["https://example.com/"]});

    let removeRequiredInside = null;
    let removeRequiredArgCount = -1;
    await new Promise((resolve) => {
      chrome.permissions.remove({permissions: ["tabs"]}, function() {
        removeRequiredArgCount = arguments.length;
        removeRequiredInside =
          chrome.runtime.lastError && chrome.runtime.lastError.message;
        resolve();
      });
    });
    const removeRequiredOutside = chrome.runtime.lastError || null;
    const getAllAfterRemove = await chrome.permissions.getAll();

    const initialRequiredPermissionsOK =
      Array.isArray(getAllInitial.permissions)
      && getAllInitial.permissions.join("|") === "activeTab|scripting|tabs";
    const callbackRequiredPermissionsOK =
      getAllCallbackResult
      && Array.isArray(getAllCallbackResult.permissions)
      && getAllCallbackResult.permissions.join("|") === "activeTab|scripting|tabs";
    const grantedPermissionVisible =
      getAllAfterGrant.permissions.includes("history");
    const grantedOriginVisible =
      getAllAfterGrant.origins.includes("https://example.com/");
    const historyRemoved =
      !getAllAfterRemove.permissions.includes("history");
    const originRemoved =
      !getAllAfterRemove.origins.includes("https://example.com/");
    const addedHistoryPayload = addedPayloads.some((payload) => {
      return Array.isArray(payload.permissions)
        && payload.permissions.includes("history");
    });
    const addedOriginPayload = addedPayloads.some((payload) => {
      return Array.isArray(payload.origins)
        && payload.origins.includes("https://example.com/");
    });
    const removedHistoryPayload = removedPayloads.some((payload) => {
      return Array.isArray(payload.permissions)
        && payload.permissions.includes("history");
    });
    const removedOriginPayload = removedPayloads.some((payload) => {
      return Array.isArray(payload.origins)
        && payload.origins.includes("https://example.com/");
    });

    return {
      exposedNamespaces,
      permissionsKeys,
      runtimeKeys,
      tabsMissing: chrome.tabs === undefined,
      scriptingMissing: chrome.scripting === undefined,
      storageMissing: chrome.storage === undefined,
      nativeMessagingMissing: chrome.nativeMessaging === undefined,
      containsCallbackResult,
      containsPromiseResult,
      getAllInitial,
      getAllAfterGrant,
      getAllAfterRemove,
      promptRejectedMessage,
      undeclaredRejectedMessage,
      removeRequiredInside,
      removeRequiredOutside,
      removeRequiredArgCount,
      addedPayloads,
      removedPayloads,
      containsCallbackOK:
        containsCallbackResult === true
        && containsCallbackLastErrorInside === null
        && containsCallbackLastErrorOutside === null,
      containsPromiseOK: containsPromiseResult === true,
      containsMissingOptionalFalseOK:
        containsMissingBefore === false
        && containsBookmarksAfterDenied === false,
      containsOriginAfterGrantOK:
        containsOriginAfterGrant === true && grantedOriginVisible,
      containsRevokedOptionalFalseOK:
        containsHistoryAfterRemove === false
        && containsOriginAfterRemove === false,
      getAllCallbackOK:
        callbackRequiredPermissionsOK
        && getAllCallbackLastErrorInside === null
        && getAllCallbackLastErrorOutside === null,
      getAllPromiseOK: initialRequiredPermissionsOK,
      requestAcceptedPermissionOK:
        acceptedPermission === true && grantedPermissionVisible,
      requestAcceptedOriginOK:
        acceptedOrigin === true && containsOriginAfterGrant === true,
      requestDeniedModeledOK:
        deniedModeled === false && containsBookmarksAfterDenied === false,
      requestWithoutPromptRejectedOK:
        typeof promptRejectedMessage === "string"
        && promptRejectedMessage.includes("product permission UI"),
      requestUndeclaredRejectedOK:
        typeof undeclaredRejectedMessage === "string"
        && undeclaredRejectedMessage.includes("not declared optional"),
      removeOptionalPermissionOK:
        removedPermission === true
        && containsHistoryAfterRemove === false
        && historyRemoved,
      removeOptionalOriginOK:
        removedOrigin === true
        && containsOriginAfterRemove === false
        && originRemoved,
      removeRequiredCallbackLastErrorOK:
        removeRequiredInside === "Required manifest permissions cannot be removed."
        && removeRequiredArgCount === 0
        && removeRequiredOutside === null,
      callbackModeOK:
        containsCallbackResult === true
        && removeRequiredArgCount === 0,
      promiseModeOK:
        containsPromiseResult === true
        && acceptedPermission === true,
      lastErrorScopedOK:
        removeRequiredInside === "Required manifest permissions cannot be removed."
        && removeRequiredOutside === null,
      onAddedPayloadOK:
        addedHistoryPayload && addedOriginPayload,
      onRemovedPayloadOK:
        removedHistoryPayload && removedOriginPayload
    };
    """

    @MainActor
    static func run(
        scriptBody: String,
        configuration: ChromeMV3PermissionsJSBridgeConfiguration =
            .syntheticHarness(),
        permissionRuntimeOwner:
            ChromeMV3PermissionRuntimeStateOwner? = nil,
        html: String =
            "<!doctype html><meta charset='utf-8'><title>Permissions JS MVP</title>"
    ) async -> ChromeMV3PermissionsJSSyntheticHarnessResult {
        let bridgeHandler = ChromeMV3PermissionsJSBridgeHandler(
            configuration: configuration,
            permissionRuntimeOwner: permissionRuntimeOwner
        )
        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.sumiIsNormalTabWebViewConfiguration = false
        let scriptHandler = ChromeMV3PermissionsJSScriptMessageHandler(
            handler: bridgeHandler
        )
        webViewConfiguration.userContentController.addScriptMessageHandler(
            scriptHandler,
            contentWorld: .page,
            name:
                ChromeMV3PermissionsJSShimSource
                .bridgeMessageHandlerName
        )
        let shimSource = ChromeMV3PermissionsJSShimSource.source(
            configuration: configuration
        )
        let userScript = WKUserScript(
            source: shimSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webViewConfiguration.userContentController.addUserScript(userScript)

        let webView = WKWebView(
            frame: .zero,
            configuration: webViewConfiguration
        )
        let observer = ChromeMV3TabsScriptingJSSyntheticNavigationObserver()
        webView.navigationDelegate = observer
        _ = webView.loadHTMLString(html, baseURL: nil)
        let navigationResult = await observer.wait()
        var diagnostics: [String] = [
            "Synthetic WKWebView is hidden and is not registered as a product tab.",
            "permissions shim is installed as a WKUserScript only on this controlled synthetic harness configuration.",
            "permissions bridge handler is installed only on the synthetic harness WKUserContentController.",
            "Product permission UI and product normal-tab runtime bridge remain unavailable.",
        ]
        if case .failure(let error) = navigationResult {
            diagnostics.append(error.localizedDescription)
        }

        var scriptSucceeded = false
        var resultJSON: String?
        if case .success = navigationResult {
            do {
                let result = try await webView.callAsyncJavaScript(
                    scriptBody,
                    arguments: [:],
                    in: nil,
                    contentWorld: .page
                )
                resultJSON = ChromeMV3StorageValue(
                    tabsScriptingWebKitValue: result ?? NSNull()
                )
                .flatMap { try? $0.canonicalJSONString() }
                scriptSucceeded = true
            } catch {
                diagnostics.append(error.localizedDescription)
            }
        }

        let runtimeSnapshot = bridgeHandler.permissionRuntimeSnapshot
        let webKitSummary =
            ChromeMV3PermissionsWebKitExecutionSummary
            .fromWebKitScriptResult(
                json: resultJSON,
                scriptEvaluationSucceeded: scriptSucceeded,
                permissionRuntimeStateAvailable: true,
                permissionsModelHandlersAvailable:
                    bridgeHandler.permissionsRequestCount > 0,
                permissionsJSBridgeAvailableInSyntheticHarness:
                    configuration
                    .permissionsJSBridgeAvailableInSyntheticHarness,
                diagnostics: diagnostics
            )
        let report = ChromeMV3PermissionImplementationReportGenerator
            .makeReport(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                webKitSyntheticPermissionVerificationStatus:
                    webKitSummary.status,
                permissionsWebKitExecutionSummary: webKitSummary
            )
        let handledRequestCount = bridgeHandler.handledRequestCount
        let permissionsRequestCount = bridgeHandler.permissionsRequestCount
        let rejectedRequestCount = bridgeHandler.rejectedRequestCount
        let userScriptCount =
            webViewConfiguration.userContentController.userScripts.count

        webView.navigationDelegate = nil
        webViewConfiguration.userContentController
            .removeScriptMessageHandler(
                forName:
                    ChromeMV3PermissionsJSShimSource
                    .bridgeMessageHandlerName,
                contentWorld: .page
            )
        webViewConfiguration.userContentController.removeAllUserScripts()
        bridgeHandler.tearDown()
        let teardownSnapshot = bridgeHandler.permissionRuntimeSnapshot

        return ChromeMV3PermissionsJSSyntheticHarnessResult(
            scriptEvaluationSucceeded: scriptSucceeded,
            scriptResultJSON: resultJSON,
            report: report,
            webKitExecutionSummary: webKitSummary,
            permissionRuntimeSnapshot: runtimeSnapshot,
            permissionRuntimeSnapshotAfterTeardown: teardownSnapshot,
            handledRequestCount: handledRequestCount,
            permissionsRequestCount: permissionsRequestCount,
            rejectedRequestCount: rejectedRequestCount,
            userScriptCount: userScriptCount,
            scriptMessageHandlerCount: 1,
            syntheticWebViewCreated: true,
            permissionsJSBridgeAvailableInSyntheticHarness:
                configuration.permissionsJSBridgeAvailableInSyntheticHarness,
            permissionsJSBridgeAvailableInProduct: false,
            permissionUIAvailableInProduct: false,
            activeTabAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            nativeMessagingAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedTabsScripting(
                    diagnostics
                        + webKitSummary.diagnostics
                        + runtimeSnapshot.diagnostics
                )
        )
    }
}
#endif

enum ChromeMV3TabsScriptingPermissionFixtures {
    static func hostAndScripting(
        extensionID: String,
        profileID: String
    ) -> ChromeMV3PermissionBroker {
        broker(
            extensionID: extensionID,
            profileID: profileID,
            requiredPermissions: ["activeTab", "scripting", "tabs"],
            hostPermissions: ["https://example.com/*"]
        )
    }

    static func hostOnly(
        extensionID: String,
        profileID: String
    ) -> ChromeMV3PermissionBroker {
        broker(
            extensionID: extensionID,
            profileID: profileID,
            requiredPermissions: ["activeTab", "tabs"],
            hostPermissions: ["https://example.com/*"]
        )
    }

    static func noHostAccess(
        extensionID: String,
        profileID: String
    ) -> ChromeMV3PermissionBroker {
        broker(
            extensionID: extensionID,
            profileID: profileID,
            requiredPermissions: ["activeTab"],
            hostPermissions: []
        )
    }

    static func activeTabGrant(
        extensionID: String,
        profileID: String,
        tabID: Int = 1,
        url: String = "https://example.com/login",
        includeScripting: Bool = true
    ) -> ChromeMV3PermissionBroker {
        let grant = ChromeMV3ActiveTabGrant(
            extensionID: extensionID,
            profileID: profileID,
            tabID: tabID,
            scope: .origin(
                ChromeMV3PermissionBrokerURL.origin(from: url)
                    ?? "https://example.com"
            ),
            reason: .testFixture,
            userGestureModeled: true,
            createdSequence: 1,
            diagnostics: [
                "Modeled activeTab grant for tabs/scripting MVP tests.",
            ]
        )
        return broker(
            extensionID: extensionID,
            profileID: profileID,
            requiredPermissions:
                includeScripting
                    ? ["activeTab", "scripting"]
                    : ["activeTab"],
            hostPermissions: [],
            activeTabGrants: [grant]
        )
    }

    private static func broker(
        extensionID: String,
        profileID: String,
        requiredPermissions: [String],
        hostPermissions: [String],
        activeTabGrants: [ChromeMV3ActiveTabGrant] = []
    ) -> ChromeMV3PermissionBroker {
        ChromeMV3PermissionBroker(
            state:
                ChromeMV3PermissionBrokerState(
                    extensionID: extensionID,
                    profileID: profileID,
                    requiredPermissions: requiredPermissions,
                    hostPermissions: hostPermissions,
                    activeTabGrants: activeTabGrants,
                    diagnostics: [
                        "tabs/scripting MVP permission fixture is deterministic.",
                    ]
                )
        )
    }
}

private extension ChromeMV3StorageValue {
    static func permissionEventPayload(
        _ payload: ChromeMV3PermissionsAPIEventPayload
    ) -> ChromeMV3StorageValue {
        .object([
            "eventKind": .string(payload.eventKind.rawValue),
            "source": .string(payload.source.rawValue),
            "extensionID": .string(payload.extensionID),
            "profileID": .string(payload.profileID),
            "permissions": .array(
                payload.permissions.map(ChromeMV3StorageValue.string)
            ),
            "origins": .array(
                payload.origins.map(ChromeMV3StorageValue.string)
            ),
            "wouldDispatchNow": .bool(payload.wouldDispatchNow),
            "serviceWorkerWakeRequired":
                .bool(payload.serviceWorkerWakeRequired),
        ])
    }

    init?(tabsScriptingWebKitValue value: Any) {
        if value is NSNull {
            self = .null
        } else if let string = value as? String {
            self = .string(string)
        } else if let bool = value as? Bool {
            self = .bool(bool)
        } else if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        } else if let array = value as? [Any] {
            var values: [ChromeMV3StorageValue] = []
            for entry in array {
                guard let converted = ChromeMV3StorageValue(
                    tabsScriptingWebKitValue: entry
                ) else { return nil }
                values.append(converted)
            }
            self = .array(values)
        } else if let object = value as? [String: Any] {
            var converted: [String: ChromeMV3StorageValue] = [:]
            for (key, entry) in object {
                guard let value = ChromeMV3StorageValue(
                    tabsScriptingWebKitValue: entry
                ) else { return nil }
                converted[key] = value
            }
            self = .object(converted)
        } else {
            return nil
        }
    }

    var objectValue: [String: ChromeMV3StorageValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    var stringValue: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self,
              value.isFinite,
              value.rounded() == value,
              value >= 0,
              value <= Double(Int.max)
        else { return nil }
        return Int(value)
    }

    var tabsScriptingFoundationObject: Any {
        switch self {
        case .array(let values):
            return values.map(\.tabsScriptingFoundationObject)
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .number(let value):
            return value
        case .object(let object):
            return object.mapValues(\.tabsScriptingFoundationObject)
        case .string(let value):
            return value
        }
    }
}

private extension Array where Element: Hashable & Comparable {
    func uniqueSorted() -> [Element] {
        Array(Set(self)).sorted()
    }
}

private func normalizedTabsScripting(
    _ value: String,
    fallback: String
) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

private func stableIDTabsScripting(
    prefix: String,
    parts: [String]
) -> String {
    let joined = parts.joined(separator: "\u{1F}")
    let digest = SHA256.hash(data: Data(joined.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "\(prefix)-\(String(hex.prefix(16)))"
}

private func uniqueSortedTabsScripting(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}
