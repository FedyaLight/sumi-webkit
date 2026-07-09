//
//  DeferredWebViewCommand.swift
//  Sumi
//
//  Value types for WebView commands that must wait behind compositor protection.
//

import Foundation

enum DeferredWebViewCommandKey: Hashable {
    case removeWebViewFromContainers(ObjectIdentifier)
    case removeAllWebViews(UUID)
    case removeTrackedWebView(ObjectIdentifier, UUID, UUID)
    case closeWebViewFromWebKit(ObjectIdentifier)
    case cleanupWindow(UUID)
    case cleanupAllWebViews
    case rebuildLiveWebViews(UUID)
    case evictHiddenWebViews(UUID)
    case cleanupTabWebView(ObjectIdentifier)
    case performFallbackWebViewCleanup(ObjectIdentifier)
}

enum DeferredWebViewCommand {
    case removeWebViewFromContainers(webViewID: ObjectIdentifier)
    case removeAllWebViews(tabID: UUID)
    case removeTrackedWebView(webViewID: ObjectIdentifier, tabID: UUID, windowID: UUID)
    case closeWebViewFromWebKit(webViewID: ObjectIdentifier)
    case cleanupWindow(windowID: UUID)
    case cleanupAllWebViews
    case rebuildLiveWebViews(tabID: UUID, preferredPrimaryWindowID: UUID?)
    case evictHiddenWebViews(windowID: UUID)
    case cleanupTabWebView(webViewID: ObjectIdentifier, tabID: UUID)
    case performFallbackWebViewCleanup(webViewID: ObjectIdentifier, tabID: UUID)

    var key: DeferredWebViewCommandKey {
        switch self {
        case .removeWebViewFromContainers(let webViewID):
            return .removeWebViewFromContainers(webViewID)
        case .removeAllWebViews(let tabID):
            return .removeAllWebViews(tabID)
        case .removeTrackedWebView(let webViewID, let tabID, let windowID):
            return .removeTrackedWebView(webViewID, tabID, windowID)
        case .closeWebViewFromWebKit(let webViewID):
            return .closeWebViewFromWebKit(webViewID)
        case .cleanupWindow(let windowID):
            return .cleanupWindow(windowID)
        case .cleanupAllWebViews:
            return .cleanupAllWebViews
        case .rebuildLiveWebViews(let tabID, _):
            return .rebuildLiveWebViews(tabID)
        case .evictHiddenWebViews(let windowID):
            return .evictHiddenWebViews(windowID)
        case .cleanupTabWebView(let webViewID, _):
            return .cleanupTabWebView(webViewID)
        case .performFallbackWebViewCleanup(let webViewID, _):
            return .performFallbackWebViewCleanup(webViewID)
        }
    }

    var debugSummary: String {
        switch self {
        case .removeWebViewFromContainers(let webViewID):
            return "removeWebViewFromContainers webView=\(webViewID)"
        case .removeAllWebViews(let tabID):
            return "removeAllWebViews tab=\(tabID.uuidString.prefix(8))"
        case .removeTrackedWebView(let webViewID, let tabID, let windowID):
            return "removeTrackedWebView tab=\(tabID.uuidString.prefix(8)) window=\(windowID.uuidString.prefix(8)) webView=\(webViewID)"
        case .closeWebViewFromWebKit(let webViewID):
            return "closeWebViewFromWebKit webView=\(webViewID)"
        case .cleanupWindow(let windowID):
            return "cleanupWindow window=\(windowID.uuidString.prefix(8))"
        case .cleanupAllWebViews:
            return "cleanupAllWebViews"
        case .rebuildLiveWebViews(let tabID, let preferredPrimaryWindowID):
            return "rebuildLiveWebViews tab=\(tabID.uuidString.prefix(8)) preferredWindow=\(preferredPrimaryWindowID?.uuidString.prefix(8) ?? "nil")"
        case .evictHiddenWebViews(let windowID):
            return "evictHiddenWebViews window=\(windowID.uuidString.prefix(8))"
        case .cleanupTabWebView(let webViewID, let tabID):
            return "cleanupTabWebView tab=\(tabID.uuidString.prefix(8)) webView=\(webViewID)"
        case .performFallbackWebViewCleanup(let webViewID, let tabID):
            return "performFallbackWebViewCleanup tab=\(tabID.uuidString.prefix(8)) webView=\(webViewID)"
        }
    }
}

enum DeferredProtectedCommandEnqueueOutcome {
    case enqueued
    case collapsed
    case droppedAtCapacity
}

struct DeferredProtectedCommandBuffer {
    static let maxCommands = 8

    private(set) var commands: [DeferredWebViewCommand] = []

    var count: Int { commands.count }
    var isEmpty: Bool { commands.isEmpty }

    mutating func enqueue(_ command: DeferredWebViewCommand) -> DeferredProtectedCommandEnqueueOutcome {
        if let index = commands.firstIndex(where: { $0.key == command.key }) {
            commands[index] = command
            return .collapsed
        }
        guard commands.count < Self.maxCommands else {
            return .droppedAtCapacity
        }
        commands.append(command)
        return .enqueued
    }

    mutating func prune(
        where shouldDrop: (DeferredWebViewCommand) -> Bool
    ) -> [DeferredWebViewCommand] {
        var dropped: [DeferredWebViewCommand] = []
        commands.removeAll { command in
            guard shouldDrop(command) else { return false }
            dropped.append(command)
            return true
        }
        return dropped
    }

    mutating func drain() -> [DeferredWebViewCommand] {
        let drained = commands
        commands.removeAll(keepingCapacity: true)
        return drained
    }
}
