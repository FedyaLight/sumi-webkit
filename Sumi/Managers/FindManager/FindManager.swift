//
//  FindManager.swift
//  Sumi
//
//  Created by Assistant on 28/12/2024.
//

import Combine
import Foundation

@MainActor
final class FindManager: ObservableObject {
    @Published private(set) var isFindBarVisible: Bool = false
    /// Bumps whenever the AppKit find panel should move keyboard focus to the search field (new show or repeat Cmd+F).
    @Published private(set) var findFieldFocusGeneration: UInt = 0

    var currentTab: Tab? {
        didSet {
            rebindVisibleSessionIfNeeded()
            bindCurrentTabModel()
        }
    }

    var currentModel: FindInPageModel? {
        currentTab?.findInPage.model
    }

    private var modelCancellables = Set<AnyCancellable>()

    func showFindBar(for tab: Tab? = nil) {
        currentTab = tab

        guard let tab,
              let webView = tab.targetFindWebView()
        else { return }

        findFieldFocusGeneration &+= 1

        tab.findInPage.show(with: webView)
        bindCurrentTabModel()
    }

    func hideFindBar() {
        currentTab?.findInPage.close()
        bindCurrentTabModel()
    }

    func closeForNavigation(tab: Tab) {
        tab.findInPage.didStartNavigation()
        if currentTab?.id == tab.id {
            bindCurrentTabModel()
        }
    }

    func closeForSameDocumentNavigation(tab: Tab) {
        tab.findInPage.didSameDocumentNavigation()
        if currentTab?.id == tab.id {
            bindCurrentTabModel()
        }
    }

    func updateCurrentTab(_ tab: Tab?) {
        currentTab = tab
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

    private func rebindVisibleSessionIfNeeded() {
        guard let currentTab,
              currentTab.findInPage.model.isVisible,
              let webView = currentTab.targetFindWebView()
        else { return }

        currentTab.findInPage.show(with: webView)
    }
}
