//
//  GlanceSession.swift
//  Sumi
//
//  Created by Jonathan Caudill on 24/09/2025.
//

import Foundation
import WebKit
import SwiftUI

@MainActor
class GlanceSession: ObservableObject, Identifiable {
    let id = UUID()
    let windowId: UUID
    weak var sourceTab: Tab?
    let previewTab: Tab
    let originRectInWindow: CGRect

    @Published var currentURL: URL
    @Published var title: String
    @Published var isLoading: Bool = true
    @Published var estimatedProgress: Double = 0
    @Published var contentFrameInWindowSpace: CGRect?
    private var observations: [NSKeyValueObservation] = []

    init(
        targetURL: URL,
        windowId: UUID,
        sourceTab: Tab?,
        previewTab: Tab,
        originRectInWindow: CGRect
    ) {
        self.windowId = windowId
        self.sourceTab = sourceTab
        self.previewTab = previewTab
        self.originRectInWindow = originRectInWindow
        self.currentURL = targetURL
        self.title = targetURL.absoluteString

        if let webView = previewTab.existingWebView {
            observe(webView)
        }
    }

    deinit {
        observations.forEach { $0.invalidate() }
    }

    func updateNavigationState(url: URL?, title: String?) {
        if let url { currentURL = url }
        if let title, !title.isEmpty { self.title = title }
    }

    func updateLoading(isLoading: Bool) {
        self.isLoading = isLoading
    }

    func updateProgress(_ progress: Double) {
        estimatedProgress = progress
    }

    func updateContentFrameInWindowSpace(_ frame: CGRect?) {
        guard contentFrameInWindowSpace != frame else { return }
        contentFrameInWindowSpace = frame
    }

    func observe(_ webView: WKWebView) {
        observations.forEach { $0.invalidate() }
        observations.removeAll()

        observations.append(
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor [weak self, weak webView] in
                    self?.updateNavigationState(url: webView?.url, title: nil)
                }
            }
        )
        observations.append(
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor [weak self, weak webView] in
                    self?.updateNavigationState(url: nil, title: webView?.title)
                }
            }
        )
        observations.append(
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor [weak self, weak webView] in
                    self?.updateProgress(webView?.estimatedProgress ?? 0)
                }
            }
        )
        observations.append(
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor [weak self, weak webView] in
                    self?.updateLoading(isLoading: webView?.isLoading ?? false)
                }
            }
        )
    }
}
