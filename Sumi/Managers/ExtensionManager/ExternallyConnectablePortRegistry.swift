//
//  ExternallyConnectablePortRegistry.swift
//  Sumi
//
//  Single source of truth for externally_connectable runtime state:
//  pending sendMessage requests, active connect port sessions, and
//  navigation-tracked page URLs.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExternallyConnectablePortRegistry {
    static let maxPendingRequests = 256
    static let maxPendingRequestsPerWebView = 32
    static let maxActivePorts = 128
    static let maxActivePortsPerWebView = 32
    static let maxTrackedPageURLs = 256

    // MARK: - Pending sendMessage requests

    private var requestsByID: [UUID: PendingExternallyConnectableNativeRequest] = [:]
    private var requestIDsByWebView: [ObjectIdentifier: Set<UUID>] = [:]

    // MARK: - Active connect port sessions

    private var portsByID: [String: ExternallyConnectableNativePortSession] = [:]
    private var portIDsByWebView: [ObjectIdentifier: Set<String>] = [:]
    private var portIDsByExtension: [String: Set<String>] = [:]

    // MARK: - Navigation tracking

    private var trackedPageURLsByWebView: [ObjectIdentifier: String] = [:]
    private var trackedPageURLOrder: [ObjectIdentifier] = []

    // MARK: - Request operations

    @discardableResult
    func addRequest(_ request: PendingExternallyConnectableNativeRequest) -> String? {
        if requestsByID.count >= Self.maxPendingRequests {
            return "Too many pending externally connectable requests"
        }

        if (requestIDsByWebView[request.webViewIdentifier]?.count ?? 0)
            >= Self.maxPendingRequestsPerWebView
        {
            return "Too many pending externally connectable requests for this page"
        }

        requestsByID[request.id] = request
        requestIDsByWebView[request.webViewIdentifier, default: []].insert(request.id)
        return nil
    }

    func removeRequest(id: UUID) -> PendingExternallyConnectableNativeRequest? {
        guard let request = requestsByID.removeValue(forKey: id) else { return nil }
        var ids = requestIDsByWebView[request.webViewIdentifier] ?? []
        ids.remove(id)
        if ids.isEmpty {
            requestIDsByWebView.removeValue(forKey: request.webViewIdentifier)
        } else {
            requestIDsByWebView[request.webViewIdentifier] = ids
        }
        return request
    }

    func requestIDs(for webView: WKWebView) -> Set<UUID> {
        requestIDsByWebView[ObjectIdentifier(webView)] ?? []
    }

    func removeRequestIDs(for webView: WKWebView) -> Set<UUID> {
        requestIDsByWebView.removeValue(forKey: ObjectIdentifier(webView)) ?? []
    }

    func requestIDs(forExtension extensionId: String) -> [UUID] {
        requestsByID.values
            .filter { $0.extensionId == extensionId }
            .map(\.id)
    }

    var allRequestIDs: [UUID] {
        Array(requestsByID.keys)
    }

    func clearAllRequests() {
        requestsByID.removeAll()
        requestIDsByWebView.removeAll()
    }

    // MARK: - Port operations

    func port(for portId: String) -> ExternallyConnectableNativePortSession? {
        portsByID[portId]
    }

    var allPortIDs: [String] {
        Array(portsByID.keys)
    }

    func portExists(_ portId: String) -> Bool {
        portsByID[portId] != nil
    }

    @discardableResult
    func addPort(_ session: ExternallyConnectableNativePortSession) -> String? {
        if portsByID.count >= Self.maxActivePorts {
            return "Too many externally connectable ports are open"
        }

        if (portIDsByWebView[session.webViewIdentifier]?.count ?? 0)
            >= Self.maxActivePortsPerWebView
        {
            return "Too many externally connectable ports are open for this page"
        }

        portsByID[session.portId] = session
        portIDsByWebView[session.webViewIdentifier, default: []].insert(session.portId)
        portIDsByExtension[session.extensionId, default: []].insert(session.portId)
        return nil
    }

    func removePort(portId: String) -> ExternallyConnectableNativePortSession? {
        guard let session = portsByID.removeValue(forKey: portId) else {
            prunePortIndexReferences(portId: portId)
            return nil
        }
        removePortFromIndexes(session)
        return session
    }

    func removePortIDs(for webView: WKWebView) -> [String] {
        let webViewID = ObjectIdentifier(webView)
        let ids = Array(portIDsByWebView.removeValue(forKey: webViewID) ?? [])
        return ids
    }

    func removePortIDs(forExtension extensionId: String) -> [String] {
        Array(portIDsByExtension.removeValue(forKey: extensionId) ?? [])
    }

    func clearAllPorts() {
        portsByID.removeAll()
        portIDsByWebView.removeAll()
        portIDsByExtension.removeAll()
    }

    func extensionIdForPort(_ portId: String) -> String? {
        portsByID[portId]?.extensionId
    }

    // MARK: - Navigation tracking

    func trackedPageURL(for webView: WKWebView) -> String? {
        trackedPageURLsByWebView[ObjectIdentifier(webView)]
    }

    func setTrackedPageURL(_ urlString: String?, for webView: WKWebView) {
        let key = ObjectIdentifier(webView)
        if let urlString {
            trackedPageURLsByWebView[key] = urlString
            touchTrackedPageURL(key)
            evictTrackedPageURLsIfNeeded()
        } else {
            trackedPageURLsByWebView.removeValue(forKey: key)
            trackedPageURLOrder.removeAll { $0 == key }
        }
    }

    func removeTrackedPageURL(for webView: WKWebView) {
        let key = ObjectIdentifier(webView)
        trackedPageURLsByWebView.removeValue(forKey: key)
        trackedPageURLOrder.removeAll { $0 == key }
    }

    func clearAllTrackedPageURLs() {
        trackedPageURLsByWebView.removeAll()
        trackedPageURLOrder.removeAll()
    }

    var trackedPageURLWebViewCount: Int {
        trackedPageURLsByWebView.count
    }

    func trackedPageURL(forWebViewIdentifier id: ObjectIdentifier) -> String? {
        trackedPageURLsByWebView[id]
    }

    // MARK: - Aggregate state queries

    func hasTrackedState(for webView: WKWebView) -> Bool {
        let id = ObjectIdentifier(webView)
        return trackedPageURLsByWebView[id] != nil
            || requestIDsByWebView[id] != nil
            || portIDsByWebView[id] != nil
    }

    // MARK: - Private helpers

    private func removePortFromIndexes(_ session: ExternallyConnectableNativePortSession) {
        var webViewPortIDs = portIDsByWebView[session.webViewIdentifier] ?? []
        webViewPortIDs.remove(session.portId)
        if webViewPortIDs.isEmpty {
            portIDsByWebView.removeValue(forKey: session.webViewIdentifier)
        } else {
            portIDsByWebView[session.webViewIdentifier] = webViewPortIDs
        }

        var extPortIDs = portIDsByExtension[session.extensionId] ?? []
        extPortIDs.remove(session.portId)
        if extPortIDs.isEmpty {
            portIDsByExtension.removeValue(forKey: session.extensionId)
        } else {
            portIDsByExtension[session.extensionId] = extPortIDs
        }
    }

    private func prunePortIndexReferences(portId: String) {
        for key in Array(portIDsByWebView.keys) {
            var ids = portIDsByWebView[key] ?? []
            ids.remove(portId)
            if ids.isEmpty {
                portIDsByWebView.removeValue(forKey: key)
            } else {
                portIDsByWebView[key] = ids
            }
        }
        for key in Array(portIDsByExtension.keys) {
            var ids = portIDsByExtension[key] ?? []
            ids.remove(portId)
            if ids.isEmpty {
                portIDsByExtension.removeValue(forKey: key)
            } else {
                portIDsByExtension[key] = ids
            }
        }
    }

    private func touchTrackedPageURL(_ id: ObjectIdentifier) {
        trackedPageURLOrder.removeAll { $0 == id }
        trackedPageURLOrder.append(id)
    }

    private func evictTrackedPageURLsIfNeeded() {
        while trackedPageURLsByWebView.count > Self.maxTrackedPageURLs {
            guard let evictionID = trackedPageURLOrder.first(where: { id in
                requestIDsByWebView[id]?.isEmpty != false
                    && portIDsByWebView[id]?.isEmpty != false
            }) else {
                return
            }

            trackedPageURLOrder.removeAll { $0 == evictionID }
            trackedPageURLsByWebView.removeValue(forKey: evictionID)
        }
    }
}
