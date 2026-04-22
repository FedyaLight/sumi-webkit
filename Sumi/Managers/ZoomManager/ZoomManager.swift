//
//  ZoomManager.swift
//  Sumi
//
//  Created by Assistant on 13/10/2025.
//

import Foundation
import WebKit
import Combine

@Observable
@MainActor
class ZoomManager: ObservableObject {
    private let userDefaults = UserDefaults.standard
    private let zoomKeyPrefix = "zoom."
    private static let defaultZoomLevel: Double = 1.0

    // DuckDuckGo page zoom presets.
    static let zoomPresets: [Double] = [0.5, 0.75, 0.85, 1.0, 1.15, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    // Current zoom state for each tab
    private var tabZoomLevels: [UUID: Double] = [:]

    // Published properties for UI updates
    var currentZoomLevel: Double = 1.0
    var currentDomain: String?

    init() {}

    // MARK: - Public Methods

    /// Get zoom level for a specific domain
    func getZoomLevel(for domain: String) -> Double {
        let key = zoomKeyPrefix + domain
        guard let storedValue = userDefaults.object(forKey: key) else {
            return Self.defaultZoomLevel
        }
        let rawValue = (storedValue as? Double) ?? (storedValue as? NSNumber)?.doubleValue ?? Self.defaultZoomLevel
        return clampZoom(rawValue)
    }

    /// Save zoom level for a specific domain
    func saveZoomLevel(_ zoomLevel: Double, for domain: String) {
        let key = zoomKeyPrefix + domain
        let clampedZoom = clampZoom(zoomLevel)
        if isDefaultZoom(clampedZoom) {
            userDefaults.removeObject(forKey: key)
        } else {
            userDefaults.set(clampedZoom, forKey: key)
        }
    }

    /// Get zoom level for a specific tab
    func getZoomLevel(for tabId: UUID) -> Double {
        return tabZoomLevels[tabId] ?? Self.defaultZoomLevel
    }

    /// Set zoom level for a specific tab
    func setZoomLevel(_ zoomLevel: Double, for tabId: UUID) {
        let clampedZoom = clampZoom(zoomLevel)
        tabZoomLevels[tabId] = clampedZoom
        currentZoomLevel = clampedZoom
    }

    /// Apply zoom to WebView with persistence
    func applyZoom(_ zoomLevel: Double, to webView: WKWebView, domain: String?, tabId: UUID) {
        let clampedZoom = clampZoom(zoomLevel)

        // Apply page zoom to WebView (this scales the content, not the view)
        webView.pageZoom = clampedZoom

        // Update tab zoom level
        setZoomLevel(clampedZoom, for: tabId)

        // Save for domain if available
        if let domain = domain {
            saveZoomLevel(clampedZoom, for: domain)
            currentDomain = domain
        }

        currentZoomLevel = clampedZoom
    }

    /// Zoom in for the current tab
    func zoomIn(for webView: WKWebView, domain: String?, tabId: UUID) {
        let currentLevel = getZoomLevel(for: tabId)
        let nextLevel = findNextZoomLevel(from: currentLevel, direction: .up)
        applyZoom(nextLevel, to: webView, domain: domain, tabId: tabId)
    }

    /// Zoom out for the current tab
    func zoomOut(for webView: WKWebView, domain: String?, tabId: UUID) {
        let currentLevel = getZoomLevel(for: tabId)
        let nextLevel = findNextZoomLevel(from: currentLevel, direction: .down)
        applyZoom(nextLevel, to: webView, domain: domain, tabId: tabId)
    }

    /// Reset zoom to 100%
    func resetZoom(for webView: WKWebView, domain: String?, tabId: UUID) {
        applyZoom(Self.defaultZoomLevel, to: webView, domain: domain, tabId: tabId)
    }

    /// Load saved zoom level for a domain and apply to WebView (only for existing tabs, not new tabs)
    func loadSavedZoom(for webView: WKWebView, domain: String, tabId: UUID) {
        let savedZoom = getZoomLevel(for: domain)
        applyZoom(savedZoom, to: webView, domain: domain, tabId: tabId)
        currentDomain = domain
    }

    func getZoomPercentageDisplay(for tabId: UUID) -> String {
        return "\(Int((getZoomLevel(for: tabId) * 100).rounded()))%"
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
    private func findNextZoomLevel(from currentLevel: Double, direction: ZoomDirection) -> Double {
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

    // MARK: - Cleanup

    /// Remove zoom level for a closed tab
    func removeTabZoomLevel(for tabId: UUID) {
        tabZoomLevels.removeValue(forKey: tabId)
    }

}

// MARK: - Supporting Types

private enum ZoomDirection {
    case up    // Zoom in
    case down  // Zoom out
}

// MARK: - Extensions
