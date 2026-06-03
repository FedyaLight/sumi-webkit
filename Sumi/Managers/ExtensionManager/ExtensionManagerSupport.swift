//
//  ExtensionManagerSupport.swift
//  Sumi
//
//  Small support types used by ExtensionManager orchestration.
//

import AppKit
import Foundation

enum BrowserExtensionActionPopupBlocker:
    String,
    Codable,
    Equatable
{
    case moduleDisabled
    case extensionNotInstalled
    case extensionDisabled
    case actionMissing
    case actionDisabled
    case noActionPopup
    case noEligibleTab
    case currentPagePermissionMissing
    case moduleWorkerUnsupported
    case runtimeUnavailable
    case runtimeLoadFailed
    case contextUnavailable
}

struct BrowserExtensionActionPopupRequestResult:
    Codable,
    Equatable
{
    var opened: Bool
    var blocker: BrowserExtensionActionPopupBlocker?
    var message: String
    var nativePopupBoundarySnapshot:
        ChromeMV3NativeActionPopupBoundarySnapshot?
    var sanitizedBridgeSnapshot:
        ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?
    var sanitizedBridgeSnapshotDiagnostics: [String] = []

    static let openedPopup = BrowserExtensionActionPopupRequestResult(
        opened: true,
        blocker: nil,
        message: "Extension action popup requested through WebKit.",
        nativePopupBoundarySnapshot: nil,
        sanitizedBridgeSnapshot: nil,
        sanitizedBridgeSnapshotDiagnostics: []
    )

    static func blocked(
        _ blocker: BrowserExtensionActionPopupBlocker,
        message: String
    ) -> BrowserExtensionActionPopupRequestResult {
        BrowserExtensionActionPopupRequestResult(
            opened: false,
            blocker: blocker,
            message: message,
            nativePopupBoundarySnapshot: nil,
            sanitizedBridgeSnapshot: nil,
            sanitizedBridgeSnapshotDiagnostics: []
        )
    }

    static func openedPopup(
        message: String = "Extension action popup requested through WebKit.",
        nativePopupBoundarySnapshot:
            ChromeMV3NativeActionPopupBoundarySnapshot? = nil,
        sanitizedBridgeSnapshot:
            ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?,
        diagnostics: [String]
    ) -> BrowserExtensionActionPopupRequestResult {
        BrowserExtensionActionPopupRequestResult(
            opened: true,
            blocker: nil,
            message: message,
            nativePopupBoundarySnapshot: nativePopupBoundarySnapshot,
            sanitizedBridgeSnapshot: sanitizedBridgeSnapshot,
            sanitizedBridgeSnapshotDiagnostics: diagnostics
        )
    }
}

struct ChromeMV3NativeActionPopupLifecycleEvent:
    Codable,
    Equatable
{
    var milestone: String
    var elapsedMilliseconds: Int
    var popupWebViewAvailable: Bool
    var sanitizedURLShape: String?
    var isLoading: Bool?
    var estimatedProgressBucket: String?
    var note: String?
}

struct ChromeMV3NativeActionPopupRouteObservation:
    Codable,
    Equatable
{
    var apiName: String
    var sourceContext: String
    var targetContext: String
    var nativeBoundary: String
    var metadataAvailable: Bool
    var payloadShape: String?
    var resultClassifier: String?
    var keyCount: Int?
    var safeTopLevelFieldNames: [String]
    var portName: String?
    var listenerRouteResult: String?
    var firstMissingAPIOrError: String?
    var sanitizedURLShape: String?
    var descriptorSummary: String? = nil
    var notes: [String]
}

struct ChromeMV3NativeActionPopupBoundarySnapshot:
    Codable,
    Equatable
{
    var extensionID: String
    var contextUniqueIdentifier: String
    var contextLoaded: Bool
    var actionEnabled: Bool
    var actionPresentsPopup: Bool
    var associatedTabKnown: Bool
    var popupWebViewAccessedBeforePerformAction: Bool
    var popupWebViewAvailableAtPresentation: Bool
    var popupPopoverAvailableAtPresentation: Bool
    var nativePopupBridgeInstalled: Bool
    var nativePopupPreludeConfiguredBeforePopupCreation: Bool
    var nativePopupPreludeAttachedAtDocumentStart: Bool
    var nativePopupPreludeFirstMissingAPIOrError: String?
    var lifecycleEvents: [ChromeMV3NativeActionPopupLifecycleEvent]
    var routeObservations: [ChromeMV3NativeActionPopupRouteObservation]
    var observerLimitations: [String]

    var sanitizedLogLines: [String] {
        var lines = lifecycleEvents.map { event in
            [
                "popupLifecycle milestone=\(event.milestone)",
                "elapsedMs=\(event.elapsedMilliseconds)",
                "webViewAvailable=\(event.popupWebViewAvailable)",
                event.sanitizedURLShape.map { "urlShape=\($0)" },
                event.isLoading.map { "isLoading=\($0)" },
                event.estimatedProgressBucket.map { "progress=\($0)" },
                event.note.map { "note=\($0)" },
            ]
                .compactMap { $0 }
                .joined(separator: " ")
        }

        lines.append(contentsOf: routeObservations.map { route in
            [
                "popupRoute api=\(route.apiName)",
                "source=\(route.sourceContext)",
                "target=\(route.targetContext)",
                "boundary=\(route.nativeBoundary)",
                "metadataAvailable=\(route.metadataAvailable)",
                route.payloadShape.map { "payloadShape=\($0)" },
                route.keyCount.map { "keyCount=\($0)" },
                route.safeTopLevelFieldNames.isEmpty
                    ? nil
                    : "safeFields=\(route.safeTopLevelFieldNames.joined(separator: ","))",
                route.portName.map { "portName=\($0)" },
                route.listenerRouteResult.map { "listenerResult=\($0)" },
                route.firstMissingAPIOrError.map { "missingOrError=\($0)" },
                route.sanitizedURLShape.map { "urlShape=\($0)" },
                route.descriptorSummary.map { "descriptor=\($0)" },
                route.resultClassifier.map { "result=\($0)" },
            ]
                .compactMap { $0 }
                .joined(separator: " ")
        })

        return lines
    }
}

@available(macOS 15.5, *)
final class WeakAnchor {
    weak var view: NSView?
    weak var window: NSWindow?

    init(view: NSView?, window: NSWindow?) {
        self.view = view
        self.window = window
    }
}

@available(macOS 15.5, *)
struct BoundedRecentDateTracker {
    let ttl: TimeInterval
    let maxKeys: Int
    let maxDatesPerKey: Int

    private var datesByKey: [String: [Date]] = [:]
    private var keyOrder: [String] = []

    init(ttl: TimeInterval, maxKeys: Int, maxDatesPerKey: Int) {
        self.ttl = ttl
        self.maxKeys = maxKeys
        self.maxDatesPerKey = maxDatesPerKey
    }

    mutating func record(key: String, at now: Date = Date()) {
        prune(now: now)

        var dates = datesByKey[key] ?? []
        dates.append(now)
        if dates.count > maxDatesPerKey {
            dates.removeFirst(dates.count - maxDatesPerKey)
        }

        datesByKey[key] = dates
        touch(key)
        evictIfNeeded()
    }

    mutating func consume(key: String, at now: Date = Date()) -> Bool {
        prune(now: now)

        guard var dates = datesByKey[key], dates.isEmpty == false else {
            return false
        }

        dates.removeLast()
        if dates.isEmpty {
            datesByKey.removeValue(forKey: key)
            keyOrder.removeAll { $0 == key }
        } else {
            datesByKey[key] = dates
            touch(key)
        }

        return true
    }

    mutating func removeAll() {
        datesByKey.removeAll()
        keyOrder.removeAll()
    }

    private mutating func prune(now: Date) {
        for key in Array(datesByKey.keys) {
            let dates = (datesByKey[key] ?? []).filter {
                now.timeIntervalSince($0) <= ttl
            }

            if dates.isEmpty {
                datesByKey.removeValue(forKey: key)
                keyOrder.removeAll { $0 == key }
            } else {
                datesByKey[key] = dates
            }
        }
    }

    private mutating func touch(_ key: String) {
        keyOrder.removeAll { $0 == key }
        keyOrder.append(key)
    }

    private mutating func evictIfNeeded() {
        while datesByKey.count > maxKeys, let key = keyOrder.first {
            keyOrder.removeFirst()
            datesByKey.removeValue(forKey: key)
        }
    }
}
