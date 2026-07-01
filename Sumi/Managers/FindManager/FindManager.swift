//
//  FindManager.swift
//  Sumi
//
//

import Combine
import Foundation

@MainActor
final class FindManager: ObservableObject {
    @Published private(set) var isFindBarVisible: Bool = false
    /// Bumps whenever the AppKit find panel should move keyboard focus to the search field (new show or repeat Cmd+F).
    @Published private(set) var findFieldFocusGeneration: UInt = 0

    private(set) var currentTab: Tab?
    private var currentWindowId: UUID?

    var currentModel: FindInPageModel? {
        currentTab?.findInPage.model
    }

    private var modelCancellables = Set<AnyCancellable>()

    func showFindBar(for tab: Tab?, in windowId: UUID?) {
        updateCurrentSession(tab, windowId: windowId)

        guard let tab,
              let webView = tab.targetFindWebView(in: windowId)
        else { return }

        findFieldFocusGeneration &+= 1

        tab.findInPage.show(with: webView)
        bindCurrentTabModel()
    }

    func hideFindBar() {
        currentTab?.findInPage.close()
        bindCurrentTabModel()
    }

    func updateCurrentTab(_ tab: Tab?, in windowId: UUID?) {
        updateCurrentSession(tab, windowId: windowId)
    }

    func findNext() {
        currentTab?.findInPage.findNext()
    }

    func findPrevious() {
        currentTab?.findInPage.findPrevious()
    }

    private func bindCurrentTabModel() {
        modelCancellables.removeAll()

        guard let model = currentTab?.findInPage.model else {
            isFindBarVisible = false
            return
        }

        isFindBarVisible = model.isVisible

        model.$isVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                self?.isFindBarVisible = isVisible
            }
            .store(in: &modelCancellables)
    }

    private func updateCurrentSession(_ tab: Tab?, windowId: UUID?) {
        currentTab = tab
        currentWindowId = tab == nil ? nil : windowId
        rebindVisibleSessionIfNeeded()
        bindCurrentTabModel()
    }

    private func rebindVisibleSessionIfNeeded() {
        guard let currentTab,
              currentTab.findInPage.model.isVisible,
              let webView = currentTab.targetFindWebView(in: currentWindowId)
        else { return }

        currentTab.findInPage.show(with: webView)
    }
}
