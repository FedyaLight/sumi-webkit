//
//  ZoomManager.swift
//  Sumi
//
//

import Combine
import Foundation
import WebKit

@Observable
@MainActor
class ZoomManager: ObservableObject {
    private let userDefaults: UserDefaults
    private let zoomKeyPrefix = "zoom."
    private static let defaultZoomLevel: Double = 1.0

    // DuckDuckGo page zoom presets.
    static let zoomPresets: [Double] = [0.5, 0.75, 0.85, 1.0, 1.15, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    // Current zoom state for each tab
    private var tabZoomLevels: [UUID: Double] = [:]

    // Per-domain zoom for private partitions. A private partition's preferences
    // live for the lifetime of its window only, so they are never written to
    // UserDefaults.
    private var privatePartitionZoomLevels: [String: Double] = [:]

    // Published properties for UI updates
    var currentZoomLevel: Double = 1.0
    var currentDomain: String?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Public Methods

    /// Get zoom level for a specific domain
    func getZoomLevel(
        for domain: String,
        profileId: UUID? = nil,
        isEphemeralProfile: Bool = false
    ) -> Double {
        guard let key = zoomStorageKey(for: domain, profileId: profileId) else {
            return Self.defaultZoomLevel
        }

        if isEphemeralProfile {
            return privatePartitionZoomLevels[key].map(clampZoom)
                ?? Self.defaultZoomLevel
        }

        return zoomLevel(forKey: key).map(clampZoom) ?? Self.defaultZoomLevel
    }

    /// Save zoom level for a specific domain
    func saveZoomLevel(
        _ zoomLevel: Double,
        for domain: String,
        profileId: UUID? = nil,
        isEphemeralProfile: Bool = false
    ) {
        guard let key = zoomStorageKey(for: domain, profileId: profileId) else {
            return
        }

        let clampedZoom = clampZoom(zoomLevel)
        if isEphemeralProfile {
            if isDefaultZoom(clampedZoom) {
                privatePartitionZoomLevels.removeValue(forKey: key)
            } else {
                privatePartitionZoomLevels[key] = clampedZoom
            }
            return
        }

        if isDefaultZoom(clampedZoom) {
            userDefaults.removeObject(forKey: key)
        } else {
            userDefaults.set(clampedZoom, forKey: key)
        }
    }

    /// Get zoom level for a specific tab
    func getZoomLevel(for tabId: UUID) -> Double {
        tabZoomLevels[tabId] ?? Self.defaultZoomLevel
    }

    /// Set zoom level for a specific tab
    func setZoomLevel(_ zoomLevel: Double, for tabId: UUID) {
        let clampedZoom = clampZoom(zoomLevel)
        tabZoomLevels[tabId] = clampedZoom
        currentZoomLevel = clampedZoom
    }

    func effectiveZoom(baseZoom: Double, multiplier: Double) -> Double {
        clampZoom(baseZoom * multiplier)
    }

    func nextZoomLevel(from currentLevel: Double, direction: ZoomStepDirection) -> Double {
        findNextZoomLevel(from: currentLevel, direction: direction)
    }

    func applyTransientZoom(
        _ zoomLevel: Double,
        to webView: WKWebView,
        domain: String?,
        tabId: UUID
    ) {
        let clampedZoom = clampZoom(zoomLevel)
        webView.pageZoom = clampedZoom
        setZoomLevel(clampedZoom, for: tabId)
        currentZoomLevel = clampedZoom
        currentDomain = domain
    }

    /// Apply zoom to WebView with persistence
    func applyZoom(
        _ zoomLevel: Double,
        to webView: WKWebView,
        domain: String?,
        tabId: UUID,
        profileId: UUID? = nil
    ) {
        let clampedZoom = clampZoom(zoomLevel)

        // Apply page zoom to WebView (this scales the content, not the view)
        webView.pageZoom = clampedZoom

        // Update tab zoom level
        setZoomLevel(clampedZoom, for: tabId)

        // Save for domain if available
        if let domain = domain {
            saveZoomLevel(clampedZoom, for: domain, profileId: profileId)
            currentDomain = domain
        }

        currentZoomLevel = clampedZoom
    }

    /// Zoom in for the current tab
    func zoomIn(for webView: WKWebView, domain: String?, tabId: UUID, profileId: UUID? = nil) {
        let currentLevel = getZoomLevel(for: tabId)
        let nextLevel = findNextZoomLevel(from: currentLevel, direction: .up)
        applyZoom(nextLevel, to: webView, domain: domain, tabId: tabId, profileId: profileId)
    }

    /// Zoom out for the current tab
    func zoomOut(for webView: WKWebView, domain: String?, tabId: UUID, profileId: UUID? = nil) {
        let currentLevel = getZoomLevel(for: tabId)
        let nextLevel = findNextZoomLevel(from: currentLevel, direction: .down)
        applyZoom(nextLevel, to: webView, domain: domain, tabId: tabId, profileId: profileId)
    }

    /// Reset zoom to 100%
    func resetZoom(for webView: WKWebView, domain: String?, tabId: UUID, profileId: UUID? = nil) {
        applyZoom(
            Self.defaultZoomLevel,
            to: webView,
            domain: domain,
            tabId: tabId,
            profileId: profileId
        )
    }

    /// Load saved zoom level for a domain and apply to WebView (only for existing tabs, not new tabs)
    func loadSavedZoom(
        for webView: WKWebView,
        domain: String,
        tabId: UUID,
        profileId: UUID? = nil
    ) {
        let savedZoom = getZoomLevel(for: domain, profileId: profileId)
        applyZoom(savedZoom, to: webView, domain: domain, tabId: tabId, profileId: profileId)
        currentDomain = domain
    }

    func getZoomPercentageDisplay(for tabId: UUID) -> String {
        "\(Int((getZoomLevel(for: tabId) * 100).rounded()))%"
    }

    func isDefaultZoom(for tabId: UUID) -> Bool {
        isDefaultZoom(getZoomLevel(for: tabId))
    }

    func isAtMinimumZoom(for tabId: UUID) -> Bool {
        getZoomLevel(for: tabId) <= (Self.zoomPresets.first ?? 0.5)
    }

    func isAtMaximumZoom(for tabId: UUID) -> Bool {
        getZoomLevel(for: tabId) >= (Self.zoomPresets.last ?? 3.0)
    }

    /// Find the closest zoom preset in the specified direction
    private func findNextZoomLevel(from currentLevel: Double, direction: ZoomStepDirection) -> Double {
        let presets = Self.zoomPresets.sorted()

        switch direction {
        case .up:
            // Find the next larger preset
            for preset in presets {
                if preset > currentLevel + 0.01 { // Add small tolerance to avoid exact matches
                    return preset
                }
            }
            // If no larger preset found, return the maximum
            return presets.last ?? 2.0

        case .down:
            // Find the next smaller preset
            for preset in presets.reversed() {
                if preset < currentLevel - 0.01 { // Add small tolerance to avoid exact matches
                    return preset
                }
            }
            // If no smaller preset found, return the minimum
            return presets.first ?? 0.5
        }
    }

    private func clampZoom(_ zoomLevel: Double) -> Double {
        let minZoom = Self.zoomPresets.first ?? 0.5
        let maxZoom = Self.zoomPresets.last ?? 3.0
        return max(minZoom, min(maxZoom, zoomLevel))
    }

    private func isDefaultZoom(_ zoomLevel: Double) -> Bool {
        abs(zoomLevel - Self.defaultZoomLevel) < 0.01
    }

    private func zoomStorageKey(for domain: String, profileId: UUID?) -> String? {
        let normalizedDomain = domain.normalizedWebsiteDataDomain
        guard !normalizedDomain.isEmpty else { return nil }

        if let profileId {
            let normalizedProfileId = profileId.uuidString.lowercased()
            return "\(zoomKeyPrefix)\(normalizedProfileId).\(normalizedDomain)"
        }

        return "\(zoomKeyPrefix)\(normalizedDomain)"
    }

    private func zoomLevel(forKey key: String) -> Double? {
        guard let storedValue = userDefaults.object(forKey: key) else {
            return nil
        }

        return (storedValue as? Double) ?? (storedValue as? NSNumber)?.doubleValue
    }

    // MARK: - Cleanup

    /// Remove zoom level for a closed tab
    func removeTabZoomLevel(for tabId: UUID) {
        tabZoomLevels.removeValue(forKey: tabId)
    }

    func deletePreferences(profileID: UUID) throws {
        let prefix = "\(zoomKeyPrefix)\(profileID.uuidString.lowercased())."
        for key in privatePartitionZoomLevels.keys where key.hasPrefix(prefix) {
            privatePartitionZoomLevels.removeValue(forKey: key)
        }
        let matchingKeys = userDefaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(prefix)
        }
        matchingKeys.forEach(userDefaults.removeObject(forKey:))
        guard userDefaults.dictionaryRepresentation().keys.contains(where: {
            $0.hasPrefix(prefix)
        }) == false else {
            throw ZoomManagerError.preferenceDeletionFailed(profileID)
        }
    }
}

enum ZoomManagerError: Error, Equatable {
    case preferenceDeletionFailed(UUID)
}

// MARK: - Supporting Types

enum ZoomStepDirection {
    case up // Zoom in
    case down // Zoom out
}

// MARK: - Extensions
