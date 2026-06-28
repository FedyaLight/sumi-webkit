//
//  GlanceSession.swift
//  Sumi
//
//

import Foundation
import SwiftUI
import WebKit

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
        if let url, currentURL != url {
            currentURL = url
        }
        if let title, !title.isEmpty, self.title != title {
            self.title = title
        }
    }

    func updateLoading(isLoading: Bool) {
        guard self.isLoading != isLoading else { return }
        self.isLoading = isLoading
    }

    func updateProgress(_ progress: Double) {
        guard estimatedProgress != progress else { return }
        estimatedProgress = progress
    }

    func updateContentFrameInWindowSpace(_ frame: CGRect?) {
        guard contentFrameInWindowSpace != frame else { return }
        contentFrameInWindowSpace = frame
    }

    func observe(_ webView: WKWebView) {
        observations.forEach { $0.invalidate() }
        observations.removeAll()

        applyCurrentState(from: webView)

        observations.append(
            webView.observe(\.url, options: [.new]) { [weak self, weak webView] _, _ in
                Self.applyObservedStateOnMainThread {
                    self?.updateNavigationState(url: webView?.url, title: nil)
                }
            }
        )
        observations.append(
            webView.observe(\.title, options: [.new]) { [weak self, weak webView] _, _ in
                Self.applyObservedStateOnMainThread {
                    self?.updateNavigationState(url: nil, title: webView?.title)
                }
            }
        )
        observations.append(
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self, weak webView] _, _ in
                Self.applyObservedStateOnMainThread {
                    self?.updateProgress(webView?.estimatedProgress ?? 0)
                }
            }
        )
        observations.append(
            webView.observe(\.isLoading, options: [.new]) { [weak self, weak webView] _, _ in
                Self.applyObservedStateOnMainThread {
                    self?.updateLoading(isLoading: webView?.isLoading ?? false)
                }
            }
        )
    }

    private func applyCurrentState(from webView: WKWebView) {
        updateNavigationState(url: webView.url, title: webView.title)
        updateProgress(webView.estimatedProgress)
        updateLoading(isLoading: webView.isLoading)
    }

    nonisolated private static func applyObservedStateOnMainThread(
        _ update: @MainActor () -> Void
    ) {
        guard Thread.isMainThread else {
            assertionFailure("GlanceSession received WKWebView KVO off the main thread")
            return
        }

        MainActor.assumeIsolated {
            update()
        }
    }
}
