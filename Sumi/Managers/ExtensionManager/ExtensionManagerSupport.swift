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
    Equatable {
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

/// Precise internal buckets when the generic action-popup runtime gate fails.
enum ExtensionActionPopupRuntimeFailureBucket: String, Codable, CaseIterable, Sendable {
    case profileRuntimeNotFound
    case profileContextNotCreated
    case profileContextNotLoaded
    case wrongProfileRuntimeLookup
    case enabledStateWithoutRuntime
    case originalAppExtensionBundleMissing
    case sourceResourcesMissing
    case webExtensionCreationFailed
    case manifestValidationPolicyWrongForSourceKind
    case staleActionSurfaceRecord
    case deletedImportRecordStale
    case privateTabGuardFalsePositive
    case globalRuntimeLoadFailed
    case globalRuntimeUnavailable
}

struct BrowserExtensionActionPopupRequestResult:
    Codable,
    Equatable {
    var opened: Bool
    var blocker: BrowserExtensionActionPopupBlocker?
    var message: String
    var diagnostics: [String] = []

    static let openedPopup = BrowserExtensionActionPopupRequestResult(
        opened: true,
        blocker: nil,
        message: "Extension action popup requested through WebKit.",
        diagnostics: []
    )

    static let performedAction = BrowserExtensionActionPopupRequestResult(
        opened: true,
        blocker: nil,
        message: "Extension action dispatched through WebKit.",
        diagnostics: []
    )

    static func blocked(
        _ blocker: BrowserExtensionActionPopupBlocker,
        message: String,
        diagnostics: [String] = []
    ) -> BrowserExtensionActionPopupRequestResult {
        BrowserExtensionActionPopupRequestResult(
            opened: false,
            blocker: blocker,
            message: message,
            diagnostics: diagnostics
        )
    }
}

/// How an extension action popup anchor was resolved at presentation time.
enum ExtensionActionPopupAnchorSource: String, Codable, Equatable, Sendable {
    case button
    case current
    case fallback
    case stale
}

/// Sanitized anchor resolution diagnostics for extension runtime traces.
struct ExtensionActionPopupAnchorResolution: Equatable, Sendable {
    var anchorResolved: Bool
    var anchorSource: ExtensionActionPopupAnchorSource?
    var windowMatch: Bool
    var profileMatch: Bool
    var sessionToken: UUID?

    static let unresolved = ExtensionActionPopupAnchorResolution(
        anchorResolved: false,
        anchorSource: nil,
        windowMatch: false,
        profileMatch: false,
        sessionToken: nil
    )

    var traceLine: String {
        "anchorResolved=\(anchorResolved) anchorSource=\(anchorSource?.rawValue ?? "nil") windowMatch=\(windowMatch) profileMatch=\(profileMatch) sessionToken=\(sessionToken?.uuidString ?? "nil")"
    }
}

/// Click-time anchor captured before async extension runtime work.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupAnchor {
    let extensionID: String
    let profileID: UUID
    let windowID: UUID
    let sessionToken: UUID
    let capturedAt: Date
    weak var buttonView: NSView?
    var validatedRectInWindow: CGRect?

    init(
        extensionID: String,
        profileID: UUID,
        windowID: UUID,
        sessionToken: UUID = UUID(),
        capturedAt: Date = Date(),
        buttonView: NSView?,
        validatedRectInWindow: CGRect?
    ) {
        self.extensionID = extensionID
        self.profileID = profileID
        self.windowID = windowID
        self.sessionToken = sessionToken
        self.capturedAt = capturedAt
        self.buttonView = buttonView
        self.validatedRectInWindow = validatedRectInWindow
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
