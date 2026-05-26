//
//  ChromeMV3ExtensionEventAPIsRuntime.swift
//  Sumi
//
//  DEBUG/internal synthetic chrome.contextMenus, chrome.alarms, and
//  chrome.webNavigation MVP for controlled fixtures. This is not product
//  extension support, does not install product menu UI, does not attach to
//  normal browsing WebViews, does not observe product navigation, and does not
//  create background schedulers.
//

import CryptoKit
import Foundation

struct ChromeMV3ExtensionEventAPIsConfiguration:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var surfaceID: String
    var surfaceKind: ChromeMV3RuntimeJSBridgeSurfaceKind
    var extensionBaseURLString: String?
    var moduleState: ChromeMV3ProfileHostModuleState
    var explicitInternalEventAPIsBridgeAllowed: Bool
    var contextMenusAvailableInInternalFixture: Bool
    var contextMenusAvailableInProduct: Bool
    var alarmsAvailableInInternalFixture: Bool
    var alarmsRealSchedulingAvailableInProduct: Bool
    var webNavigationAvailableInInternalFixture: Bool
    var webNavigationAvailableInProduct: Bool
    var serviceWorkerLifecycleAvailableInInternalFixture: Bool
    var serviceWorkerWakeAvailableInProduct: Bool
    var serviceWorkerPermanentBackgroundAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    var sourceContext: ChromeMV3JSBridgeSourceContext {
        surfaceKind.sourceContext
    }

    static func syntheticHarness(
        extensionID: String = "extension-event-apis-mvp-extension",
        profileID: String = "extension-event-apis-mvp-profile",
        surfaceID: String = "extension-event-apis-mvp-synthetic-surface",
        surfaceKind: ChromeMV3RuntimeJSBridgeSurfaceKind =
            .extensionPageFixture,
        extensionBaseURLString: String? =
            "chrome-extension://extension-event-apis-mvp-extension/",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        explicitInternalEventAPIsBridgeAllowed: Bool = true
    ) -> ChromeMV3ExtensionEventAPIsConfiguration {
        let normalizedExtensionID = normalizedExtensionEventAPIs(
            extensionID,
            fallback: "extension-event-apis-mvp-extension"
        )
        let normalizedProfileID = normalizedExtensionEventAPIs(
            profileID,
            fallback: "extension-event-apis-mvp-profile"
        )
        let allowed = moduleState == .enabled
            && explicitInternalEventAPIsBridgeAllowed
        return ChromeMV3ExtensionEventAPIsConfiguration(
            extensionID: normalizedExtensionID,
            profileID: normalizedProfileID,
            surfaceID: normalizedExtensionEventAPIs(
                surfaceID,
                fallback: "extension-event-apis-synthetic-surface"
            ),
            surfaceKind: surfaceKind,
            extensionBaseURLString: extensionBaseURLString,
            moduleState: moduleState,
            explicitInternalEventAPIsBridgeAllowed:
                explicitInternalEventAPIsBridgeAllowed,
            contextMenusAvailableInInternalFixture: allowed,
            contextMenusAvailableInProduct: false,
            alarmsAvailableInInternalFixture: allowed,
            alarmsRealSchedulingAvailableInProduct: false,
            webNavigationAvailableInInternalFixture: allowed,
            webNavigationAvailableInProduct: false,
            serviceWorkerLifecycleAvailableInInternalFixture: allowed,
            serviceWorkerWakeAvailableInProduct: false,
            serviceWorkerPermanentBackgroundAvailable: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedExtensionEventAPIs([
                    "Event API bridge is confined to a DEBUG/internal synthetic surface.",
                    "contextMenus is an internal model only and does not create product menu UI.",
                    "alarms stores timing values only; alarm firing requires an explicit fixture trigger.",
                    "webNavigation consumes only controlled synthetic navigation events.",
                    "Product normal-tab runtime bridge remains unavailable.",
                    "runtimeLoadable remains false.",
                ])
        )
    }
}

enum ChromeMV3ExtensionEventAPIErrorCode: String, Codable, Sendable {
    case duplicateMenuItemID
    case extensionDisabled
    case invalidArguments
    case listenerMissing
    case menuItemMissing
    case methodUnsupported
    case namespaceUnsupported
    case permissionMissing
    case syntheticEventBlocked
    case unsupported

    var lastErrorMessage: String {
        switch self {
        case .duplicateMenuItemID:
            return "Cannot create item with duplicate id."
        case .extensionDisabled:
            return "Extensions module is disabled."
        case .invalidArguments:
            return "Invalid Chrome MV3 event API arguments."
        case .listenerMissing:
            return "Could not establish connection. Receiving end does not exist."
        case .menuItemMissing:
            return "Cannot find menu item with specified id."
        case .methodUnsupported:
            return "Chrome MV3 event API method is not supported by this internal MVP."
        case .namespaceUnsupported:
            return "Chrome MV3 event API namespace is not supported by this internal MVP."
        case .permissionMissing:
            return "Required API permission is missing in the synthetic permission broker."
        case .syntheticEventBlocked:
            return "Synthetic event did not match an internal listener or fixture."
        case .unsupported:
            return "Requested operation is outside the internal synthetic MVP."
        }
    }
}

private struct ChromeMV3ExtensionEventAPIArgumentError: Error, Sendable {
    let message: String
}

enum ChromeMV3ContextMenuItemType:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case checkbox
    case normal
    case radio
    case separator

    static func < (
        lhs: ChromeMV3ContextMenuItemType,
        rhs: ChromeMV3ContextMenuItemType
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ContextMenuContext:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case action
    case all
    case audio
    case browserAction = "browser_action"
    case editable
    case frame
    case image
    case launcher
    case link
    case page
    case pageAction = "page_action"
    case selection
    case tab
    case video

    static func < (
        lhs: ChromeMV3ContextMenuContext,
        rhs: ChromeMV3ContextMenuContext
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ContextMenuItemRecord:
    Codable,
    Equatable,
    Sendable
{
    var id: String
    var extensionID: String
    var profileID: String
    var title: String?
    var type: ChromeMV3ContextMenuItemType
    var contexts: [ChromeMV3ContextMenuContext]
    var parentID: String?
    var checked: Bool?
    var enabled: Bool
    var visible: Bool
    var documentUrlPatterns: [String]
    var targetUrlPatterns: [String]
    var createdSequence: Int
    var updatedSequence: Int?
    var diagnostics: [String]

    var storageValue: ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "id": .string(id),
            "type": .string(type.rawValue),
            "contexts": .array(contexts.map { .string($0.rawValue) }),
            "enabled": .bool(enabled),
            "visible": .bool(visible),
            "documentUrlPatterns":
                .array(documentUrlPatterns.map(ChromeMV3StorageValue.string)),
            "targetUrlPatterns":
                .array(targetUrlPatterns.map(ChromeMV3StorageValue.string)),
            "createdSequence": .number(Double(createdSequence)),
        ]
        if let title {
            object["title"] = .string(title)
        }
        if let parentID {
            object["parentId"] = .string(parentID)
        }
        if let checked {
            object["checked"] = .bool(checked)
        }
        if let updatedSequence {
            object["updatedSequence"] = .number(Double(updatedSequence))
        }
        return .object(object)
    }
}

struct ChromeMV3ContextMenusRuntimeSummary:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var itemCount: Int
    var itemIDs: [String]
    var operationRecordCount: Int
    var clickDispatchCount: Int
    var contextMenusAvailableInInternalFixture: Bool
    var contextMenusAvailableInProduct: Bool
    var productContextMenuUIAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

struct ChromeMV3ContextMenusOperationRecord:
    Codable,
    Equatable,
    Sendable
{
    var sequence: Int
    var methodName: String
    var succeeded: Bool
    var menuItemID: String?
    var resultPayload: ChromeMV3StorageValue?
    var lastErrorMessage: String?
    var lastErrorCode: String?
    var diagnostics: [String]
}

struct ChromeMV3ContextMenusSyntheticClickFixture:
    Codable,
    Equatable,
    Sendable
{
    var menuItemID: String
    var context: ChromeMV3ContextMenuContext
    var tabID: Int?
    var frameID: Int?
    var pageURL: String?
    var frameURL: String?
    var linkURL: String?
    var srcURL: String?
    var selectionText: String?
    var editable: Bool
    var checked: Bool?
    var wasChecked: Bool?

    static func page(
        menuItemID: String,
        tabID: Int = 1,
        pageURL: String = "https://example.com/login"
    ) -> ChromeMV3ContextMenusSyntheticClickFixture {
        ChromeMV3ContextMenusSyntheticClickFixture(
            menuItemID: menuItemID,
            context: .page,
            tabID: tabID,
            frameID: 0,
            pageURL: pageURL,
            frameURL: pageURL,
            linkURL: nil,
            srcURL: nil,
            selectionText: nil,
            editable: false,
            checked: nil,
            wasChecked: nil
        )
    }
}

struct ChromeMV3ContextMenusClickDispatchRecord:
    Codable,
    Equatable,
    Sendable
{
    var sequence: Int
    var menuItemID: String
    var fixture: ChromeMV3ContextMenusSyntheticClickFixture
    var clickInfoPayload: ChromeMV3StorageValue
    var tabPayload: ChromeMV3StorageValue?
    var matchedListenerCount: Int
    var permissionRedacted: Bool
    var serviceWorkerLifecycleWakeResult:
        ChromeMV3ServiceWorkerInternalWakeResult?
    var sharedLifecycleSessionID: String?
    var sharedLifecycleSessionUsed: Bool
    var dispatched: Bool
    var lastErrorMessage: String?
    var diagnostics: [String]
}

struct ChromeMV3AlarmRecord:
    Codable,
    Equatable,
    Sendable
{
    var name: String
    var extensionID: String
    var profileID: String
    var scheduledTime: Double
    var delayInMinutes: Double?
    var periodInMinutes: Double?
    var createdSequence: Int
    var replacedExistingAlarm: Bool
    var cleared: Bool
    var diagnostics: [String]

    var repeating: Bool {
        periodInMinutes != nil
    }

    var storageValue: ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "name": .string(name),
            "scheduledTime": .number(scheduledTime),
            "repeating": .bool(repeating),
            "createdSequence": .number(Double(createdSequence)),
        ]
        if let periodInMinutes {
            object["periodInMinutes"] = .number(periodInMinutes)
        }
        return .object(object)
    }
}

struct ChromeMV3AlarmsRuntimeSummary:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var alarmCount: Int
    var alarmNames: [String]
    var operationRecordCount: Int
    var triggerRecordCount: Int
    var repeatingAlarmCount: Int
    var explicitTestControlledTriggersOnly: Bool
    var alarmsAvailableInInternalFixture: Bool
    var alarmsRealSchedulingAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

struct ChromeMV3AlarmsOperationRecord:
    Codable,
    Equatable,
    Sendable
{
    var sequence: Int
    var methodName: String
    var succeeded: Bool
    var alarmName: String?
    var resultPayload: ChromeMV3StorageValue?
    var lastErrorMessage: String?
    var lastErrorCode: String?
    var diagnostics: [String]
}

struct ChromeMV3AlarmTriggerRecord:
    Codable,
    Equatable,
    Sendable
{
    var sequence: Int
    var alarmName: String
    var alarmPayload: ChromeMV3StorageValue?
    var matchedListenerCount: Int
    var serviceWorkerLifecycleWakeResult:
        ChromeMV3ServiceWorkerInternalWakeResult?
    var sharedLifecycleSessionID: String?
    var sharedLifecycleSessionUsed: Bool
    var dispatched: Bool
    var repeatingAlarmValueStateRetained: Bool
    var lastErrorMessage: String?
    var diagnostics: [String]
}

enum ChromeMV3WebNavigationEventKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case onBeforeNavigate
    case onCommitted
    case onCompleted
    case onDOMContentLoaded
    case onErrorOccurred
    case onHistoryStateUpdated
    case onReferenceFragmentUpdated

    static func < (
        lhs: ChromeMV3WebNavigationEventKind,
        rhs: ChromeMV3WebNavigationEventKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var listenerEvent: ChromeMV3ServiceWorkerSyntheticListenerEvent {
        switch self {
        case .onBeforeNavigate:
            return .webNavigationOnBeforeNavigate
        case .onCommitted:
            return .webNavigationOnCommitted
        case .onCompleted:
            return .webNavigationOnCompleted
        case .onDOMContentLoaded:
            return .webNavigationOnDOMContentLoaded
        case .onErrorOccurred:
            return .webNavigationOnErrorOccurred
        case .onHistoryStateUpdated:
            return .webNavigationOnHistoryStateUpdated
        case .onReferenceFragmentUpdated:
            return .webNavigationOnReferenceFragmentUpdated
        }
    }
}

struct ChromeMV3WebNavigationURLFilter:
    Codable,
    Equatable,
    Sendable
{
    var urlContains: String?
    var urlEquals: String?
    var hostContains: String?
    var hostEquals: String?
    var pathContains: String?
    var unsupportedKeys: [String]
    var ignoredKeys: [String]
    var diagnostics: [String]

    static func parse(
        _ value: ChromeMV3StorageValue?
    ) -> ChromeMV3WebNavigationURLFilter {
        guard let object = value?.objectValue else {
            return ChromeMV3WebNavigationURLFilter(
                urlContains: nil,
                urlEquals: nil,
                hostContains: nil,
                hostEquals: nil,
                pathContains: nil,
                unsupportedKeys: [],
                ignoredKeys: [],
                diagnostics: []
            )
        }
        let supported = Set([
            "urlContains",
            "urlEquals",
            "hostContains",
            "hostEquals",
            "pathContains",
        ])
        let ignored = object.keys.filter {
            $0 == "schemes" || $0 == "ports"
        }.sorted()
        let unsupported = object.keys.filter {
            supported.contains($0) == false && ignored.contains($0) == false
        }.sorted()
        return ChromeMV3WebNavigationURLFilter(
            urlContains: object["urlContains"]?.stringValue,
            urlEquals: object["urlEquals"]?.stringValue,
            hostContains: object["hostContains"]?.stringValue,
            hostEquals: object["hostEquals"]?.stringValue,
            pathContains: object["pathContains"]?.stringValue,
            unsupportedKeys: unsupported,
            ignoredKeys: ignored,
            diagnostics:
                uniqueSortedExtensionEventAPIs(
                    unsupported.map {
                        "Unsupported webNavigation UrlFilter key recorded: \($0)."
                    }
                    + ignored.map {
                        "webNavigation UrlFilter key \($0) is recorded but ignored by this synthetic MVP."
                    }
                )
        )
    }

    func matches(url: String) -> Bool {
        if let urlEquals, url != urlEquals {
            return false
        }
        if let urlContains, url.contains(urlContains) == false {
            return false
        }
        if let components = URLComponents(string: url) {
            if let hostEquals,
               components.host?.lowercased() != hostEquals.lowercased()
            {
                return false
            }
            if let hostContains,
               components.host?.lowercased()
                .contains(hostContains.lowercased()) != true
            {
                return false
            }
            if let pathContains,
               components.path.contains(pathContains) == false
            {
                return false
            }
        } else if hostContains != nil || hostEquals != nil
                    || pathContains != nil
        {
            return false
        }
        return true
    }

    var storageValue: ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [:]
        if let urlContains {
            object["urlContains"] = .string(urlContains)
        }
        if let urlEquals {
            object["urlEquals"] = .string(urlEquals)
        }
        if let hostContains {
            object["hostContains"] = .string(hostContains)
        }
        if let hostEquals {
            object["hostEquals"] = .string(hostEquals)
        }
        if let pathContains {
            object["pathContains"] = .string(pathContains)
        }
        object["unsupportedKeys"] =
            .array(unsupportedKeys.map(ChromeMV3StorageValue.string))
        object["ignoredKeys"] =
            .array(ignoredKeys.map(ChromeMV3StorageValue.string))
        return .object(object)
    }
}

struct ChromeMV3WebNavigationListenerFilter:
    Codable,
    Equatable,
    Sendable
{
    var urlFilters: [ChromeMV3WebNavigationURLFilter]
    var diagnostics: [String]

    static func parse(
        _ value: ChromeMV3StorageValue?
    ) -> ChromeMV3WebNavigationListenerFilter {
        guard let object = value?.objectValue,
              let urlValue = object["url"]
        else {
            return ChromeMV3WebNavigationListenerFilter(
                urlFilters: [],
                diagnostics: ["No webNavigation listener filter was supplied."]
            )
        }
        guard case .array(let values) = urlValue else {
            return ChromeMV3WebNavigationListenerFilter(
                urlFilters: [],
                diagnostics: [
                    "webNavigation listener filter url field must be an array.",
                ]
            )
        }
        let filters = values.map(ChromeMV3WebNavigationURLFilter.parse)
        return ChromeMV3WebNavigationListenerFilter(
            urlFilters: filters,
            diagnostics:
                uniqueSortedExtensionEventAPIs(
                    filters.flatMap(\.diagnostics)
                        + [
                            "webNavigation listener filter was normalized deterministically.",
                        ]
                )
        )
    }

    func matches(url: String) -> Bool {
        urlFilters.isEmpty || urlFilters.contains { $0.matches(url: url) }
    }

    var storageValue: ChromeMV3StorageValue {
        .object([
            "url": .array(urlFilters.map(\.storageValue)),
        ])
    }
}

struct ChromeMV3WebNavigationFrameRecord:
    Codable,
    Equatable,
    Sendable
{
    var tabID: Int
    var frameID: Int
    var parentFrameID: Int
    var documentID: String
    var parentDocumentID: String?
    var url: String
    var frameType: String
    var documentLifecycle: String
    var sequence: Int

    var storageValue: ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "tabId": .number(Double(tabID)),
            "frameId": .number(Double(frameID)),
            "parentFrameId": .number(Double(parentFrameID)),
            "documentId": .string(documentID),
            "url": .string(url),
            "frameType": .string(frameType),
            "documentLifecycle": .string(documentLifecycle),
        ]
        if let parentDocumentID {
            object["parentDocumentId"] = .string(parentDocumentID)
        }
        return .object(object)
    }
}

struct ChromeMV3WebNavigationSyntheticEvent:
    Codable,
    Equatable,
    Sendable
{
    var eventKind: ChromeMV3WebNavigationEventKind
    var tabID: Int
    var frameID: Int
    var parentFrameID: Int
    var documentID: String
    var parentDocumentID: String?
    var url: String
    var timeStamp: Double
    var transitionType: String?
    var transitionQualifiers: [String]
    var error: String?
    var frameType: String
    var documentLifecycle: String
    var sequence: Int

    static func committed(
        tabID: Int = 1,
        url: String = "https://example.com/login",
        sequence: Int = 1
    ) -> ChromeMV3WebNavigationSyntheticEvent {
        ChromeMV3WebNavigationSyntheticEvent(
            eventKind: .onCommitted,
            tabID: tabID,
            frameID: 0,
            parentFrameID: -1,
            documentID: "document-\(sequence)",
            parentDocumentID: nil,
            url: url,
            timeStamp: Double(sequence),
            transitionType: "link",
            transitionQualifiers: [],
            error: nil,
            frameType: "outermost_frame",
            documentLifecycle: "active",
            sequence: sequence
        )
    }

    func withEventKind(
        _ kind: ChromeMV3WebNavigationEventKind,
        sequence: Int
    ) -> ChromeMV3WebNavigationSyntheticEvent {
        var copy = self
        copy.eventKind = kind
        copy.sequence = sequence
        copy.timeStamp = Double(sequence)
        return copy
    }

    var frameRecord: ChromeMV3WebNavigationFrameRecord {
        ChromeMV3WebNavigationFrameRecord(
            tabID: tabID,
            frameID: frameID,
            parentFrameID: parentFrameID,
            documentID: documentID,
            parentDocumentID: parentDocumentID,
            url: url,
            frameType: frameType,
            documentLifecycle: documentLifecycle,
            sequence: sequence
        )
    }

    var storageValue: ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "tabId": .number(Double(tabID)),
            "frameId": .number(Double(frameID)),
            "parentFrameId": .number(Double(parentFrameID)),
            "documentId": .string(documentID),
            "url": .string(url),
            "timeStamp": .number(timeStamp),
            "frameType": .string(frameType),
            "documentLifecycle": .string(documentLifecycle),
        ]
        if let parentDocumentID {
            object["parentDocumentId"] = .string(parentDocumentID)
        }
        if let transitionType {
            object["transitionType"] = .string(transitionType)
            object["transitionQualifiers"] =
                .array(transitionQualifiers.map(ChromeMV3StorageValue.string))
        }
        if let error {
            object["error"] = .string(error)
        }
        return .object(object)
    }
}

struct ChromeMV3WebNavigationDispatchRecord:
    Codable,
    Equatable,
    Sendable
{
    var sequence: Int
    var eventKind: ChromeMV3WebNavigationEventKind
    var eventPayload: ChromeMV3StorageValue
    var matchedListenerCount: Int
    var filterMatched: Bool
    var serviceWorkerLifecycleWakeResult:
        ChromeMV3ServiceWorkerInternalWakeResult?
    var sharedLifecycleSessionID: String?
    var sharedLifecycleSessionUsed: Bool
    var dispatched: Bool
    var lastErrorMessage: String?
    var diagnostics: [String]
}

struct ChromeMV3WebNavigationOperationRecord:
    Codable,
    Equatable,
    Sendable
{
    var sequence: Int
    var methodName: String
    var succeeded: Bool
    var resultPayload: ChromeMV3StorageValue?
    var lastErrorMessage: String?
    var lastErrorCode: String?
    var diagnostics: [String]
}

struct ChromeMV3WebNavigationRuntimeSummary:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var frameCount: Int
    var frameKeys: [String]
    var operationRecordCount: Int
    var syntheticEventRecordCount: Int
    var listenerFilterCount: Int
    var webNavigationAvailableInInternalFixture: Bool
    var webNavigationAvailableInProduct: Bool
    var productBrowserNavigationEventsSubscribed: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

struct ChromeMV3ExtensionEventListenerRegistration:
    Codable,
    Equatable,
    Sendable
{
    var listenerID: String
    var namespace: String
    var eventName: String
    var registeredSequence: Int
    var webNavigationFilter: ChromeMV3WebNavigationListenerFilter?
    var diagnostics: [String]
}

struct ChromeMV3ExtensionEventListenerFilterSummary:
    Codable,
    Equatable,
    Sendable
{
    var totalListenerCount: Int
    var listenerCountsByEvent: [String: Int]
    var listenerIDs: [String]
    var webNavigationFilterCount: Int
    var webNavigationFilterDiagnostics: [String]
    var listenerRegistryScopedToSyntheticRuntime: Bool
    var productListenersRegistered: Bool
}

final class ChromeMV3ExtensionEventListenerRegistry {
    private var registrations:
        [String: [String: ChromeMV3ExtensionEventListenerRegistration]] = [:]
    private var nextSequence = 0

    @discardableResult
    func register(
        namespace: String,
        eventName: String,
        listenerID: String,
        webNavigationFilter: ChromeMV3WebNavigationListenerFilter? = nil
    ) -> ChromeMV3ExtensionEventListenerRegistration {
        nextSequence += 1
        let key = Self.key(namespace: namespace, eventName: eventName)
        let normalizedID = normalizedExtensionEventAPIs(
            listenerID,
            fallback:
                stableIDExtensionEventAPIs(
                    prefix: "extension-event-listener",
                    parts: [key, String(nextSequence)]
                )
        )
        let registration = ChromeMV3ExtensionEventListenerRegistration(
            listenerID: normalizedID,
            namespace: namespace,
            eventName: eventName,
            registeredSequence: nextSequence,
            webNavigationFilter: webNavigationFilter,
            diagnostics:
                uniqueSortedExtensionEventAPIs(
                    [
                        "Listener registration is synthetic runtime state.",
                        "No product listener or product WebView listener is installed.",
                    ]
                        + (webNavigationFilter?.diagnostics ?? [])
                )
        )
        registrations[key, default: [:]][normalizedID] = registration
        return registration
    }

    @discardableResult
    func remove(
        namespace: String,
        eventName: String,
        listenerID: String
    ) -> Bool {
        let key = Self.key(namespace: namespace, eventName: eventName)
        return registrations[key]?.removeValue(forKey: listenerID) != nil
    }

    func has(
        namespace: String,
        eventName: String,
        listenerID: String
    ) -> Bool {
        registrations[Self.key(namespace: namespace, eventName: eventName)]?[listenerID] != nil
    }

    func listeners(
        namespace: String,
        eventName: String
    ) -> [ChromeMV3ExtensionEventListenerRegistration] {
        let values = registrations[Self.key(namespace: namespace, eventName: eventName)]?.values
            .map { $0 } ?? []
        return values.sorted {
            if $0.registeredSequence != $1.registeredSequence {
                return $0.registeredSequence < $1.registeredSequence
            }
            return $0.listenerID < $1.listenerID
        }
    }

    func tearDown() {
        registrations.removeAll()
        nextSequence = 0
    }

    var summary: ChromeMV3ExtensionEventListenerFilterSummary {
        let all = registrations.values.flatMap(\.values).sorted {
            if $0.namespace != $1.namespace {
                return $0.namespace < $1.namespace
            }
            if $0.eventName != $1.eventName {
                return $0.eventName < $1.eventName
            }
            return $0.listenerID < $1.listenerID
        }
        let counts = Dictionary(
            uniqueKeysWithValues:
                Set(all.map { Self.key(namespace: $0.namespace, eventName: $0.eventName) })
                .sorted()
                .map { key in
                    (key, all.filter {
                        Self.key(namespace: $0.namespace, eventName: $0.eventName) == key
                    }.count)
                }
        )
        return ChromeMV3ExtensionEventListenerFilterSummary(
            totalListenerCount: all.count,
            listenerCountsByEvent: counts,
            listenerIDs: all.map(\.listenerID),
            webNavigationFilterCount:
                all.filter { $0.webNavigationFilter != nil }.count,
            webNavigationFilterDiagnostics:
                uniqueSortedExtensionEventAPIs(
                    all.flatMap { $0.webNavigationFilter?.diagnostics ?? [] }
                ),
            listenerRegistryScopedToSyntheticRuntime: true,
            productListenersRegistered: false
        )
    }

    private static func key(namespace: String, eventName: String) -> String {
        "\(namespace).\(eventName)"
    }
}

final class ChromeMV3ExtensionEventAPIsRuntimeStateOwner {
    let configuration: ChromeMV3ExtensionEventAPIsConfiguration
    let listenerRegistry = ChromeMV3ExtensionEventListenerRegistry()
    private var permissionBroker: ChromeMV3PermissionBroker
    private var contextMenuItems: [String: ChromeMV3ContextMenuItemRecord] = [:]
    private var alarms: [String: ChromeMV3AlarmRecord] = [:]
    private var webNavigationFrames:
        [String: ChromeMV3WebNavigationFrameRecord] = [:]
    private(set) var contextMenuOperationRecords:
        [ChromeMV3ContextMenusOperationRecord] = []
    private(set) var contextMenuClickDispatchRecords:
        [ChromeMV3ContextMenusClickDispatchRecord] = []
    private(set) var alarmOperationRecords:
        [ChromeMV3AlarmsOperationRecord] = []
    private(set) var alarmTriggerRecords: [ChromeMV3AlarmTriggerRecord] = []
    private(set) var webNavigationOperationRecords:
        [ChromeMV3WebNavigationOperationRecord] = []
    private(set) var webNavigationDispatchRecords:
        [ChromeMV3WebNavigationDispatchRecord] = []
    private var nextSequence = 0
    private var nextContextMenuAutoID = 1

    init(
        configuration: ChromeMV3ExtensionEventAPIsConfiguration,
        permissionBroker: ChromeMV3PermissionBroker? = nil
    ) {
        self.configuration = configuration
        self.permissionBroker =
            permissionBroker
            ?? ChromeMV3ExtensionEventAPIPermissionFixtures.allEventAPIs(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID
            )
    }

    var contextMenusSummary: ChromeMV3ContextMenusRuntimeSummary {
        ChromeMV3ContextMenusRuntimeSummary(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            itemCount: contextMenuItems.count,
            itemIDs: contextMenuItems.keys.sorted(),
            operationRecordCount: contextMenuOperationRecords.count,
            clickDispatchCount: contextMenuClickDispatchRecords.count,
            contextMenusAvailableInInternalFixture:
                configuration.contextMenusAvailableInInternalFixture,
            contextMenusAvailableInProduct: false,
            productContextMenuUIAvailable: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedExtensionEventAPIs(
                    contextMenuItems.values.flatMap(\.diagnostics)
                        + [
                            "contextMenus runtime state is deterministic and internal fixture scoped.",
                            "No product context menu UI is created.",
                        ]
                )
        )
    }

    var alarmsSummary: ChromeMV3AlarmsRuntimeSummary {
        ChromeMV3AlarmsRuntimeSummary(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            alarmCount: alarms.count,
            alarmNames: alarms.keys.sorted(),
            operationRecordCount: alarmOperationRecords.count,
            triggerRecordCount: alarmTriggerRecords.count,
            repeatingAlarmCount: alarms.values.filter(\.repeating).count,
            explicitTestControlledTriggersOnly: true,
            alarmsAvailableInInternalFixture:
                configuration.alarmsAvailableInInternalFixture,
            alarmsRealSchedulingAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics: [
                "Alarm records store scheduledTime and period values only.",
                "Synthetic alarm firing is only through explicit fixture trigger calls.",
                "Product alarm scheduling remains unavailable.",
            ]
        )
    }

    var webNavigationSummary: ChromeMV3WebNavigationRuntimeSummary {
        ChromeMV3WebNavigationRuntimeSummary(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            frameCount: webNavigationFrames.count,
            frameKeys: webNavigationFrames.keys.sorted(),
            operationRecordCount: webNavigationOperationRecords.count,
            syntheticEventRecordCount: webNavigationDispatchRecords.count,
            listenerFilterCount:
                listenerRegistry.summary.webNavigationFilterCount,
            webNavigationAvailableInInternalFixture:
                configuration.webNavigationAvailableInInternalFixture,
            webNavigationAvailableInProduct: false,
            productBrowserNavigationEventsSubscribed: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics: [
                "webNavigation frame/event state is synthetic fixture data only.",
                "No product browser navigation events are subscribed.",
                "getFrame/getAllFrames read only the synthetic frame model.",
            ]
        )
    }

    func item(id: String) -> ChromeMV3ContextMenuItemRecord? {
        contextMenuItems[id]
    }

    func alarm(name: String) -> ChromeMV3AlarmRecord? {
        alarms[name]
    }

    func createContextMenu(
        properties: ChromeMV3StorageValue?,
        invocationMode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3ContextMenusOperationRecord {
        guard permissionBroker.hasAPIPermission("contextMenus") else {
            return contextMenuFailure(
                methodName: "create",
                invocationMode: invocationMode,
                code: .permissionMissing,
                diagnostics: ["contextMenus permission is required."]
            )
        }
        guard let object = properties?.objectValue else {
            return contextMenuFailure(
                methodName: "create",
                invocationMode: invocationMode,
                code: .invalidArguments,
                diagnostics: ["contextMenus.create requires a createProperties object."]
            )
        }
        let normalizedID: String
        if let rawID = object["id"] {
            guard let id = menuItemID(rawID), id.isEmpty == false else {
                return contextMenuFailure(
                    methodName: "create",
                    invocationMode: invocationMode,
                    code: .invalidArguments,
                    diagnostics: ["contextMenus.create id must be a string or integer."]
                )
            }
            normalizedID = id
        } else {
            normalizedID = "context-menu-\(nextContextMenuAutoID)"
            nextContextMenuAutoID += 1
        }
        guard contextMenuItems[normalizedID] == nil else {
            return contextMenuFailure(
                methodName: "create",
                invocationMode: invocationMode,
                menuItemID: normalizedID,
                code: .duplicateMenuItemID,
                diagnostics: [
                    "contextMenus.create rejected duplicate menu item id \(normalizedID).",
                ]
            )
        }
        let type = itemType(object["type"]?.stringValue)
        let title = object["title"]?.stringValue
        if type != .separator, title?.isEmpty != false {
            return contextMenuFailure(
                methodName: "create",
                invocationMode: invocationMode,
                menuItemID: normalizedID,
                code: .invalidArguments,
                diagnostics: [
                    "contextMenus.create requires title unless type is separator.",
                ]
            )
        }
        let item = ChromeMV3ContextMenuItemRecord(
            id: normalizedID,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            title: title,
            type: type,
            contexts: contextList(object["contexts"]),
            parentID: object["parentId"].flatMap(menuItemID),
            checked: object["checked"]?.boolValue,
            enabled: object["enabled"]?.boolValue ?? true,
            visible: object["visible"]?.boolValue ?? true,
            documentUrlPatterns: stringArray(object["documentUrlPatterns"]),
            targetUrlPatterns: stringArray(object["targetUrlPatterns"]),
            createdSequence: nextOperationSequence(),
            updatedSequence: nil,
            diagnostics: [
                "Context menu item exists only in the internal synthetic model.",
                "No product menu item is created.",
            ]
        )
        contextMenuItems[normalizedID] = item
        let record = ChromeMV3ContextMenusOperationRecord(
            sequence: item.createdSequence,
            methodName: "create",
            succeeded: true,
            menuItemID: normalizedID,
            resultPayload: .string(normalizedID),
            lastErrorMessage: nil,
            lastErrorCode: nil,
            diagnostics: item.diagnostics
        )
        contextMenuOperationRecords.append(record)
        return record
    }

    func updateContextMenu(
        idValue: ChromeMV3StorageValue?,
        properties: ChromeMV3StorageValue?,
        invocationMode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3ContextMenusOperationRecord {
        guard permissionBroker.hasAPIPermission("contextMenus") else {
            return contextMenuFailure(
                methodName: "update",
                invocationMode: invocationMode,
                code: .permissionMissing,
                diagnostics: ["contextMenus permission is required."]
            )
        }
        guard let id = idValue.flatMap(menuItemID), id.isEmpty == false,
              let object = properties?.objectValue
        else {
            return contextMenuFailure(
                methodName: "update",
                invocationMode: invocationMode,
                code: .invalidArguments,
                diagnostics: [
                    "contextMenus.update requires id and updateProperties.",
                ]
            )
        }
        guard var item = contextMenuItems[id] else {
            return contextMenuFailure(
                methodName: "update",
                invocationMode: invocationMode,
                menuItemID: id,
                code: .menuItemMissing,
                diagnostics: [
                    "contextMenus.update could not find the synthetic item.",
                ]
            )
        }
        if let title = object["title"]?.stringValue {
            item.title = title
        }
        if let type = object["type"]?.stringValue {
            item.type = itemType(type)
        }
        if object.keys.contains("contexts") {
            item.contexts = contextList(object["contexts"])
        }
        if let parentID = object["parentId"] {
            item.parentID = menuItemID(parentID)
        }
        if let checked = object["checked"]?.boolValue {
            item.checked = checked
        }
        if let enabled = object["enabled"]?.boolValue {
            item.enabled = enabled
        }
        if let visible = object["visible"]?.boolValue {
            item.visible = visible
        }
        if object.keys.contains("documentUrlPatterns") {
            item.documentUrlPatterns =
                stringArray(object["documentUrlPatterns"])
        }
        if object.keys.contains("targetUrlPatterns") {
            item.targetUrlPatterns =
                stringArray(object["targetUrlPatterns"])
        }
        let sequence = nextOperationSequence()
        item.updatedSequence = sequence
        item.diagnostics =
            uniqueSortedExtensionEventAPIs(
                item.diagnostics
                    + ["Context menu item was updated in synthetic model state."]
            )
        contextMenuItems[id] = item
        let record = ChromeMV3ContextMenusOperationRecord(
            sequence: sequence,
            methodName: "update",
            succeeded: true,
            menuItemID: id,
            resultPayload: nil,
            lastErrorMessage: nil,
            lastErrorCode: nil,
            diagnostics: item.diagnostics
        )
        contextMenuOperationRecords.append(record)
        return record
    }

    func removeContextMenu(
        idValue: ChromeMV3StorageValue?,
        invocationMode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3ContextMenusOperationRecord {
        guard permissionBroker.hasAPIPermission("contextMenus") else {
            return contextMenuFailure(
                methodName: "remove",
                invocationMode: invocationMode,
                code: .permissionMissing,
                diagnostics: ["contextMenus permission is required."]
            )
        }
        guard let id = idValue.flatMap(menuItemID), id.isEmpty == false else {
            return contextMenuFailure(
                methodName: "remove",
                invocationMode: invocationMode,
                code: .invalidArguments,
                diagnostics: ["contextMenus.remove requires a menu item id."]
            )
        }
        guard contextMenuItems.removeValue(forKey: id) != nil else {
            return contextMenuFailure(
                methodName: "remove",
                invocationMode: invocationMode,
                menuItemID: id,
                code: .menuItemMissing,
                diagnostics: [
                    "contextMenus.remove could not find the synthetic item.",
                ]
            )
        }
        let record = ChromeMV3ContextMenusOperationRecord(
            sequence: nextOperationSequence(),
            methodName: "remove",
            succeeded: true,
            menuItemID: id,
            resultPayload: nil,
            lastErrorMessage: nil,
            lastErrorCode: nil,
            diagnostics: [
                "Context menu item was removed from synthetic model state.",
                "No product menu UI was touched.",
            ]
        )
        contextMenuOperationRecords.append(record)
        return record
    }

    func removeAllContextMenus(
        invocationMode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3ContextMenusOperationRecord {
        guard permissionBroker.hasAPIPermission("contextMenus") else {
            return contextMenuFailure(
                methodName: "removeAll",
                invocationMode: invocationMode,
                code: .permissionMissing,
                diagnostics: ["contextMenus permission is required."]
            )
        }
        contextMenuItems.removeAll()
        let record = ChromeMV3ContextMenusOperationRecord(
            sequence: nextOperationSequence(),
            methodName: "removeAll",
            succeeded: true,
            menuItemID: nil,
            resultPayload: nil,
            lastErrorMessage: nil,
            lastErrorCode: nil,
            diagnostics: [
                "All synthetic context menu items were removed.",
                "Product menu UI remains unavailable.",
            ]
        )
        contextMenuOperationRecords.append(record)
        return record
    }

    func triggerContextMenuClick(
        _ fixture: ChromeMV3ContextMenusSyntheticClickFixture,
        serviceWorkerLifecycleOwner:
            ChromeMV3ServiceWorkerInternalLifecycleRuntimeOwner?,
        lifecycleComponentID: String,
        sharedLifecycleSessionID: String?
    ) -> ChromeMV3ContextMenusClickDispatchRecord {
        let sequence = nextOperationSequence()
        let listeners = listenerRegistry.listeners(
            namespace: "contextMenus",
            eventName: "onClicked"
        )
        guard let item = contextMenuItems[fixture.menuItemID],
              item.enabled,
              item.visible,
              contextMatches(item: item, fixture: fixture),
              documentURLMatches(item: item, url: fixture.pageURL)
        else {
            let record = ChromeMV3ContextMenusClickDispatchRecord(
                sequence: sequence,
                menuItemID: fixture.menuItemID,
                fixture: fixture,
                clickInfoPayload: .object([:]),
                tabPayload: nil,
                matchedListenerCount: listeners.count,
                permissionRedacted: false,
                serviceWorkerLifecycleWakeResult: nil,
                sharedLifecycleSessionID: sharedLifecycleSessionID,
                sharedLifecycleSessionUsed: sharedLifecycleSessionID != nil,
                dispatched: false,
                lastErrorMessage:
                    ChromeMV3ExtensionEventAPIErrorCode.syntheticEventBlocked
                    .lastErrorMessage,
                diagnostics: [
                    "Synthetic context menu click did not match an enabled visible item.",
                ]
            )
            contextMenuClickDispatchRecords.append(record)
            return record
        }
        let hostDecision = permissionBroker.hostAccessDecision(
            url: fixture.pageURL,
            tabID: fixture.tabID
        )
        let redact = fixture.pageURL != nil && hostDecision.hasHostAccess == false
        let clickPayload = contextMenuClickPayload(
            item: item,
            fixture: fixture,
            redactURLs: redact
        )
        let tabPayload = tabPayload(fixture: fixture, redactURLs: redact)
        let payload: ChromeMV3StorageValue = .object([
            "info": clickPayload,
            "tab": tabPayload ?? .null,
        ])
        let lifecycleResult = serviceWorkerLifecycleOwner?.requestWake(
            reason: .contextMenusClicked,
            listenerEvent: .contextMenusOnClicked,
            payload: payload,
            payloadSummary: "contextMenus.onClicked",
            sourceContext: configuration.sourceContext.runtimeContext,
            sourceComponentID: lifecycleComponentID,
            sourceComponentKind: .contextMenusHarness
        )
        let dispatched = lifecycleResult?.dispatched == true
            && listeners.isEmpty == false
        let record = ChromeMV3ContextMenusClickDispatchRecord(
            sequence: sequence,
            menuItemID: item.id,
            fixture: fixture,
            clickInfoPayload: clickPayload,
            tabPayload: tabPayload,
            matchedListenerCount: listeners.count,
            permissionRedacted: redact,
            serviceWorkerLifecycleWakeResult: lifecycleResult,
            sharedLifecycleSessionID: lifecycleResult?.sessionID
                ?? sharedLifecycleSessionID,
            sharedLifecycleSessionUsed:
                (lifecycleResult?.sessionID ?? sharedLifecycleSessionID) != nil,
            dispatched: dispatched,
            lastErrorMessage:
                dispatched ? nil
                    : lifecycleResult?.lastErrorMessage
                    ?? ChromeMV3ExtensionEventAPIErrorCode.listenerMissing
                    .lastErrorMessage,
            diagnostics:
                uniqueSortedExtensionEventAPIs(
                    [
                        "Synthetic context menu click was evaluated against internal model state.",
                        "No product context menu UI was involved.",
                    ]
                        + hostDecision.diagnostics
                        + (lifecycleResult?.diagnostics ?? [])
                )
        )
        contextMenuClickDispatchRecords.append(record)
        return record
    }

    func createAlarm(
        arguments: [ChromeMV3StorageValue],
        invocationMode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3AlarmsOperationRecord {
        guard permissionBroker.hasAPIPermission("alarms") else {
            return alarmFailure(
                methodName: "create",
                invocationMode: invocationMode,
                code: .permissionMissing,
                diagnostics: ["alarms permission is required."]
            )
        }
        let parsed = parseAlarmCreateArguments(arguments)
        switch parsed {
        case .failure(let error):
            return alarmFailure(
                methodName: "create",
                invocationMode: invocationMode,
                code: .invalidArguments,
                diagnostics: [error.message]
            )
        case .success(let input):
            let replaced = alarms[input.name] != nil
            let sequence = nextOperationSequence()
            let alarm = ChromeMV3AlarmRecord(
                name: input.name,
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                scheduledTime: input.scheduledTime,
                delayInMinutes: input.delayInMinutes,
                periodInMinutes: input.periodInMinutes,
                createdSequence: sequence,
                replacedExistingAlarm: replaced,
                cleared: false,
                diagnostics:
                    uniqueSortedExtensionEventAPIs([
                        "Alarm timing is stored as deterministic values only.",
                        "No product scheduler is started.",
                        replaced
                            ? "Existing alarm with same name was replaced."
                            : "New synthetic alarm record was stored.",
                    ])
            )
            alarms[input.name] = alarm
            let record = ChromeMV3AlarmsOperationRecord(
                sequence: sequence,
                methodName: "create",
                succeeded: true,
                alarmName: input.name,
                resultPayload: nil,
                lastErrorMessage: nil,
                lastErrorCode: nil,
                diagnostics: alarm.diagnostics
            )
            alarmOperationRecords.append(record)
            return record
        }
    }

    func getAlarm(
        nameValue: ChromeMV3StorageValue?,
        invocationMode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3AlarmsOperationRecord {
        guard permissionBroker.hasAPIPermission("alarms") else {
            return alarmFailure(
                methodName: "get",
                invocationMode: invocationMode,
                code: .permissionMissing,
                diagnostics: ["alarms permission is required."]
            )
        }
        let name = nameValue?.stringValue ?? ""
        let payload = alarms[name]?.storageValue ?? .null
        let record = ChromeMV3AlarmsOperationRecord(
            sequence: nextOperationSequence(),
            methodName: "get",
            succeeded: true,
            alarmName: name,
            resultPayload: payload,
            lastErrorMessage: nil,
            lastErrorCode: nil,
            diagnostics: [
                "alarms.get read the synthetic alarm store.",
            ]
        )
        alarmOperationRecords.append(record)
        return record
    }

    func getAllAlarms(
        invocationMode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3AlarmsOperationRecord {
        guard permissionBroker.hasAPIPermission("alarms") else {
            return alarmFailure(
                methodName: "getAll",
                invocationMode: invocationMode,
                code: .permissionMissing,
                diagnostics: ["alarms permission is required."]
            )
        }
        let payload = ChromeMV3StorageValue.array(
            alarms.values.sorted { $0.name < $1.name }.map(\.storageValue)
        )
        let record = ChromeMV3AlarmsOperationRecord(
            sequence: nextOperationSequence(),
            methodName: "getAll",
            succeeded: true,
            alarmName: nil,
            resultPayload: payload,
            lastErrorMessage: nil,
            lastErrorCode: nil,
            diagnostics: [
                "alarms.getAll returned deterministic synthetic alarm records.",
            ]
        )
        alarmOperationRecords.append(record)
        return record
    }

    func clearAlarm(
        nameValue: ChromeMV3StorageValue?,
        invocationMode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3AlarmsOperationRecord {
        guard permissionBroker.hasAPIPermission("alarms") else {
            return alarmFailure(
                methodName: "clear",
                invocationMode: invocationMode,
                code: .permissionMissing,
                diagnostics: ["alarms permission is required."]
            )
        }
        let name = nameValue?.stringValue ?? ""
        let removed = alarms.removeValue(forKey: name) != nil
        let record = ChromeMV3AlarmsOperationRecord(
            sequence: nextOperationSequence(),
            methodName: "clear",
            succeeded: true,
            alarmName: name,
            resultPayload: .bool(removed),
            lastErrorMessage: nil,
            lastErrorCode: nil,
            diagnostics: [
                removed
                    ? "Synthetic alarm was cleared."
                    : "No matching synthetic alarm existed.",
            ]
        )
        alarmOperationRecords.append(record)
        return record
    }

    func clearAllAlarms(
        invocationMode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3AlarmsOperationRecord {
        guard permissionBroker.hasAPIPermission("alarms") else {
            return alarmFailure(
                methodName: "clearAll",
                invocationMode: invocationMode,
                code: .permissionMissing,
                diagnostics: ["alarms permission is required."]
            )
        }
        let removed = alarms.isEmpty == false
        alarms.removeAll()
        let record = ChromeMV3AlarmsOperationRecord(
            sequence: nextOperationSequence(),
            methodName: "clearAll",
            succeeded: true,
            alarmName: nil,
            resultPayload: .bool(removed),
            lastErrorMessage: nil,
            lastErrorCode: nil,
            diagnostics: [
                "All synthetic alarms were cleared.",
                "No product scheduler state exists.",
            ]
        )
        alarmOperationRecords.append(record)
        return record
    }

    func triggerAlarm(
        name: String,
        serviceWorkerLifecycleOwner:
            ChromeMV3ServiceWorkerInternalLifecycleRuntimeOwner?,
        lifecycleComponentID: String,
        sharedLifecycleSessionID: String?
    ) -> ChromeMV3AlarmTriggerRecord {
        let sequence = nextOperationSequence()
        let listeners = listenerRegistry.listeners(
            namespace: "alarms",
            eventName: "onAlarm"
        )
        guard let alarm = alarms[name] else {
            let record = ChromeMV3AlarmTriggerRecord(
                sequence: sequence,
                alarmName: name,
                alarmPayload: nil,
                matchedListenerCount: listeners.count,
                serviceWorkerLifecycleWakeResult: nil,
                sharedLifecycleSessionID: sharedLifecycleSessionID,
                sharedLifecycleSessionUsed: sharedLifecycleSessionID != nil,
                dispatched: false,
                repeatingAlarmValueStateRetained: false,
                lastErrorMessage:
                    ChromeMV3ExtensionEventAPIErrorCode.syntheticEventBlocked
                    .lastErrorMessage,
                diagnostics: [
                    "Explicit alarm trigger did not match a synthetic alarm record.",
                ]
            )
            alarmTriggerRecords.append(record)
            return record
        }
        let lifecycleResult = serviceWorkerLifecycleOwner?.requestWake(
            reason: .alarm,
            listenerEvent: .alarmsOnAlarm,
            payload: alarm.storageValue,
            payloadSummary: "alarms.onAlarm",
            sourceContext: configuration.sourceContext.runtimeContext,
            sourceComponentID: lifecycleComponentID,
            sourceComponentKind: .alarmsHarness
        )
        let dispatched = lifecycleResult?.dispatched == true
            && listeners.isEmpty == false
        let record = ChromeMV3AlarmTriggerRecord(
            sequence: sequence,
            alarmName: name,
            alarmPayload: alarm.storageValue,
            matchedListenerCount: listeners.count,
            serviceWorkerLifecycleWakeResult: lifecycleResult,
            sharedLifecycleSessionID: lifecycleResult?.sessionID
                ?? sharedLifecycleSessionID,
            sharedLifecycleSessionUsed:
                (lifecycleResult?.sessionID ?? sharedLifecycleSessionID) != nil,
            dispatched: dispatched,
            repeatingAlarmValueStateRetained: alarm.repeating,
            lastErrorMessage:
                dispatched ? nil
                    : lifecycleResult?.lastErrorMessage
                    ?? ChromeMV3ExtensionEventAPIErrorCode.listenerMissing
                    .lastErrorMessage,
            diagnostics:
                uniqueSortedExtensionEventAPIs(
                    alarm.diagnostics
                        + (lifecycleResult?.diagnostics ?? [])
                        + [
                            "Alarm fired only because an explicit synthetic trigger was invoked.",
                            "Repeating state is value-only; no recurring scheduler is present.",
                        ]
                )
        )
        alarmTriggerRecords.append(record)
        return record
    }

    func emitWebNavigationEvent(
        _ event: ChromeMV3WebNavigationSyntheticEvent,
        serviceWorkerLifecycleOwner:
            ChromeMV3ServiceWorkerInternalLifecycleRuntimeOwner?,
        lifecycleComponentID: String,
        sharedLifecycleSessionID: String?
    ) -> ChromeMV3WebNavigationDispatchRecord {
        let sequence = nextOperationSequence()
        let listeners = listenerRegistry.listeners(
            namespace: "webNavigation",
            eventName: event.eventKind.rawValue
        )
        let matching = listeners.filter {
            $0.webNavigationFilter?.matches(url: event.url) ?? true
        }
        webNavigationFrames[frameKey(tabID: event.tabID, frameID: event.frameID)] =
            event.frameRecord
        guard permissionBroker.hasAPIPermission("webNavigation"),
              matching.isEmpty == false
        else {
            let record = ChromeMV3WebNavigationDispatchRecord(
                sequence: sequence,
                eventKind: event.eventKind,
                eventPayload: event.storageValue,
                matchedListenerCount: matching.count,
                filterMatched: matching.isEmpty == false,
                serviceWorkerLifecycleWakeResult: nil,
                sharedLifecycleSessionID: sharedLifecycleSessionID,
                sharedLifecycleSessionUsed: sharedLifecycleSessionID != nil,
                dispatched: false,
                lastErrorMessage:
                    permissionBroker.hasAPIPermission("webNavigation")
                    ? ChromeMV3ExtensionEventAPIErrorCode.listenerMissing
                        .lastErrorMessage
                    : ChromeMV3ExtensionEventAPIErrorCode.permissionMissing
                        .lastErrorMessage,
                diagnostics: [
                    "Synthetic webNavigation event did not have a matching registered listener or permission.",
                    "No product navigation event was observed.",
                ]
            )
            webNavigationDispatchRecords.append(record)
            return record
        }
        let lifecycleResult = serviceWorkerLifecycleOwner?.requestWake(
            reason: .webNavigationEvent,
            listenerEvent: event.eventKind.listenerEvent,
            payload: event.storageValue,
            payloadSummary: "webNavigation.\(event.eventKind.rawValue)",
            sourceContext: configuration.sourceContext.runtimeContext,
            sourceComponentID: lifecycleComponentID,
            sourceComponentKind: .webNavigationHarness
        )
        let dispatched = lifecycleResult?.dispatched == true
        let record = ChromeMV3WebNavigationDispatchRecord(
            sequence: sequence,
            eventKind: event.eventKind,
            eventPayload: event.storageValue,
            matchedListenerCount: matching.count,
            filterMatched: true,
            serviceWorkerLifecycleWakeResult: lifecycleResult,
            sharedLifecycleSessionID: lifecycleResult?.sessionID
                ?? sharedLifecycleSessionID,
            sharedLifecycleSessionUsed:
                (lifecycleResult?.sessionID ?? sharedLifecycleSessionID) != nil,
            dispatched: dispatched,
            lastErrorMessage:
                dispatched ? nil : lifecycleResult?.lastErrorMessage,
            diagnostics:
                uniqueSortedExtensionEventAPIs(
                    matching.flatMap(\.diagnostics)
                        + (lifecycleResult?.diagnostics ?? [])
                        + [
                            "Synthetic webNavigation event was dispatched through the internal lifecycle owner.",
                            "Product browser navigation subscription remains unavailable.",
                        ]
                )
        )
        webNavigationDispatchRecords.append(record)
        return record
    }

    func getFrame(
        details: ChromeMV3StorageValue?,
        invocationMode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3WebNavigationOperationRecord {
        guard permissionBroker.hasAPIPermission("webNavigation") else {
            return webNavigationFailure(
                methodName: "getFrame",
                invocationMode: invocationMode,
                code: .permissionMissing,
                diagnostics: ["webNavigation permission is required."]
            )
        }
        guard let object = details?.objectValue,
              let tabID = object["tabId"]?.intValue,
              let frameID = object["frameId"]?.intValue
        else {
            return webNavigationFailure(
                methodName: "getFrame",
                invocationMode: invocationMode,
                code: .invalidArguments,
                diagnostics: [
                    "webNavigation.getFrame requires tabId and frameId.",
                ]
            )
        }
        let record = webNavigationFrames[frameKey(tabID: tabID, frameID: frameID)]
        let operation = ChromeMV3WebNavigationOperationRecord(
            sequence: nextOperationSequence(),
            methodName: "getFrame",
            succeeded: true,
            resultPayload: record?.storageValue ?? .null,
            lastErrorMessage: nil,
            lastErrorCode: nil,
            diagnostics: [
                "webNavigation.getFrame read the synthetic navigation frame store.",
            ]
        )
        webNavigationOperationRecords.append(operation)
        return operation
    }

    func getAllFrames(
        details: ChromeMV3StorageValue?,
        invocationMode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3WebNavigationOperationRecord {
        guard permissionBroker.hasAPIPermission("webNavigation") else {
            return webNavigationFailure(
                methodName: "getAllFrames",
                invocationMode: invocationMode,
                code: .permissionMissing,
                diagnostics: ["webNavigation permission is required."]
            )
        }
        guard let object = details?.objectValue,
              let tabID = object["tabId"]?.intValue
        else {
            return webNavigationFailure(
                methodName: "getAllFrames",
                invocationMode: invocationMode,
                code: .invalidArguments,
                diagnostics: ["webNavigation.getAllFrames requires tabId."]
            )
        }
        let frames = webNavigationFrames.values
            .filter { $0.tabID == tabID }
            .sorted { $0.frameID < $1.frameID }
        let operation = ChromeMV3WebNavigationOperationRecord(
            sequence: nextOperationSequence(),
            methodName: "getAllFrames",
            succeeded: true,
            resultPayload: .array(frames.map(\.storageValue)),
            lastErrorMessage: nil,
            lastErrorCode: nil,
            diagnostics: [
                "webNavigation.getAllFrames read synthetic frame records only.",
            ]
        )
        webNavigationOperationRecords.append(operation)
        return operation
    }

    func tearDown() {
        contextMenuItems.removeAll()
        alarms.removeAll()
        webNavigationFrames.removeAll()
        contextMenuOperationRecords.removeAll()
        contextMenuClickDispatchRecords.removeAll()
        alarmOperationRecords.removeAll()
        alarmTriggerRecords.removeAll()
        webNavigationOperationRecords.removeAll()
        webNavigationDispatchRecords.removeAll()
        listenerRegistry.tearDown()
        nextSequence = 0
        nextContextMenuAutoID = 1
    }

    private func contextMenuFailure(
        methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode,
        menuItemID: String? = nil,
        code: ChromeMV3ExtensionEventAPIErrorCode,
        diagnostics: [String]
    ) -> ChromeMV3ContextMenusOperationRecord {
        let record = ChromeMV3ContextMenusOperationRecord(
            sequence: nextOperationSequence(),
            methodName: methodName,
            succeeded: false,
            menuItemID: menuItemID,
            resultPayload: nil,
            lastErrorMessage: code.lastErrorMessage,
            lastErrorCode: code.rawValue,
            diagnostics: diagnostics
        )
        contextMenuOperationRecords.append(record)
        _ = invocationMode
        return record
    }

    private func alarmFailure(
        methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode,
        alarmName: String? = nil,
        code: ChromeMV3ExtensionEventAPIErrorCode,
        diagnostics: [String]
    ) -> ChromeMV3AlarmsOperationRecord {
        let record = ChromeMV3AlarmsOperationRecord(
            sequence: nextOperationSequence(),
            methodName: methodName,
            succeeded: false,
            alarmName: alarmName,
            resultPayload: nil,
            lastErrorMessage: code.lastErrorMessage,
            lastErrorCode: code.rawValue,
            diagnostics: diagnostics
        )
        alarmOperationRecords.append(record)
        _ = invocationMode
        return record
    }

    private func webNavigationFailure(
        methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode,
        code: ChromeMV3ExtensionEventAPIErrorCode,
        diagnostics: [String]
    ) -> ChromeMV3WebNavigationOperationRecord {
        let record = ChromeMV3WebNavigationOperationRecord(
            sequence: nextOperationSequence(),
            methodName: methodName,
            succeeded: false,
            resultPayload: nil,
            lastErrorMessage: code.lastErrorMessage,
            lastErrorCode: code.rawValue,
            diagnostics: diagnostics
        )
        webNavigationOperationRecords.append(record)
        _ = invocationMode
        return record
    }

    private func nextOperationSequence() -> Int {
        nextSequence += 1
        return nextSequence
    }

    private func menuItemID(_ value: ChromeMV3StorageValue) -> String? {
        if let string = value.stringValue {
            return string
        }
        if let int = value.intValue {
            return String(int)
        }
        return nil
    }

    private func itemType(_ raw: String?) -> ChromeMV3ContextMenuItemType {
        raw.flatMap(ChromeMV3ContextMenuItemType.init(rawValue:)) ?? .normal
    }

    private func contextList(
        _ value: ChromeMV3StorageValue?
    ) -> [ChromeMV3ContextMenuContext] {
        guard case .array(let entries) = value else { return [.page] }
        let values = entries.compactMap {
            $0.stringValue.flatMap(ChromeMV3ContextMenuContext.init(rawValue:))
        }
        return values.isEmpty ? [.page] : Array(Set(values)).sorted()
    }

    private func stringArray(_ value: ChromeMV3StorageValue?) -> [String] {
        guard case .array(let entries) = value else { return [] }
        return Array(Set(entries.compactMap(\.stringValue))).sorted()
    }

    private func contextMatches(
        item: ChromeMV3ContextMenuItemRecord,
        fixture: ChromeMV3ContextMenusSyntheticClickFixture
    ) -> Bool {
        item.contexts.contains(.all) || item.contexts.contains(fixture.context)
    }

    private func documentURLMatches(
        item: ChromeMV3ContextMenuItemRecord,
        url: String?
    ) -> Bool {
        item.documentUrlPatterns.isEmpty
            || item.documentUrlPatterns.contains {
                ChromeMV3HostMatchPattern($0).matches(url: url)
            }
    }

    private func contextMenuClickPayload(
        item: ChromeMV3ContextMenuItemRecord,
        fixture: ChromeMV3ContextMenusSyntheticClickFixture,
        redactURLs: Bool
    ) -> ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "menuItemId": .string(item.id),
            "editable": .bool(fixture.editable),
        ]
        if let parentID = item.parentID {
            object["parentMenuItemId"] = .string(parentID)
        }
        if let frameID = fixture.frameID {
            object["frameId"] = .number(Double(frameID))
        }
        if let selectionText = fixture.selectionText {
            object["selectionText"] = .string(selectionText)
        }
        if let checked = fixture.checked ?? item.checked {
            object["checked"] = .bool(checked)
        }
        if let wasChecked = fixture.wasChecked {
            object["wasChecked"] = .bool(wasChecked)
        }
        guard redactURLs == false else {
            object["urlsRedactedBySyntheticPermissionModel"] = .bool(true)
            return .object(object)
        }
        if let pageURL = fixture.pageURL {
            object["pageUrl"] = .string(pageURL)
        }
        if let frameURL = fixture.frameURL {
            object["frameUrl"] = .string(frameURL)
        }
        if let linkURL = fixture.linkURL {
            object["linkUrl"] = .string(linkURL)
        }
        if let srcURL = fixture.srcURL {
            object["srcUrl"] = .string(srcURL)
        }
        return .object(object)
    }

    private func tabPayload(
        fixture: ChromeMV3ContextMenusSyntheticClickFixture,
        redactURLs: Bool
    ) -> ChromeMV3StorageValue? {
        guard let tabID = fixture.tabID else { return nil }
        var object: [String: ChromeMV3StorageValue] = [
            "id": .number(Double(tabID)),
            "active": .bool(true),
            "status": .string("complete"),
        ]
        if redactURLs == false, let pageURL = fixture.pageURL {
            object["url"] = .string(pageURL)
        }
        return .object(object)
    }

    private func parseAlarmCreateArguments(
        _ arguments: [ChromeMV3StorageValue]
    ) -> Result<
        (name: String, scheduledTime: Double, delayInMinutes: Double?,
         periodInMinutes: Double?),
        ChromeMV3ExtensionEventAPIArgumentError
    > {
        let name: String
        let info: [String: ChromeMV3StorageValue]?
        if arguments.count == 1 {
            name = ""
            info = arguments[0].objectValue
        } else if arguments.count == 2 {
            guard let parsedName = arguments[0].stringValue else {
                return .failure(
                    ChromeMV3ExtensionEventAPIArgumentError(
                        message: "alarms.create name must be a string."
                    )
                )
            }
            name = parsedName
            info = arguments[1].objectValue
        } else {
            return .failure(
                ChromeMV3ExtensionEventAPIArgumentError(
                    message: "alarms.create accepts alarmInfo or name and alarmInfo."
                )
            )
        }
        guard let info else {
            return .failure(
                ChromeMV3ExtensionEventAPIArgumentError(
                    message: "alarms.create alarmInfo must be an object."
                )
            )
        }
        let when = info["when"]?.numberValue
        let delay = info["delayInMinutes"]?.numberValue
        let period = info["periodInMinutes"]?.numberValue
        guard [when, delay, period].contains(where: { $0 != nil }) else {
            return .failure(
                ChromeMV3ExtensionEventAPIArgumentError(
                    message: "alarms.create requires when, delayInMinutes, or periodInMinutes."
                )
            )
        }
        if [when, delay, period].compactMap({ $0 }).contains(where: { $0 < 0 }) {
            return .failure(
                ChromeMV3ExtensionEventAPIArgumentError(
                    message: "alarms.create timing values must be non-negative."
                )
            )
        }
        let scheduled = when ?? ((delay ?? period ?? 0) * 60_000)
        return .success((name, scheduled, delay, period))
    }

    private func frameKey(tabID: Int, frameID: Int) -> String {
        "\(tabID):\(frameID)"
    }
}

enum ChromeMV3ExtensionEventAPIPermissionFixtures {
    static func allEventAPIs(
        extensionID: String,
        profileID: String
    ) -> ChromeMV3PermissionBroker {
        ChromeMV3PermissionBroker(
            state: ChromeMV3PermissionBrokerState(
                extensionID: extensionID,
                profileID: profileID,
                requiredPermissions: [
                    "alarms",
                    "contextMenus",
                    "webNavigation",
                ],
                hostPermissions: ["https://example.com/*"],
                diagnostics: [
                    "Synthetic event API fixture declares only the APIs under test.",
                ]
            )
        )
    }

    static func missingEventAPIs(
        extensionID: String,
        profileID: String
    ) -> ChromeMV3PermissionBroker {
        ChromeMV3PermissionBroker(
            state: ChromeMV3PermissionBrokerState(
                extensionID: extensionID,
                profileID: profileID,
                requiredPermissions: [],
                diagnostics: [
                    "Negative fixture intentionally omits event API permissions.",
                ]
            )
        )
    }
}

struct ChromeMV3ExtensionEventAPIsJSShimCoverage:
    Codable,
    Equatable,
    Sendable
{
    var exposedChromeNamespaces: [String]
    var runtimeMembers: [String]
    var contextMenusMethods: [String]
    var contextMenusEvents: [String]
    var alarmsMethods: [String]
    var alarmsEvents: [String]
    var webNavigationEvents: [String]
    var webNavigationMethods: [String]
    var callbackModeSupported: Bool
    var promiseModeSupported: Bool
    var lastErrorScopedToCallbackTurn: Bool
    var unsupportedChromeNamespaces: [String]
}

enum ChromeMV3ExtensionEventAPIsJSShimSource {
    static let bridgeMessageHandlerName = "sumiChromeMV3ExtensionEventAPIs"

    static var coverage: ChromeMV3ExtensionEventAPIsJSShimCoverage {
        ChromeMV3ExtensionEventAPIsJSShimCoverage(
            exposedChromeNamespaces: [
                "alarms",
                "contextMenus",
                "runtime",
                "webNavigation",
            ],
            runtimeMembers: ["lastError"],
            contextMenusMethods: [
                "create",
                "remove",
                "removeAll",
                "update",
            ],
            contextMenusEvents: ["onClicked"],
            alarmsMethods: [
                "clear",
                "clearAll",
                "create",
                "get",
                "getAll",
            ],
            alarmsEvents: ["onAlarm"],
            webNavigationEvents:
                ChromeMV3WebNavigationEventKind.allCases.map(\.rawValue),
            webNavigationMethods: ["getAllFrames", "getFrame"],
            callbackModeSupported: true,
            promiseModeSupported: true,
            lastErrorScopedToCallbackTurn: true,
            unsupportedChromeNamespaces: [
                "bookmarks",
                "downloads",
                "history",
                "nativeMessaging",
                "scripting",
                "tabs",
            ]
        )
    }

    static func source(
        configuration: ChromeMV3ExtensionEventAPIsConfiguration
    ) -> String {
        let configJSON = jsonString([
            "extensionID": configuration.extensionID,
            "profileID": configuration.profileID,
            "surfaceID": configuration.surfaceID,
            "sourceContext": configuration.sourceContext.rawValue,
            "bridgeMessageHandlerName": bridgeMessageHandlerName,
        ])
        let webNavigationEventsJSON =
            jsonArray(ChromeMV3WebNavigationEventKind.allCases.map(\.rawValue))
        return """
        (() => {
          "use strict";
          const config = \(configJSON);
          const webNavigationEventNames = \(webNavigationEventsJSON);
          const bridgeName = config.bridgeMessageHandlerName;
          const chromeObject = {};
          const runtime = {};
          const contextMenus = {};
          const alarms = {};
          const webNavigation = {};
          let lastErrorValue;
          let nextBridgeCallNumber = 0;
          let nextListenerNumber = 0;
          let nextContextMenuID = 0;

          function bridgeUnavailableResponse(namespace, methodName) {
            return {
              bridgeCallID: "extension-event-apis-js-unavailable",
              namespace,
              methodName,
              succeeded: false,
              resultPayload: null,
              lastErrorMessage: "extension event APIs JS bridge handler is unavailable.",
              lastErrorCode: "jsBridgeUnavailable",
              callbackWouldSetLastError: false,
              promiseWouldReject: false,
              diagnostics: ["extension event APIs JS bridge handler is unavailable."]
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
            return handler.postMessage(Object.assign({
              namespace,
              methodName,
              invocationMode,
              extensionID: config.extensionID,
              profileID: config.profileID,
              sourceContext: config.sourceContext,
              surfaceID: config.surfaceID,
              bridgeCallID: [
                "extension-event-apis-js",
                config.surfaceID,
                namespace,
                methodName,
                String(nextBridgeCallNumber)
              ].join("-"),
              arguments: args || []
            }, extra || {}));
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
              new Error(response.lastErrorMessage || "extension event APIs JS bridge call failed.")
            );
          }

          function callbackOrPromise(namespace, methodName, args, callback, valueMapper) {
            const mode = callback ? "callback" : "promise";
            let bridgeArgs;
            try {
              bridgeArgs = (args || []).map(toJSONCompatible);
            } catch (error) {
              const message = "Invalid Chrome MV3 event APIs JavaScript arguments.";
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
                  invokeCallback(
                    callback,
                    null,
                    valueMapper ? valueMapper(response, true) : []
                  );
                } else {
                  invokeCallback(callback, response.lastErrorMessage, []);
                }
              });
              return undefined;
            }
            return promise.then((response) => {
              if (response.succeeded) {
                return valueMapper ? valueMapper(response, false)[0] : undefined;
              }
              return rejectFromResponse(response);
            });
          }

          function makeEvent(namespace, eventName) {
            const entries = [];
            const ids = new Map();
            function method(suffix) {
              return eventName + "." + suffix;
            }
            return Object.freeze({
              addListener(listener, filters) {
                if (typeof listener !== "function" || ids.has(listener)) {
                  return;
                }
                nextListenerNumber += 1;
                const listenerID = [
                  config.surfaceID,
                  namespace,
                  eventName,
                  String(nextListenerNumber)
                ].join(":");
                ids.set(listener, listenerID);
                entries.push({ listener, listenerID, filters: filters || null });
                bridgePost(
                  namespace,
                  method("addListener"),
                  "fireAndForget",
                  filters ? [filters] : [],
                  { listenerID }
                ).catch(() => undefined);
              },
              removeListener(listener) {
                const listenerID = ids.get(listener);
                if (!listenerID) {
                  return;
                }
                ids.delete(listener);
                const index = entries.findIndex((entry) => entry.listener === listener);
                if (index >= 0) {
                  entries.splice(index, 1);
                }
                bridgePost(
                  namespace,
                  method("removeListener"),
                  "fireAndForget",
                  [],
                  { listenerID }
                ).catch(() => undefined);
              },
              hasListener(listener) {
                return ids.has(listener);
              },
              hasListeners() {
                return entries.length > 0;
              },
              __sumiDispatchSynthetic() {
                const args = Array.prototype.slice.call(arguments);
                entries.slice().forEach((entry) => {
                  entry.listener.apply(undefined, args);
                });
              },
              __sumiSnapshot() {
                return entries.slice();
              }
            });
          }

          const contextMenusOnClicked =
            makeEvent("contextMenus", "onClicked");
          const alarmsOnAlarm = makeEvent("alarms", "onAlarm");

          Object.defineProperty(runtime, "lastError", {
            get() { return lastErrorValue; },
            enumerable: true
          });

          Object.defineProperty(contextMenus, "create", {
            value(createProperties, callback) {
              const properties = Object.assign({}, createProperties || {});
              if (properties.id === undefined) {
                nextContextMenuID += 1;
                properties.id = "js-context-menu-" + String(nextContextMenuID);
              }
              const cb = typeof callback === "function" ? callback : null;
              bridgePost(
                "contextMenus",
                "create",
                cb ? "callback" : "fireAndForget",
                [properties]
              ).then((response) => {
                if (cb) {
                  invokeCallback(
                    cb,
                    response.succeeded ? null : response.lastErrorMessage,
                    []
                  );
                }
              });
              return properties.id;
            },
            enumerable: true
          });
          Object.defineProperty(contextMenus, "update", {
            value(id, updateProperties, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise(
                "contextMenus",
                "update",
                [id, updateProperties || {}],
                cb
              );
            },
            enumerable: true
          });
          Object.defineProperty(contextMenus, "remove", {
            value(id, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("contextMenus", "remove", [id], cb);
            },
            enumerable: true
          });
          Object.defineProperty(contextMenus, "removeAll", {
            value(callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("contextMenus", "removeAll", [], cb);
            },
            enumerable: true
          });
          Object.defineProperty(contextMenus, "onClicked", {
            value: contextMenusOnClicked,
            enumerable: true
          });

          function alarmArgs(first, second, third) {
            if (typeof first === "string") {
              return {
                args: [first, second || {}],
                callback: typeof third === "function" ? third : null
              };
            }
            return {
              args: [first || {}],
              callback: typeof second === "function" ? second : null
            };
          }

          Object.defineProperty(alarms, "create", {
            value(first, second, third) {
              const parsed = alarmArgs(first, second, third);
              return callbackOrPromise("alarms", "create", parsed.args, parsed.callback);
            },
            enumerable: true
          });
          Object.defineProperty(alarms, "get", {
            value(name, callback) {
              const cb = typeof callback === "function" ? callback : null;
              const args = typeof name === "function" ? [] : [name || ""];
              const resolvedCallback = typeof name === "function" ? name : cb;
              return callbackOrPromise(
                "alarms",
                "get",
                args,
                resolvedCallback,
                (response) => [response.resultPayload || undefined]
              );
            },
            enumerable: true
          });
          Object.defineProperty(alarms, "getAll", {
            value(callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise(
                "alarms",
                "getAll",
                [],
                cb,
                (response) => [response.resultPayload || []]
              );
            },
            enumerable: true
          });
          Object.defineProperty(alarms, "clear", {
            value(name, callback) {
              const cb = typeof callback === "function" ? callback : null;
              const args = typeof name === "function" ? [] : [name || ""];
              const resolvedCallback = typeof name === "function" ? name : cb;
              return callbackOrPromise(
                "alarms",
                "clear",
                args,
                resolvedCallback,
                (response) => [Boolean(response.resultPayload)]
              );
            },
            enumerable: true
          });
          Object.defineProperty(alarms, "clearAll", {
            value(callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise(
                "alarms",
                "clearAll",
                [],
                cb,
                (response) => [Boolean(response.resultPayload)]
              );
            },
            enumerable: true
          });
          Object.defineProperty(alarms, "onAlarm", {
            value: alarmsOnAlarm,
            enumerable: true
          });

          webNavigationEventNames.forEach((eventName) => {
            Object.defineProperty(webNavigation, eventName, {
              value: makeEvent("webNavigation", eventName),
              enumerable: true
            });
          });
          Object.defineProperty(webNavigation, "getFrame", {
            value(details, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise(
                "webNavigation",
                "getFrame",
                [details || {}],
                cb,
                (response) => [response.resultPayload || null]
              );
            },
            enumerable: true
          });
          Object.defineProperty(webNavigation, "getAllFrames", {
            value(details, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise(
                "webNavigation",
                "getAllFrames",
                [details || {}],
                cb,
                (response) => [response.resultPayload || []]
              );
            },
            enumerable: true
          });

          Object.defineProperty(chromeObject, "runtime", {
            value: Object.freeze(runtime),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "contextMenus", {
            value: Object.freeze(contextMenus),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "alarms", {
            value: Object.freeze(alarms),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "webNavigation", {
            value: Object.freeze(webNavigation),
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

    private static func jsonArray(_ values: [String]) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: values,
            options: [.sortedKeys]
        )) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

struct ChromeMV3ExtensionEventAPIsBridgeHostResponse:
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
    var contextMenusSummary: ChromeMV3ContextMenusRuntimeSummary
    var alarmsSummary: ChromeMV3AlarmsRuntimeSummary
    var webNavigationSummary: ChromeMV3WebNavigationRuntimeSummary
    var listenerFilterSummary: ChromeMV3ExtensionEventListenerFilterSummary
    var serviceWorkerLifecycleWakeResult:
        ChromeMV3ServiceWorkerInternalWakeResult?
    var contextMenusAvailableInInternalFixture: Bool
    var contextMenusAvailableInProduct: Bool
    var alarmsAvailableInInternalFixture: Bool
    var alarmsRealSchedulingAvailableInProduct: Bool
    var webNavigationAvailableInInternalFixture: Bool
    var webNavigationAvailableInProduct: Bool
    var sharedLifecycleSessionUsed: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    var foundationObject: [String: Any] {
        [
            "bridgeCallID": bridgeCallID,
            "namespace": namespace,
            "methodName": methodName,
            "succeeded": succeeded,
            "resultPayload":
                resultPayload?.extensionEventAPIsFoundationObject
                ?? NSNull(),
            "lastErrorMessage": lastErrorMessage ?? NSNull(),
            "lastErrorCode": lastErrorCode ?? NSNull(),
            "callbackWouldSetLastError": callbackWouldSetLastError,
            "promiseWouldReject": promiseWouldReject,
            "contextMenusAvailableInInternalFixture":
                contextMenusAvailableInInternalFixture,
            "contextMenusAvailableInProduct":
                contextMenusAvailableInProduct,
            "alarmsAvailableInInternalFixture":
                alarmsAvailableInInternalFixture,
            "alarmsRealSchedulingAvailableInProduct":
                alarmsRealSchedulingAvailableInProduct,
            "webNavigationAvailableInInternalFixture":
                webNavigationAvailableInInternalFixture,
            "webNavigationAvailableInProduct":
                webNavigationAvailableInProduct,
            "sharedLifecycleSessionUsed": sharedLifecycleSessionUsed,
            "normalTabRuntimeBridgeAvailable":
                normalTabRuntimeBridgeAvailable,
            "runtimeLoadable": runtimeLoadable,
            "diagnostics": diagnostics,
        ]
    }
}

final class ChromeMV3ExtensionEventAPIsJSBridgeHandler {
    let configuration: ChromeMV3ExtensionEventAPIsConfiguration
    let runtimeStateOwner: ChromeMV3ExtensionEventAPIsRuntimeStateOwner
    private let serviceWorkerLifecycleOwner:
        ChromeMV3ServiceWorkerInternalLifecycleRuntimeOwner?
    private let sharedLifecycleSession:
        ChromeMV3ServiceWorkerSharedLifecycleSession?
    private let contextMenusComponentID: String
    private let alarmsComponentID: String
    private let webNavigationComponentID: String
    private(set) var handledRequestCount = 0
    private(set) var rejectedRequestCount = 0

    init(
        configuration: ChromeMV3ExtensionEventAPIsConfiguration,
        permissionBroker: ChromeMV3PermissionBroker? = nil,
        runtimeStateOwner:
            ChromeMV3ExtensionEventAPIsRuntimeStateOwner? = nil,
        sharedLifecycleSession:
            ChromeMV3ServiceWorkerSharedLifecycleSession? = nil
    ) {
        self.configuration = configuration
        self.runtimeStateOwner =
            runtimeStateOwner
            ?? ChromeMV3ExtensionEventAPIsRuntimeStateOwner(
                configuration: configuration,
                permissionBroker: permissionBroker
            )
        self.sharedLifecycleSession = sharedLifecycleSession
        self.contextMenusComponentID =
            "context-menus-harness:\(configuration.surfaceID)"
        self.alarmsComponentID =
            "alarms-harness:\(configuration.surfaceID)"
        self.webNavigationComponentID =
            "web-navigation-harness:\(configuration.surfaceID)"
        if configuration.serviceWorkerLifecycleAvailableInInternalFixture {
            let owner: ChromeMV3ServiceWorkerInternalLifecycleRuntimeOwner
            if let sharedLifecycleSession {
                _ = sharedLifecycleSession.attachComponent(
                    kind: .contextMenusHarness,
                    componentID: contextMenusComponentID,
                    eventSurfaces: [.contextMenusOnClicked]
                )
                _ = sharedLifecycleSession.attachComponent(
                    kind: .alarmsHarness,
                    componentID: alarmsComponentID,
                    eventSurfaces: [.alarmsOnAlarm]
                )
                _ = sharedLifecycleSession.attachComponent(
                    kind: .webNavigationHarness,
                    componentID: webNavigationComponentID,
                    eventSurfaces:
                        ChromeMV3WebNavigationEventKind.allCases.map {
                            $0.listenerEvent
                        }
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
                            .explicitInternalEventAPIsBridgeAllowed
                    )
                )
            }
            self.serviceWorkerLifecycleOwner = owner
        } else {
            self.serviceWorkerLifecycleOwner = nil
        }
    }

    var sharedLifecycleSessionID: String? {
        sharedLifecycleSession?.key.lifecycleSessionID
            ?? serviceWorkerLifecycleOwner?.snapshot.currentSessionID
    }

    func handle(_ body: Any) -> ChromeMV3ExtensionEventAPIsBridgeHostResponse {
        handledRequestCount += 1
        switch ChromeMV3RuntimeJSBridgeHostRequest.parse(body) {
        case .success(let request):
            return handle(request)
        case .failure(let error):
            rejectedRequestCount += 1
            return response(
                request: nil,
                methodName: "parse",
                namespace: "extensionEventAPIs",
                succeeded: false,
                lastErrorMessage: error.message,
                lastErrorCode:
                    ChromeMV3ExtensionEventAPIErrorCode.invalidArguments
                    .rawValue,
                diagnostics: [error.message]
            )
        }
    }

    func handle(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3ExtensionEventAPIsBridgeHostResponse {
        guard configuration.moduleState == .enabled,
              configuration.explicitInternalEventAPIsBridgeAllowed
        else {
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3ExtensionEventAPIErrorCode.extensionDisabled
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3ExtensionEventAPIErrorCode.extensionDisabled
                    .rawValue,
                diagnostics: [
                    "Event API bridge request blocked because the extensions module or explicit internal gate is disabled.",
                ]
            )
        }

        switch request.namespace {
        case "contextMenus":
            return handleContextMenus(request)
        case "alarms":
            return handleAlarms(request)
        case "webNavigation":
            return handleWebNavigation(request)
        default:
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3ExtensionEventAPIErrorCode.namespaceUnsupported
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3ExtensionEventAPIErrorCode.namespaceUnsupported
                    .rawValue,
                diagnostics: [
                    "Unsupported event API namespace: \(request.namespace).",
                ]
            )
        }
    }

    func triggerContextMenuClick(
        _ fixture: ChromeMV3ContextMenusSyntheticClickFixture
    ) -> ChromeMV3ContextMenusClickDispatchRecord {
        runtimeStateOwner.triggerContextMenuClick(
            fixture,
            serviceWorkerLifecycleOwner: serviceWorkerLifecycleOwner,
            lifecycleComponentID: contextMenusComponentID,
            sharedLifecycleSessionID: sharedLifecycleSession?.key.lifecycleSessionID
        )
    }

    func triggerAlarm(name: String) -> ChromeMV3AlarmTriggerRecord {
        runtimeStateOwner.triggerAlarm(
            name: name,
            serviceWorkerLifecycleOwner: serviceWorkerLifecycleOwner,
            lifecycleComponentID: alarmsComponentID,
            sharedLifecycleSessionID: sharedLifecycleSession?.key.lifecycleSessionID
        )
    }

    func emitWebNavigationEvent(
        _ event: ChromeMV3WebNavigationSyntheticEvent
    ) -> ChromeMV3WebNavigationDispatchRecord {
        runtimeStateOwner.emitWebNavigationEvent(
            event,
            serviceWorkerLifecycleOwner: serviceWorkerLifecycleOwner,
            lifecycleComponentID: webNavigationComponentID,
            sharedLifecycleSessionID: sharedLifecycleSession?.key.lifecycleSessionID
        )
    }

    func tearDown() {
        runtimeStateOwner.tearDown()
        if sharedLifecycleSession != nil {
            _ = sharedLifecycleSession?.detachComponent(
                componentID: contextMenusComponentID,
                reason: .reset
            )
            _ = sharedLifecycleSession?.detachComponent(
                componentID: alarmsComponentID,
                reason: .reset
            )
            _ = sharedLifecycleSession?.detachComponent(
                componentID: webNavigationComponentID,
                reason: .reset
            )
        } else {
            serviceWorkerLifecycleOwner?.tearDownForExtensionDisable()
        }
    }

    private func handleContextMenus(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3ExtensionEventAPIsBridgeHostResponse {
        switch request.methodName {
        case "create":
            let record = runtimeStateOwner.createContextMenu(
                properties: request.arguments.first,
                invocationMode: request.invocationMode
            )
            return response(from: record, request: request)
        case "update":
            let record = runtimeStateOwner.updateContextMenu(
                idValue: request.arguments.first,
                properties: request.arguments.dropFirst().first,
                invocationMode: request.invocationMode
            )
            return response(from: record, request: request)
        case "remove":
            let record = runtimeStateOwner.removeContextMenu(
                idValue: request.arguments.first,
                invocationMode: request.invocationMode
            )
            return response(from: record, request: request)
        case "removeAll":
            let record = runtimeStateOwner.removeAllContextMenus(
                invocationMode: request.invocationMode
            )
            return response(from: record, request: request)
        case "onClicked.addListener":
            return registerListener(
                request,
                namespace: "contextMenus",
                eventName: "onClicked",
                listenerEvent: .contextMenusOnClicked
            )
        case "onClicked.removeListener":
            return removeListener(
                request,
                namespace: "contextMenus",
                eventName: "onClicked",
                listenerEvent: .contextMenusOnClicked
            )
        case "onClicked.hasListener":
            return hasListener(
                request,
                namespace: "contextMenus",
                eventName: "onClicked"
            )
        default:
            return unsupported(request)
        }
    }

    private func handleAlarms(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3ExtensionEventAPIsBridgeHostResponse {
        switch request.methodName {
        case "create":
            let record = runtimeStateOwner.createAlarm(
                arguments: request.arguments,
                invocationMode: request.invocationMode
            )
            return response(from: record, request: request)
        case "get":
            let record = runtimeStateOwner.getAlarm(
                nameValue: request.arguments.first,
                invocationMode: request.invocationMode
            )
            return response(from: record, request: request)
        case "getAll":
            let record = runtimeStateOwner.getAllAlarms(
                invocationMode: request.invocationMode
            )
            return response(from: record, request: request)
        case "clear":
            let record = runtimeStateOwner.clearAlarm(
                nameValue: request.arguments.first,
                invocationMode: request.invocationMode
            )
            return response(from: record, request: request)
        case "clearAll":
            let record = runtimeStateOwner.clearAllAlarms(
                invocationMode: request.invocationMode
            )
            return response(from: record, request: request)
        case "onAlarm.addListener":
            return registerListener(
                request,
                namespace: "alarms",
                eventName: "onAlarm",
                listenerEvent: .alarmsOnAlarm
            )
        case "onAlarm.removeListener":
            return removeListener(
                request,
                namespace: "alarms",
                eventName: "onAlarm",
                listenerEvent: .alarmsOnAlarm
            )
        case "onAlarm.hasListener":
            return hasListener(
                request,
                namespace: "alarms",
                eventName: "onAlarm"
            )
        default:
            return unsupported(request)
        }
    }

    private func handleWebNavigation(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3ExtensionEventAPIsBridgeHostResponse {
        if request.methodName == "getFrame" {
            let record = runtimeStateOwner.getFrame(
                details: request.arguments.first,
                invocationMode: request.invocationMode
            )
            return response(from: record, request: request)
        }
        if request.methodName == "getAllFrames" {
            let record = runtimeStateOwner.getAllFrames(
                details: request.arguments.first,
                invocationMode: request.invocationMode
            )
            return response(from: record, request: request)
        }
        guard let parsed = parseWebNavigationListenerMethod(
            request.methodName
        ) else {
            return unsupported(request)
        }
        switch parsed.action {
        case "addListener":
            return registerListener(
                request,
                namespace: "webNavigation",
                eventName: parsed.event.rawValue,
                listenerEvent: parsed.event.listenerEvent,
                webNavigationFilter:
                    ChromeMV3WebNavigationListenerFilter.parse(
                        request.arguments.first
                    )
            )
        case "removeListener":
            return removeListener(
                request,
                namespace: "webNavigation",
                eventName: parsed.event.rawValue,
                listenerEvent: parsed.event.listenerEvent
            )
        case "hasListener":
            return hasListener(
                request,
                namespace: "webNavigation",
                eventName: parsed.event.rawValue
            )
        default:
            return unsupported(request)
        }
    }

    private func registerListener(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        namespace: String,
        eventName: String,
        listenerEvent: ChromeMV3ServiceWorkerSyntheticListenerEvent,
        webNavigationFilter: ChromeMV3WebNavigationListenerFilter? = nil
    ) -> ChromeMV3ExtensionEventAPIsBridgeHostResponse {
        guard let listenerID = request.listenerID,
              listenerID.isEmpty == false
        else {
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3ExtensionEventAPIErrorCode.invalidArguments
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3ExtensionEventAPIErrorCode.invalidArguments
                    .rawValue,
                diagnostics: [
                    "Listener registration requires a synthetic listenerID.",
                ]
            )
        }
        let registration = runtimeStateOwner.listenerRegistry.register(
            namespace: namespace,
            eventName: eventName,
            listenerID: listenerID,
            webNavigationFilter: webNavigationFilter
        )
        serviceWorkerLifecycleOwner?.registerListener(
            event: listenerEvent,
            listenerID: registration.listenerID
        )
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "listenerID": .string(registration.listenerID),
                "eventName": .string(eventName),
                "namespace": .string(namespace),
                "filter":
                    webNavigationFilter?.storageValue ?? .null,
            ]),
            diagnostics: registration.diagnostics
        )
    }

    private func removeListener(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        namespace: String,
        eventName: String,
        listenerEvent: ChromeMV3ServiceWorkerSyntheticListenerEvent
    ) -> ChromeMV3ExtensionEventAPIsBridgeHostResponse {
        let removed = request.listenerID.map {
            runtimeStateOwner.listenerRegistry.remove(
                namespace: namespace,
                eventName: eventName,
                listenerID: $0
            )
        } ?? false
        if removed, let listenerID = request.listenerID {
            serviceWorkerLifecycleOwner?.listenerRegistry.remove(
                event: listenerEvent,
                listenerID: listenerID
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: .bool(removed),
            diagnostics: [
                removed
                    ? "Synthetic event listener was removed."
                    : "Synthetic event listener was not registered.",
            ]
        )
    }

    private func hasListener(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        namespace: String,
        eventName: String
    ) -> ChromeMV3ExtensionEventAPIsBridgeHostResponse {
        let present = request.listenerID.map {
            runtimeStateOwner.listenerRegistry.has(
                namespace: namespace,
                eventName: eventName,
                listenerID: $0
            )
        } ?? false
        return response(
            request: request,
            succeeded: true,
            payload: .bool(present),
            diagnostics: ["Synthetic event listener lookup completed."]
        )
    }

    private func unsupported(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3ExtensionEventAPIsBridgeHostResponse {
        rejectedRequestCount += 1
        return response(
            request: request,
            succeeded: false,
            lastErrorMessage:
                ChromeMV3ExtensionEventAPIErrorCode.methodUnsupported
                .lastErrorMessage,
            lastErrorCode:
                ChromeMV3ExtensionEventAPIErrorCode.methodUnsupported
                .rawValue,
            diagnostics: [
                "Unsupported event API bridge route: \(request.namespace).\(request.methodName).",
            ]
        )
    }

    private func response(
        from record: ChromeMV3ContextMenusOperationRecord,
        request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3ExtensionEventAPIsBridgeHostResponse {
        if record.succeeded == false {
            rejectedRequestCount += 1
        }
        return response(
            request: request,
            succeeded: record.succeeded,
            payload: record.resultPayload,
            lastErrorMessage: record.lastErrorMessage,
            lastErrorCode: record.lastErrorCode,
            diagnostics: record.diagnostics
        )
    }

    private func response(
        from record: ChromeMV3AlarmsOperationRecord,
        request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3ExtensionEventAPIsBridgeHostResponse {
        if record.succeeded == false {
            rejectedRequestCount += 1
        }
        return response(
            request: request,
            succeeded: record.succeeded,
            payload: record.resultPayload,
            lastErrorMessage: record.lastErrorMessage,
            lastErrorCode: record.lastErrorCode,
            diagnostics: record.diagnostics
        )
    }

    private func response(
        from record: ChromeMV3WebNavigationOperationRecord,
        request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3ExtensionEventAPIsBridgeHostResponse {
        if record.succeeded == false {
            rejectedRequestCount += 1
        }
        return response(
            request: request,
            succeeded: record.succeeded,
            payload: record.resultPayload,
            lastErrorMessage: record.lastErrorMessage,
            lastErrorCode: record.lastErrorCode,
            diagnostics: record.diagnostics
        )
    }

    private func response(
        request: ChromeMV3RuntimeJSBridgeHostRequest?,
        methodName: String? = nil,
        namespace: String? = nil,
        succeeded: Bool,
        payload: ChromeMV3StorageValue? = nil,
        lastErrorMessage: String? = nil,
        lastErrorCode: String? = nil,
        serviceWorkerLifecycleWakeResult:
            ChromeMV3ServiceWorkerInternalWakeResult? = nil,
        diagnostics: [String] = []
    ) -> ChromeMV3ExtensionEventAPIsBridgeHostResponse {
        let invocationMode = request?.invocationMode ?? .promise
        return ChromeMV3ExtensionEventAPIsBridgeHostResponse(
            bridgeCallID:
                request?.bridgeCallID
                ?? stableIDExtensionEventAPIs(
                    prefix: "extension-event-apis-response",
                    parts: [
                        namespace ?? "unknown",
                        methodName ?? "unknown",
                        succeeded.description,
                    ]
                ),
            namespace: request?.namespace ?? namespace ?? "extensionEventAPIs",
            methodName: request?.methodName ?? methodName ?? "unknown",
            succeeded: succeeded,
            resultPayload: payload,
            lastErrorMessage: lastErrorMessage,
            lastErrorCode: lastErrorCode,
            callbackWouldSetLastError:
                invocationMode == .callback && succeeded == false,
            promiseWouldReject:
                invocationMode == .promise && succeeded == false,
            contextMenusSummary: runtimeStateOwner.contextMenusSummary,
            alarmsSummary: runtimeStateOwner.alarmsSummary,
            webNavigationSummary: runtimeStateOwner.webNavigationSummary,
            listenerFilterSummary:
                runtimeStateOwner.listenerRegistry.summary,
            serviceWorkerLifecycleWakeResult:
                serviceWorkerLifecycleWakeResult,
            contextMenusAvailableInInternalFixture:
                configuration.contextMenusAvailableInInternalFixture,
            contextMenusAvailableInProduct: false,
            alarmsAvailableInInternalFixture:
                configuration.alarmsAvailableInInternalFixture,
            alarmsRealSchedulingAvailableInProduct: false,
            webNavigationAvailableInInternalFixture:
                configuration.webNavigationAvailableInInternalFixture,
            webNavigationAvailableInProduct: false,
            sharedLifecycleSessionUsed:
                sharedLifecycleSession != nil
                    || serviceWorkerLifecycleWakeResult?.sessionID != nil,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedExtensionEventAPIs(
                    configuration.diagnostics
                        + diagnostics
                        + (serviceWorkerLifecycleWakeResult?.diagnostics ?? [])
                        + [
                            "Event API bridge handler is DEBUG/internal and synthetic-surface gated.",
                            "Product context menu UI, alarm scheduling, browser navigation observation, and normal-tab runtime exposure remain unavailable.",
                        ]
                )
        )
    }

    private func parseWebNavigationListenerMethod(
        _ methodName: String
    ) -> (event: ChromeMV3WebNavigationEventKind, action: String)? {
        let parts = methodName.split(separator: ".", maxSplits: 1)
        guard parts.count == 2,
              let event = ChromeMV3WebNavigationEventKind(
                rawValue: String(parts[0])
              )
        else { return nil }
        return (event, String(parts[1]))
    }
}

struct ChromeMV3ExtensionEventAPIsSharedLifecycleUsage:
    Codable,
    Equatable,
    Sendable
{
    var sharedLifecycleSessionUsed: Bool
    var sessionID: String?
    var contextMenuClickSessionID: String?
    var alarmTriggerSessionID: String?
    var webNavigationSessionIDs: [String]
    var dispatchedEventCount: Int
    var diagnostics: [String]
}

struct ChromeMV3ExtensionEventAPIsWebKitExecutionSummary:
    Codable,
    Equatable,
    Sendable
{
    var status: String
    var eventAPIsJSBridgeAvailableInSyntheticHarness: Bool
    var eventAPIsJSExecutedInWebKitSyntheticHarness: Bool
    var contextMenusCreateExecuted: Bool
    var contextMenusListenerRegistered: Bool
    var alarmsCreateExecuted: Bool
    var alarmsGetAllExecuted: Bool
    var alarmsListenerRegistered: Bool
    var webNavigationListenerRegistered: Bool
    var webNavigationGetFrameExecutedOrDeterministic: Bool
    var callbackModeRepresentedFromActualJSCall: Bool
    var promiseModeRepresentedFromActualJSCall: Bool
    var lastErrorScopedFromActualJSCall: Bool
    var contextMenusAvailableInProduct: Bool
    var alarmsRealSchedulingAvailableInProduct: Bool
    var webNavigationAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var productRuntimeExposed: Bool
    var diagnostics: [String]

    static func notAttempted(
        eventAPIsJSBridgeAvailableInSyntheticHarness: Bool
    ) -> ChromeMV3ExtensionEventAPIsWebKitExecutionSummary {
        ChromeMV3ExtensionEventAPIsWebKitExecutionSummary(
            status: "notAttemptedByModelReportGenerator",
            eventAPIsJSBridgeAvailableInSyntheticHarness:
                eventAPIsJSBridgeAvailableInSyntheticHarness,
            eventAPIsJSExecutedInWebKitSyntheticHarness: false,
            contextMenusCreateExecuted: false,
            contextMenusListenerRegistered: false,
            alarmsCreateExecuted: false,
            alarmsGetAllExecuted: false,
            alarmsListenerRegistered: false,
            webNavigationListenerRegistered: false,
            webNavigationGetFrameExecutedOrDeterministic: false,
            callbackModeRepresentedFromActualJSCall: false,
            promiseModeRepresentedFromActualJSCall: false,
            lastErrorScopedFromActualJSCall: false,
            contextMenusAvailableInProduct: false,
            alarmsRealSchedulingAvailableInProduct: false,
            webNavigationAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            diagnostics: [
                "WebKit synthetic harness was not run by this model-only report generator.",
                "Model handler coverage is reported separately from WebKit JS execution.",
            ]
        )
    }

    static func fromWebKitScriptResult(
        json: String?,
        scriptEvaluationSucceeded: Bool,
        eventAPIsJSBridgeAvailableInSyntheticHarness: Bool,
        diagnostics: [String]
    ) -> ChromeMV3ExtensionEventAPIsWebKitExecutionSummary {
        let object = decodedObject(json)
        func bool(_ key: String) -> Bool {
            object?[key] as? Bool ?? false
        }
        let executed = scriptEvaluationSucceeded
        return ChromeMV3ExtensionEventAPIsWebKitExecutionSummary(
            status:
                executed
                    ? "executedInWebKitSyntheticHarness"
                    : "blockedOrFailedInWebKitSyntheticHarness",
            eventAPIsJSBridgeAvailableInSyntheticHarness:
                eventAPIsJSBridgeAvailableInSyntheticHarness,
            eventAPIsJSExecutedInWebKitSyntheticHarness: executed,
            contextMenusCreateExecuted: bool("contextMenusCreateOK"),
            contextMenusListenerRegistered:
                bool("contextMenusListenerRegisteredOK"),
            alarmsCreateExecuted: bool("alarmsCreateOK"),
            alarmsGetAllExecuted: bool("alarmsGetAllOK"),
            alarmsListenerRegistered: bool("alarmsListenerRegisteredOK"),
            webNavigationListenerRegistered:
                bool("webNavigationListenerRegisteredOK"),
            webNavigationGetFrameExecutedOrDeterministic:
                bool("webNavigationGetFrameOK"),
            callbackModeRepresentedFromActualJSCall:
                bool("callbackModeOK"),
            promiseModeRepresentedFromActualJSCall:
                bool("promiseModeOK"),
            lastErrorScopedFromActualJSCall: bool("lastErrorScopedOK"),
            contextMenusAvailableInProduct: false,
            alarmsRealSchedulingAvailableInProduct: false,
            webNavigationAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            diagnostics:
                uniqueSortedExtensionEventAPIs(
                    diagnostics
                        + [
                            executed
                                ? "Event API JS calls executed in the controlled WebKit synthetic harness."
                                : "Event API WebKit synthetic harness produced a deterministic blocked/failed diagnostic.",
                            "WebKit execution is separate from product runtime availability.",
                        ]
                )
        )
    }

    private static func decodedObject(_ json: String?) -> [String: Any]? {
        guard let json,
              let data = json.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return value as? [String: Any]
    }
}

struct ChromeMV3ExtensionEventAPIsReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var contextMenusAvailableInInternalFixture: Bool
    var contextMenusAvailableInProduct: Bool
    var alarmsAvailableInInternalFixture: Bool
    var alarmsRealSchedulingAvailableInProduct: Bool
    var webNavigationAvailableInInternalFixture: Bool
    var webNavigationAvailableInProduct: Bool
    var sharedLifecycleSessionUsed: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
}

struct ChromeMV3ExtensionEventAPIsReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var extensionID: String
    var profileID: String
    var contextMenusRuntimeSummary:
        ChromeMV3ContextMenusRuntimeSummary
    var contextMenusOperationRecords:
        [ChromeMV3ContextMenusOperationRecord]
    var contextMenusClickFlow:
        [ChromeMV3ContextMenusClickDispatchRecord]
    var alarmsRuntimeSummary: ChromeMV3AlarmsRuntimeSummary
    var alarmsOperationRecords: [ChromeMV3AlarmsOperationRecord]
    var alarmsExplicitTriggerFlow: [ChromeMV3AlarmTriggerRecord]
    var webNavigationRuntimeSummary:
        ChromeMV3WebNavigationRuntimeSummary
    var webNavigationOperationRecords:
        [ChromeMV3WebNavigationOperationRecord]
    var syntheticNavigationFlow:
        [ChromeMV3WebNavigationDispatchRecord]
    var listenerFilterSummary:
        ChromeMV3ExtensionEventListenerFilterSummary
    var sharedLifecycleSessionUsage:
        ChromeMV3ExtensionEventAPIsSharedLifecycleUsage
    var webKitExecutionSummary:
        ChromeMV3ExtensionEventAPIsWebKitExecutionSummary
    var shimCoverage: ChromeMV3ExtensionEventAPIsJSShimCoverage
    var contextMenusAvailableInInternalFixture: Bool
    var contextMenusAvailableInProduct: Bool
    var alarmsAvailableInInternalFixture: Bool
    var alarmsRealSchedulingAvailableInProduct: Bool
    var webNavigationAvailableInInternalFixture: Bool
    var webNavigationAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var productRuntimeExposed: Bool
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    var diagnostics: [String]

    var summary: ChromeMV3ExtensionEventAPIsReportSummary {
        ChromeMV3ExtensionEventAPIsReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            contextMenusAvailableInInternalFixture:
                contextMenusAvailableInInternalFixture,
            contextMenusAvailableInProduct: false,
            alarmsAvailableInInternalFixture:
                alarmsAvailableInInternalFixture,
            alarmsRealSchedulingAvailableInProduct: false,
            webNavigationAvailableInInternalFixture:
                webNavigationAvailableInInternalFixture,
            webNavigationAvailableInProduct: false,
            sharedLifecycleSessionUsed:
                sharedLifecycleSessionUsage.sharedLifecycleSessionUsed,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false
        )
    }
}

enum ChromeMV3ExtensionEventAPIsReportWriter {
    static let reportFileName =
        "runtime-extension-event-apis-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3ExtensionEventAPIsReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3ExtensionEventAPIsReport {
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

enum ChromeMV3ExtensionEventAPIsReportGenerator {
    static func makeReport(
        extensionID: String = "extension-event-apis-mvp-extension",
        profileID: String = "extension-event-apis-mvp-profile",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        webKitExecutionSummary:
            ChromeMV3ExtensionEventAPIsWebKitExecutionSummary? = nil
    ) -> ChromeMV3ExtensionEventAPIsReport {
        let configuration =
            ChromeMV3ExtensionEventAPIsConfiguration.syntheticHarness(
                extensionID: extensionID,
                profileID: profileID,
                moduleState: moduleState
            )
        let registry = ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
        let sharedSession = registry.session(
            profileID: configuration.profileID,
            extensionID: configuration.extensionID,
            moduleState: moduleState,
            explicitInternalLifecycleAllowed:
                configuration.explicitInternalEventAPIsBridgeAllowed
        )
        let handler = ChromeMV3ExtensionEventAPIsJSBridgeHandler(
            configuration: configuration,
            sharedLifecycleSession: sharedSession
        )
        _ = handler.handle(listenerRequest(
            namespace: "contextMenus",
            methodName: "onClicked.addListener",
            listenerID: "context-menu-click-listener"
        ))
        let menuCreate = handler.handle(request(
            namespace: "contextMenus",
            methodName: "create",
            arguments: [
                .object([
                    "id": .string("open-login"),
                    "title": .string("Open Login"),
                    "contexts": .array([.string("page")]),
                    "documentUrlPatterns":
                        .array([.string("https://example.com/*")]),
                ]),
            ]
        ))
        let menuUpdate = handler.handle(request(
            namespace: "contextMenus",
            methodName: "update",
            arguments: [
                .string("open-login"),
                .object(["checked": .bool(true), "enabled": .bool(true)]),
            ]
        ))
        let menuClick = handler.triggerContextMenuClick(
            .page(menuItemID: "open-login")
        )

        _ = handler.handle(listenerRequest(
            namespace: "alarms",
            methodName: "onAlarm.addListener",
            listenerID: "alarm-listener"
        ))
        let alarmCreate = handler.handle(request(
            namespace: "alarms",
            methodName: "create",
            arguments: [
                .string("sync"),
                .object([
                    "delayInMinutes": .number(1),
                    "periodInMinutes": .number(5),
                ]),
            ]
        ))
        let alarmGet = handler.handle(request(
            namespace: "alarms",
            methodName: "get",
            arguments: [.string("sync")]
        ))
        let alarmGetAll = handler.handle(request(
            namespace: "alarms",
            methodName: "getAll"
        ))
        let alarmTrigger = handler.triggerAlarm(name: "sync")

        _ = handler.handle(listenerRequest(
            namespace: "webNavigation",
            methodName: "onCommitted.addListener",
            listenerID: "web-nav-committed-listener",
            arguments: [
                .object([
                    "url": .array([
                        .object(["urlContains": .string("example.com")]),
                    ]),
                ]),
            ]
        ))
        _ = handler.handle(listenerRequest(
            namespace: "webNavigation",
            methodName: "onCompleted.addListener",
            listenerID: "web-nav-completed-listener",
            arguments: [
                .object([
                    "url": .array([
                        .object(["hostEquals": .string("example.com")]),
                    ]),
                ]),
            ]
        ))
        let committed = ChromeMV3WebNavigationSyntheticEvent.committed()
        let navigationCommitted = handler.emitWebNavigationEvent(committed)
        let navigationCompleted = handler.emitWebNavigationEvent(
            committed.withEventKind(.onCompleted, sequence: 2)
        )
        let getFrame = handler.handle(request(
            namespace: "webNavigation",
            methodName: "getFrame",
            arguments: [
                .object([
                    "tabId": .number(1),
                    "frameId": .number(0),
                ]),
            ]
        ))
        let getAllFrames = handler.handle(request(
            namespace: "webNavigation",
            methodName: "getAllFrames",
            arguments: [.object(["tabId": .number(1)])]
        ))

        let allBridgeResponses = [
            menuCreate,
            menuUpdate,
            alarmCreate,
            alarmGet,
            alarmGetAll,
            getFrame,
            getAllFrames,
        ]
        let webKitSummary =
            webKitExecutionSummary
            ?? ChromeMV3ExtensionEventAPIsWebKitExecutionSummary
            .notAttempted(
                eventAPIsJSBridgeAvailableInSyntheticHarness:
                    configuration
                    .contextMenusAvailableInInternalFixture
            )
        let sharedUsage = sharedLifecycleUsage(
            session: sharedSession,
            contextMenuClick: menuClick,
            alarmTrigger: alarmTrigger,
            navigation: [navigationCommitted, navigationCompleted]
        )
        let reportID = stableIDExtensionEventAPIs(
            prefix: "runtime-extension-event-apis",
            parts: [
                configuration.extensionID,
                configuration.profileID,
                allBridgeResponses.map(\.bridgeCallID)
                    .joined(separator: "|"),
                String(menuClick.dispatched),
                String(alarmTrigger.dispatched),
                String(navigationCommitted.dispatched),
                webKitSummary.status,
            ]
        )
        return ChromeMV3ExtensionEventAPIsReport(
            schemaVersion: 1,
            id: reportID,
            reportFileName:
                ChromeMV3ExtensionEventAPIsReportWriter.reportFileName,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            contextMenusRuntimeSummary:
                handler.runtimeStateOwner.contextMenusSummary,
            contextMenusOperationRecords:
                handler.runtimeStateOwner.contextMenuOperationRecords,
            contextMenusClickFlow:
                handler.runtimeStateOwner.contextMenuClickDispatchRecords,
            alarmsRuntimeSummary: handler.runtimeStateOwner.alarmsSummary,
            alarmsOperationRecords:
                handler.runtimeStateOwner.alarmOperationRecords,
            alarmsExplicitTriggerFlow:
                handler.runtimeStateOwner.alarmTriggerRecords,
            webNavigationRuntimeSummary:
                handler.runtimeStateOwner.webNavigationSummary,
            webNavigationOperationRecords:
                handler.runtimeStateOwner.webNavigationOperationRecords,
            syntheticNavigationFlow:
                handler.runtimeStateOwner.webNavigationDispatchRecords,
            listenerFilterSummary:
                handler.runtimeStateOwner.listenerRegistry.summary,
            sharedLifecycleSessionUsage: sharedUsage,
            webKitExecutionSummary: webKitSummary,
            shimCoverage: ChromeMV3ExtensionEventAPIsJSShimSource.coverage,
            contextMenusAvailableInInternalFixture:
                configuration.contextMenusAvailableInInternalFixture,
            contextMenusAvailableInProduct: false,
            alarmsAvailableInInternalFixture:
                configuration.alarmsAvailableInInternalFixture,
            alarmsRealSchedulingAvailableInProduct: false,
            webNavigationAvailableInInternalFixture:
                configuration.webNavigationAvailableInInternalFixture,
            webNavigationAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            documentationSources: documentationSources(),
            diagnostics:
                uniqueSortedExtensionEventAPIs(
                    configuration.diagnostics
                        + webKitSummary.diagnostics
                        + sharedUsage.diagnostics
                        + allBridgeResponses.flatMap(\.diagnostics)
                        + [
                            "Event APIs report covers internal synthetic contextMenus, alarms, and webNavigation basics.",
                            "No product context menu UI, real alarm scheduling, product browser navigation observation, or normal-tab runtime bridge was added.",
                        ]
                )
        )
    }

    private static func sharedLifecycleUsage(
        session: ChromeMV3ServiceWorkerSharedLifecycleSession?,
        contextMenuClick: ChromeMV3ContextMenusClickDispatchRecord,
        alarmTrigger: ChromeMV3AlarmTriggerRecord,
        navigation: [ChromeMV3WebNavigationDispatchRecord]
    ) -> ChromeMV3ExtensionEventAPIsSharedLifecycleUsage {
        let sessionIDs =
            [contextMenuClick.sharedLifecycleSessionID,
             alarmTrigger.sharedLifecycleSessionID]
            .compactMap { $0 }
            + navigation.compactMap(\.sharedLifecycleSessionID)
        let expectedSession = session?.key.lifecycleSessionID
        let used = sessionIDs.isEmpty == false
            && (expectedSession == nil || Set(sessionIDs) == Set([expectedSession!]))
        return ChromeMV3ExtensionEventAPIsSharedLifecycleUsage(
            sharedLifecycleSessionUsed: used,
            sessionID: expectedSession,
            contextMenuClickSessionID:
                contextMenuClick.sharedLifecycleSessionID,
            alarmTriggerSessionID: alarmTrigger.sharedLifecycleSessionID,
            webNavigationSessionIDs:
                navigation.compactMap(\.sharedLifecycleSessionID).sorted(),
            dispatchedEventCount:
                ([contextMenuClick.dispatched, alarmTrigger.dispatched]
                    + navigation.map(\.dispatched)).filter { $0 }.count,
            diagnostics:
                used
                    ? [
                        "Event API synthetic events used the shared internal lifecycle session.",
                    ]
                    : [
                        "Event API synthetic events did not all reach a shared lifecycle session.",
                    ]
        )
    }

    private static func request(
        namespace: String,
        methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode = .promise,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID:
                stableIDExtensionEventAPIs(
                    prefix: "extension-event-apis-report-call",
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
            diagnostics: [
                "Report generator built a deterministic event API bridge request.",
            ]
        )
    }

    private static func listenerRequest(
        namespace: String,
        methodName: String,
        listenerID: String,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID:
                stableIDExtensionEventAPIs(
                    prefix: "extension-event-apis-report-listener",
                    parts: [namespace, methodName, listenerID]
                ),
            namespace: namespace,
            methodName: methodName,
            invocationMode: .fireAndForget,
            arguments: arguments,
            listenerID: listenerID,
            eventName: nil,
            portID: nil,
            diagnostics: [
                "Report generator built a deterministic listener request.",
            ]
        )
    }

    private static func documentationSources()
        -> [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    {
        [
            ChromeMV3WebKitObjectAcceptanceDocumentationSource(
                kind: "chromeDocumentation",
                title: "Chrome contextMenus API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/contextMenus",
                note: "Defines context menu permission, item fields, create/update/remove/removeAll, and onClicked payload shape."
            ),
            ChromeMV3WebKitObjectAcceptanceDocumentationSource(
                kind: "chromeDocumentation",
                title: "Chrome alarms API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/alarms",
                note: "Defines alarms permission, create/get/getAll/clear/clearAll, onAlarm, and MV3 service-worker wake behavior."
            ),
            ChromeMV3WebKitObjectAcceptanceDocumentationSource(
                kind: "chromeDocumentation",
                title: "Chrome webNavigation API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/webNavigation",
                note: "Defines webNavigation permission, event filters, frame methods, and navigation event details."
            ),
            ChromeMV3WebKitObjectAcceptanceDocumentationSource(
                kind: "currentSumiCode",
                title: "Sumi shared lifecycle session",
                url: nil,
                note: "Events route through ChromeMV3ServiceWorkerSharedLifecycleSession in internal fixtures only."
            ),
        ]
    }
}

private extension ChromeMV3StorageValue {
    init?(extensionEventAPIsWebKitValue value: Any) {
        if value is NSNull {
            self = .null
        } else if let bool = value as? Bool {
            self = .bool(bool)
        } else if let string = value as? String {
            self = .string(string)
        } else if let number = value as? NSNumber {
            self = .number(number.doubleValue)
        } else if let array = value as? [Any] {
            self = .array(array.compactMap {
                ChromeMV3StorageValue(extensionEventAPIsWebKitValue: $0)
            })
        } else if let object = value as? [String: Any] {
            var mapped: [String: ChromeMV3StorageValue] = [:]
            for key in object.keys.sorted() {
                if let value = ChromeMV3StorageValue(
                    extensionEventAPIsWebKitValue: object[key] ?? NSNull()
                ) {
                    mapped[key] = value
                }
            }
            self = .object(mapped)
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

    var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self,
              value.rounded(.towardZero) == value
        else { return nil }
        return Int(value)
    }

    var extensionEventAPIsFoundationObject: Any {
        switch self {
        case .array(let values):
            return values.map(\.extensionEventAPIsFoundationObject)
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .number(let value):
            return value
        case .object(let object):
            return object.mapValues(\.extensionEventAPIsFoundationObject)
        case .string(let value):
            return value
        }
    }
}

private func normalizedExtensionEventAPIs(
    _ value: String,
    fallback: String
) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

private func stableIDExtensionEventAPIs(
    prefix: String,
    parts: [String]
) -> String {
    let seed = parts.joined(separator: "\u{1F}")
    let digest = SHA256.hash(data: Data(seed.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "\(prefix)-\(String(hex.prefix(16)))"
}

private func uniqueSortedExtensionEventAPIs(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}

import WebKit

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3ExtensionEventAPIsJSScriptMessageHandler:
    NSObject,
    WKScriptMessageHandlerWithReply
{
    let handler: ChromeMV3ExtensionEventAPIsJSBridgeHandler

    init(handler: ChromeMV3ExtensionEventAPIsJSBridgeHandler) {
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

struct ChromeMV3ExtensionEventAPIsSyntheticHarnessResult:
    Codable,
    Equatable,
    Sendable
{
    var scriptEvaluationSucceeded: Bool
    var scriptResultJSON: String?
    var report: ChromeMV3ExtensionEventAPIsReport
    var webKitExecutionSummary:
        ChromeMV3ExtensionEventAPIsWebKitExecutionSummary
    var handledRequestCount: Int
    var userScriptCount: Int
    var scriptMessageHandlerCount: Int
    var syntheticWebViewCreated: Bool
    var contextMenusAvailableInInternalFixture: Bool
    var contextMenusAvailableInProduct: Bool
    var alarmsAvailableInInternalFixture: Bool
    var alarmsRealSchedulingAvailableInProduct: Bool
    var webNavigationAvailableInInternalFixture: Bool
    var webNavigationAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3ExtensionEventAPIsSyntheticNavigationObserver:
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
enum ChromeMV3ExtensionEventAPIsSyntheticHarness {
    static let reportVerificationScriptBody = """
    const exposedNamespaces = Object.keys(chrome).sort();
    const contextMenuKeys = Object.keys(chrome.contextMenus).sort();
    const alarmKeys = Object.keys(chrome.alarms).sort();
    const webNavigationKeys = Object.keys(chrome.webNavigation).sort();
    function contextMenuListener() {}
    function alarmListener() {}
    function navListener() {}
    chrome.contextMenus.onClicked.addListener(contextMenuListener);
    chrome.alarms.onAlarm.addListener(alarmListener);
    chrome.webNavigation.onCommitted.addListener(navListener, {
      url: [{urlContains: "example.com"}]
    });
    let createCallbackLastErrorInside = "unset";
    await new Promise((resolve) => {
      chrome.contextMenus.create(
        {id: "webkit-menu", title: "WebKit Menu", contexts: ["page"]},
        function() {
          createCallbackLastErrorInside = chrome.runtime.lastError || null;
          resolve();
        }
      );
    });
    const updateResult = await chrome.contextMenus.update(
      "webkit-menu",
      {enabled: true, visible: true}
    );
    await chrome.alarms.create("webkit-alarm", {
      delayInMinutes: 1,
      periodInMinutes: 2
    });
    const alarm = await chrome.alarms.get("webkit-alarm");
    const alarms = await chrome.alarms.getAll();
    let clearCallbackValue = null;
    let clearCallbackLastErrorInside = "unset";
    await new Promise((resolve) => {
      chrome.alarms.clear("missing", function(cleared) {
        clearCallbackValue = cleared;
        clearCallbackLastErrorInside = chrome.runtime.lastError || null;
        resolve();
      });
    });
    const lastErrorOutside = chrome.runtime.lastError || null;
    let frameResult = null;
    try {
      frameResult = await chrome.webNavigation.getFrame({tabId: 1, frameId: 0});
    } catch (error) {
      frameResult = null;
    }
    return {
      exposedNamespaces,
      contextMenuKeys,
      alarmKeys,
      webNavigationKeys,
      contextMenusCreateOK:
        typeof updateResult === "undefined"
        && createCallbackLastErrorInside === null,
      contextMenusListenerRegisteredOK:
        chrome.contextMenus.onClicked.hasListener(contextMenuListener),
      alarmsCreateOK:
        alarm && alarm.name === "webkit-alarm"
        && alarm.repeating === true,
      alarmsGetAllOK:
        Array.isArray(alarms)
        && alarms.some((entry) => entry.name === "webkit-alarm"),
      alarmsListenerRegisteredOK:
        chrome.alarms.onAlarm.hasListener(alarmListener),
      webNavigationListenerRegisteredOK:
        chrome.webNavigation.onCommitted.hasListener(navListener),
      webNavigationGetFrameOK: frameResult === null || typeof frameResult === "object",
      callbackModeOK:
        createCallbackLastErrorInside === null
        && clearCallbackLastErrorInside === null
        && clearCallbackValue === false,
      promiseModeOK:
        Array.isArray(alarms)
        && typeof updateResult === "undefined",
      lastErrorScopedOK: lastErrorOutside === null,
      nativeMessagingMissing: chrome.nativeMessaging === undefined,
      tabsMissing: chrome.tabs === undefined,
      scriptingMissing: chrome.scripting === undefined
    };
    """

    @MainActor
    static func run(
        scriptBody: String,
        configuration: ChromeMV3ExtensionEventAPIsConfiguration =
            .syntheticHarness(),
        html: String =
            "<!doctype html><meta charset='utf-8'><title>Event APIs JS MVP</title>"
    ) async -> ChromeMV3ExtensionEventAPIsSyntheticHarnessResult {
        let registry = ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
        let sharedSession = registry.session(
            profileID: configuration.profileID,
            extensionID: configuration.extensionID,
            moduleState: configuration.moduleState,
            explicitInternalLifecycleAllowed:
                configuration.explicitInternalEventAPIsBridgeAllowed
        )
        let bridgeHandler = ChromeMV3ExtensionEventAPIsJSBridgeHandler(
            configuration: configuration,
            sharedLifecycleSession: sharedSession
        )
        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.sumiIsNormalTabWebViewConfiguration = false
        let scriptHandler = ChromeMV3ExtensionEventAPIsJSScriptMessageHandler(
            handler: bridgeHandler
        )
        webViewConfiguration.userContentController.addScriptMessageHandler(
            scriptHandler,
            contentWorld: .page,
            name: ChromeMV3ExtensionEventAPIsJSShimSource
                .bridgeMessageHandlerName
        )
        let userScript = WKUserScript(
            source:
                ChromeMV3ExtensionEventAPIsJSShimSource.source(
                    configuration: configuration
                ),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webViewConfiguration.userContentController.addUserScript(userScript)

        let webView = WKWebView(
            frame: .zero,
            configuration: webViewConfiguration
        )
        let observer = ChromeMV3ExtensionEventAPIsSyntheticNavigationObserver()
        webView.navigationDelegate = observer
        _ = webView.loadHTMLString(html, baseURL: nil)
        let navigationResult = await observer.wait()
        var diagnostics = [
            "Synthetic WKWebView is hidden and not registered as a product tab.",
            "Event API shim is installed only on the controlled synthetic harness configuration.",
            "Event API bridge handler is installed only on the synthetic harness content controller.",
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
                    extensionEventAPIsWebKitValue: result ?? NSNull()
                )
                .flatMap { try? $0.canonicalJSONString() }
                scriptSucceeded = true
            } catch {
                diagnostics.append(error.localizedDescription)
            }
        }

        let webKitSummary =
            ChromeMV3ExtensionEventAPIsWebKitExecutionSummary
            .fromWebKitScriptResult(
                json: resultJSON,
                scriptEvaluationSucceeded: scriptSucceeded,
                eventAPIsJSBridgeAvailableInSyntheticHarness:
                    configuration.contextMenusAvailableInInternalFixture,
                diagnostics: diagnostics
            )
        let report = ChromeMV3ExtensionEventAPIsReportGenerator.makeReport(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            moduleState: configuration.moduleState,
            webKitExecutionSummary: webKitSummary
        )
        let handledRequestCount = bridgeHandler.handledRequestCount
        let userScriptCount =
            webViewConfiguration.userContentController.userScripts.count

        webView.navigationDelegate = nil
        webViewConfiguration.userContentController
            .removeScriptMessageHandler(
                forName:
                    ChromeMV3ExtensionEventAPIsJSShimSource
                    .bridgeMessageHandlerName,
                contentWorld: .page
            )
        webViewConfiguration.userContentController.removeAllUserScripts()
        bridgeHandler.tearDown()

        return ChromeMV3ExtensionEventAPIsSyntheticHarnessResult(
            scriptEvaluationSucceeded: scriptSucceeded,
            scriptResultJSON: resultJSON,
            report: report,
            webKitExecutionSummary: webKitSummary,
            handledRequestCount: handledRequestCount,
            userScriptCount: userScriptCount,
            scriptMessageHandlerCount: 1,
            syntheticWebViewCreated: true,
            contextMenusAvailableInInternalFixture:
                configuration.contextMenusAvailableInInternalFixture,
            contextMenusAvailableInProduct: false,
            alarmsAvailableInInternalFixture:
                configuration.alarmsAvailableInInternalFixture,
            alarmsRealSchedulingAvailableInProduct: false,
            webNavigationAvailableInInternalFixture:
                configuration.webNavigationAvailableInInternalFixture,
            webNavigationAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedExtensionEventAPIs(
                    diagnostics + webKitSummary.diagnostics
                )
        )
    }
}
