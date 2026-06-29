//
//  NavButtonsView.swift
//  Sumi
//
//
import AppKit
import Combine
import SwiftUI
import WebKit

// Narrow wrapper that only publishes navigation state (canGoBack/canGoForward),
// avoiding full Tab.objectWillChange fan-out for unrelated changes like favicon/audio/title.
@MainActor
class ObservableTabWrapper: ObservableObject {
    @Published var tab: Tab?
    var webViewProvider: ((Tab) -> WKWebView?)?
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

    func setWebViewProvider(_ provider: @escaping (Tab) -> WKWebView?) {
        webViewProvider = provider
    }

    func activeWebView() -> WKWebView? {
        guard let tab else { return nil }
        if let webView = webViewProvider?(tab) {
            return webView
        }
        return tab.assignedWebView ?? tab.existingWebView
    }

    private func refreshNavigationState() {
        // Tab already maintains canGoBack/canGoForward in sync with the
        // underlying WKWebView via TabNavigationStateController (and posts
        // .sumiTabNavigationStateDidChange only on real change). Reading the
        // cached Tab values avoids a KVO round-trip into WebKit on every
        // navigation notification while staying accurate in every case the
        // notification covers.
        canGoBack = tab?.canGoBack ?? false
        canGoForward = tab?.canGoForward ?? false

        let webView = activeWebView()
        isLoading = (tab?.loadingState.isLoading ?? false) || (webView?.isLoading ?? false)
        canReload = tab.map { !$0.representsSumiEmptySurface && !$0.representsSumiNativeSurface } ?? false
    }
}

@MainActor
struct NavigationToolbarBrowserContext {
    let currentTab: () -> Tab?
    let webView: (Tab) -> WKWebView?
    let historyContext: SumiNavigationHistoryContext

    static func live(
        browserManager: BrowserManager,
        windowState: BrowserWindowState
    ) -> NavigationToolbarBrowserContext {
        NavigationToolbarBrowserContext(
            currentTab: { [weak browserManager, weak windowState] in
                guard let browserManager, let windowState else { return nil }
                return browserManager.currentTab(for: windowState)
            },
            webView: { [weak browserManager, weak windowState] tab in
                guard let browserManager, let windowState else { return nil }
                return browserManager.getWebView(for: tab.id, in: windowState.id)
            },
            historyContext: SumiNavigationHistoryContext.live(
                browserManager: browserManager,
                windowState: windowState
            )
        )
    }
}

struct NavButtonsView: View {
    let browserContext: NavigationToolbarBrowserContext

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
            historyContext: browserContext.historyContext,
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
            tabWrapper.setWebViewProvider(browserContext.webView)
            updateCurrentTab()
        }
        .onChange(of: browserContext.currentTab()?.id) { _, _ in
            DispatchQueue.main.async {
                updateCurrentTab()
            }
        }
    }

    private func updateCurrentTab() {
        tabWrapper.updateTab(browserContext.currentTab())
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
            historyContext: browserContext.historyContext,
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
            historyContext: browserContext.historyContext,
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
