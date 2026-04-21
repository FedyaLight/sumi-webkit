//
//  NavButtonsView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import Combine
import SwiftUI

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
    }

    func setContext(browserManager: BrowserManager, windowState: BrowserWindowState) {
        self.browserManager = browserManager
        self.windowState = windowState
    }

    private func refreshNavigationState() {
        if tab?.isFreezingNavigationStateDuringBackForwardGesture == true {
            canGoBack = tab?.canGoBack ?? false
            canGoForward = tab?.canGoForward ?? false
            return
        }

        if let tab, let browserManager, let windowState,
           let webView = browserManager.getWebView(for: tab.id, in: windowState.id) {
            canGoBack = webView.canGoBack
            canGoForward = webView.canGoForward
        } else {
            canGoBack = tab?.canGoBack ?? false
            canGoForward = tab?.canGoForward ?? false
        }
    }
}

struct NavButtonsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @StateObject private var tabWrapper = ObservableTabWrapper()

    var body: some View {
        HStack(spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                Button("Go Back", systemImage: "arrow.backward", action: goBack)
                    .labelStyle(.iconOnly)
                    .buttonStyle(NavButtonStyle())
                    .disabled(!tabWrapper.canGoBack)
                    .sumiAppKitContextMenu(entries: {
                        NavigationHistoryContextMenuEntries.make(
                            historyType: .back,
                            windowState: windowState,
                            browserManager: browserManager
                        )
                    })

                Button("Go Forward", systemImage: "arrow.forward", action: goForward)
                    .labelStyle(.iconOnly)
                    .buttonStyle(NavButtonStyle())
                    .disabled(!tabWrapper.canGoForward)
                    .sumiAppKitContextMenu(entries: {
                        NavigationHistoryContextMenuEntries.make(
                            historyType: .forward,
                            windowState: windowState,
                            browserManager: browserManager
                        )
                    })

                Button("Reload", systemImage: "arrow.clockwise", action: refreshCurrentTab)
                    .labelStyle(.iconOnly)
                    .buttonStyle(NavButtonStyle())
            }
        }
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
    
    private func goBack() {
        if let tab = tabWrapper.tab,
           let webView = browserManager.getWebView(for: tab.id, in: windowState.id) {
            webView.goBack()
        } else {
            tabWrapper.tab?.goBack()
        }
    }
    
    private func goForward() {
        if let tab = tabWrapper.tab,
           let webView = browserManager.getWebView(for: tab.id, in: windowState.id) {
            webView.goForward()
        } else {
            tabWrapper.tab?.goForward()
        }
    }
    
    private func refreshCurrentTab() {
        tabWrapper.tab?.refresh()
    }
    
}
