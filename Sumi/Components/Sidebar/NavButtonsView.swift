//
//  NavButtonsView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import Combine
import AppKit
import SwiftUI
import WebKit

// Narrow wrapper that only publishes navigation state (canGoBack/canGoForward),
// avoiding full Tab.objectWillChange fan-out for unrelated changes like favicon/audio/title.
@MainActor
class ObservableTabWrapper: ObservableObject {
    @Published var tab: Tab?
    weak var browserManager: BrowserManager?
    weak var windowState: BrowserWindowState?
    private var cancellables: Set<AnyCancellable> = []
    @Published private(set) var canGoBack: Bool = false
    @Published private(set) var canGoForward: Bool = false
    @Published private(set) var canReload: Bool = false
    @Published private(set) var isLoading: Bool = false

    func updateTab(_ newTab: Tab?) {
        guard tab !== newTab else { return }

        cancellables.removeAll()
        tab = newTab
        refreshNavigationState()

        NotificationCenter.default.publisher(for: .sumiTabNavigationStateDidChange)
            .filter { [weak newTab] in ($0.object as? Tab) === newTab }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshNavigationState()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .sumiTabLoadingStateDidChange)
            .filter { [weak newTab] in ($0.object as? Tab) === newTab }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshNavigationState()
            }
            .store(in: &cancellables)
    }

    func setContext(browserManager: BrowserManager, windowState: BrowserWindowState) {
        self.browserManager = browserManager
        self.windowState = windowState
    }

    func activeWebView() -> WKWebView? {
        guard let tab else { return nil }
        if let browserManager, let windowState,
           let webView = browserManager.getWebView(for: tab.id, in: windowState.id) {
            return webView
        }
        return tab.assignedWebView ?? tab.existingWebView
    }

    private func refreshNavigationState() {
        let webView = activeWebView()

        if tab?.isFreezingNavigationStateDuringBackForwardGesture == true {
            canGoBack = tab?.canGoBack ?? false
            canGoForward = tab?.canGoForward ?? false
        } else if let webView {
            canGoBack = webView.canGoBack
            canGoForward = webView.canGoForward
        } else {
            canGoBack = tab?.canGoBack ?? false
            canGoForward = tab?.canGoForward ?? false
        }

        isLoading = (tab?.loadingState.isLoading ?? false) || (webView?.isLoading ?? false)
        canReload = tab.map { !$0.representsSumiEmptySurface } ?? false
    }
}

struct NavButtonsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sumiSettings) private var sumiSettings
    @StateObject private var tabWrapper = ObservableTabWrapper()

    var body: some View {
        SumiNavigationToolbarControls(
            state: navigationControlState,
            theme: SumiNavigationToolbarTheme(
                tokens: themeContext.tokens(settings: sumiSettings)
            ),
            browserManager: browserManager,
            windowState: windowState,
            tab: tabWrapper.tab,
            activeWebView: tabWrapper.activeWebView(),
            goBack: goBack,
            goForward: goForward,
            reloadOrStop: reloadOrStopCurrentTab
        )
        .frame(
            width: SidebarChromeMetrics.navigationButtonSize * 3
                + SidebarChromeMetrics.controlSpacing * 2,
            height: SidebarChromeMetrics.navigationButtonSize
        )
        .background(
            DoubleClickView {
                if let window = NSApp.keyWindow {
                    window.performZoom(nil)
                }
            }
        )
        .onAppear {
            tabWrapper.setContext(browserManager: browserManager, windowState: windowState)
            updateCurrentTab()
        }
        .onChange(of: browserManager.currentTab(for: windowState)?.id) { _, _ in
            DispatchQueue.main.async {
                updateCurrentTab()
            }
        }
    }
    
    private func updateCurrentTab() {
        tabWrapper.updateTab(browserManager.currentTab(for: windowState))
    }

    private var navigationControlState: SumiNavigationToolbarControlState {
        SumiNavigationToolbarControlState(
            canGoBack: tabWrapper.canGoBack,
            canGoForward: tabWrapper.canGoForward,
            canReload: tabWrapper.canReload,
            isLoading: tabWrapper.isLoading
        )
    }

    private func activeWebView() -> WKWebView? {
        tabWrapper.activeWebView()
    }
    
    private func goBack() {
        let webView = activeWebView()
        if SumiNavigationHistoryMenuModel.openURLIfModifiedClick(
            webView?.backForwardList.backItem?.url,
            browserManager: browserManager,
            windowState: windowState,
            sourceTab: tabWrapper.tab,
            event: NSApp.currentEvent
        ) {
            return
        }

        if let webView {
            webView.goBack()
        } else {
            tabWrapper.tab?.goBack()
        }
    }
    
    private func goForward() {
        let webView = activeWebView()
        if SumiNavigationHistoryMenuModel.openURLIfModifiedClick(
            webView?.backForwardList.forwardItem?.url,
            browserManager: browserManager,
            windowState: windowState,
            sourceTab: tabWrapper.tab,
            event: NSApp.currentEvent
        ) {
            return
        }

        if let webView {
            webView.goForward()
        } else {
            tabWrapper.tab?.goForward()
        }
    }
    
    private func reloadOrStopCurrentTab() {
        guard let tab = tabWrapper.tab else { return }

        if tabWrapper.isLoading {
            tab.stopLoading(on: activeWebView())
        } else {
            tab.refresh()
        }
    }
    
}
