//
//  FindManager.swift
//  Sumi
//
//

import Combine
import Foundation

@MainActor
final class FindManager: ObservableObject {
    typealias WebViewResolver = @MainActor (Tab, UUID?) -> (any FindInPageWebView)?

    @Published private(set) var isFindBarVisible: Bool = false
    /// Bumps whenever the AppKit find panel should move keyboard focus to the search field (new show or repeat Cmd+F).
    @Published private(set) var findFieldFocusGeneration: UInt = 0

    private(set) var currentTab: Tab?
    private var currentWindowId: UUID?
    private weak var currentWebView: (any FindInPageWebView)?
    private weak var boundModel: FindInPageModel?
    private let resolveWebView: WebViewResolver

    var currentModel: FindInPageModel? {
        currentTab?.findInPage.model
    }

    private var visibilityCancellable: AnyCancellable?

    init(
        resolveWebView: @escaping WebViewResolver = { tab, windowId in
            tab.targetFindWebView(in: windowId)
        }
    ) {
        self.resolveWebView = resolveWebView
    }

    func showFindBar(for tab: Tab?, in windowId: UUID?) {
        let webView = updateCurrentRouting(tab, windowId: windowId)

        guard let tab,
              let webView
        else { return }

        findFieldFocusGeneration &+= 1

        tab.findInPage.show(with: webView)
    }

    func hideFindBar() {
        currentTab?.findInPage.close()
    }

    func updateCurrentTab(_ tab: Tab?, in windowId: UUID?) {
        let oldTab = currentTab
        let oldWindowId = currentWindowId
        let oldWebView = currentWebView
        let webView = updateCurrentRouting(tab, windowId: windowId)

        guard let tab,
              tab.findInPage.model.isVisible,
              let webView,
              oldTab !== tab
                || oldWindowId != windowId
                || oldWebView !== webView
        else { return }

        tab.findInPage.show(with: webView)
    }

    func findNext() {
        currentTab?.findInPage.findNext()
    }

    func findPrevious() {
        currentTab?.findInPage.findPrevious()
    }

    private func bindCurrentTabModel() {
        let model = currentTab?.findInPage.model
        guard boundModel !== model else { return }

        visibilityCancellable = nil
        boundModel = model

        guard let model else {
            setFindBarVisible(false)
            return
        }

        setFindBarVisible(model.isVisible)

        visibilityCancellable = model.$isVisible
            .sink { [weak self] isVisible in
                self?.setFindBarVisible(isVisible)
            }
    }

    @discardableResult
    private func updateCurrentRouting(
        _ tab: Tab?,
        windowId: UUID?
    ) -> (any FindInPageWebView)? {
        let webView = tab.flatMap { resolveWebView($0, windowId) }
        currentTab = tab
        currentWindowId = tab == nil ? nil : windowId
        currentWebView = webView
        bindCurrentTabModel()
        return webView
    }

    private func setFindBarVisible(_ isVisible: Bool) {
        guard isFindBarVisible != isVisible else { return }
        isFindBarVisible = isVisible
    }
}
