//
//  URLBarView.swift
//  Sumi
//
//  Canonical Sumi browser URL bar hosted from the sidebar shell.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

enum URLBarPresentationMode {
    case sidebar
    case topBar

    var height: CGFloat {
        switch self {
        case .sidebar: 36
        case .topBar: 30
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .sidebar: 12
        case .topBar: 8
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .sidebar: 12
        case .topBar: 13
        }
    }
}

struct URLBarView: View {
    @EnvironmentObject var glanceManager: GlanceManager
    @EnvironmentObject var extensionSurfaceStore: BrowserExtensionSurfaceStore
    @Environment(BrowserWindowState.self) var windowState
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) var themeContext

    let browserContext: URLBarBrowserContext
    let presentationMode: URLBarPresentationMode

    @State var isHovering = false
    @State var showCheckmark = false
    @State var isZoomPopoverPresented = false
    @State var zoomPopoverSource: ZoomPopoverSource = .toolbar
    @State var zoomPopoverSize = CGSize(width: 252, height: 48)
    @State var isZoomButtonHovering = false
    @State var isZoomPopoverHovering = false
    @State var zoomPopoverHideTask: Task<Void, Never>?
    @State var isPermissionIndicatorPopoverPresented = false
    @StateObject var permissionIndicatorViewModel = SumiPermissionIndicatorViewModel()
    @StateObject var permissionPromptPresenter = SumiPermissionPromptPresenter()
    @StateObject var permissionRuntimeControlsModel = SumiPermissionRuntimeControlsViewModel()

    init(
        browserContext: URLBarBrowserContext,
        presentationMode: URLBarPresentationMode = .sidebar
    ) {
        self.browserContext = browserContext
        self.presentationMode = presentationMode
    }

    var body: some View {
        let cornerRadius = sumiSettings.resolvedCornerRadius(
            presentationMode.cornerRadius
        )

        VStack(alignment: .leading, spacing: presentationMode == .sidebar ? 6 : 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    leadingContent
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: focusFloatingBarFromURLBar)
                .sidebarAppKitPrimaryAction(action: focusFloatingBarFromURLBar)

                if let currentTab = currentTab {
                    trailingActions(for: currentTab)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(
                maxWidth: .infinity,
                minHeight: presentationMode.height,
                maxHeight: presentationMode.height
            )
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: URLBarFramePreferenceKey.self,
                        value: proxy.frame(in: .named("WindowSpace"))
                    )
                }
            )
            .contentShape(Rectangle())
            .accessibilityIdentifier(
                presentationMode == .sidebar
                    ? "sidebar-urlbar"
                    : "topbar-urlbar"
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHovering = hovering
                }
            }
        }
        .onChange(of: browserContext.zoom.popoverRequest) { _, request in
            handleZoomPopoverRequest(request)
        }
        .onChange(of: browserContext.bookmarkEditorPresentationRequest) { _, request in
            handleBookmarkEditorPresentationRequest(request)
        }
        .onChange(of: currentTab?.id) { _, _ in
            DispatchQueue.main.async {
                closeZoomPopover()
                closePermissionIndicatorPopover()
                browserContext.closeURLBarHubPopover(windowState)
                permissionPromptPresenter.closeForCurrentTabChange()
            }
        }
        .onChange(of: currentTab?.url) { _, url in
            if let url, SumiSurface.isSettingsSurfaceURL(url) || SumiSurface.isHistorySurfaceURL(url) || SumiSurface.isBookmarksSurfaceURL(url) {
                DispatchQueue.main.async {
                    closeZoomPopover()
                    closePermissionIndicatorPopover()
                    browserContext.closeURLBarHubPopover(windowState)
                }
            }
        }
        .onChange(of: permissionPromptPresenter.isPresented) { _, isPresented in
            if isPresented {
                closePermissionIndicatorPopover()
                browserContext.closeURLBarHubPopover(windowState)
            }
        }
        .onDisappear {
            cancelZoomPopoverHideTask()
            closePermissionIndicatorPopover()
            browserContext.closeURLBarHubPopover(windowState)
            permissionPromptPresenter.clear()
        }
    }

    var currentTab: Tab? {
        if let glanceTab = glanceManager.activePreviewTab(for: windowState) {
            return glanceTab
        }

        let currentTabId = windowState.currentTabId
        if windowState.isIncognito {
            return windowState.ephemeralTabs.first { $0.id == currentTabId }
        }
        guard let currentTabId else { return nil }
        return browserContext.tabForID(currentTabId)
            ?? browserContext.currentTab(windowState)
    }

    var activePageURL: URL? {
        glanceManager.activeSession(for: windowState)?.currentURL
            ?? currentTab?.url
    }

    func focusFloatingBarFromURLBar() {
        let currentURL = ExtensionUtils.isExtensionOwnedURL(activePageURL)
            ? ""
            : activePageURL?.absoluteString ?? ""
        browserContext.focusFloatingBar(windowState, currentURL, true)
    }

    var effectiveProfileId: UUID? {
        windowState.currentProfileId ?? browserContext.currentProfile()?.id
    }

    var effectiveProfile: Profile? {
        if let profile = currentTab?.resolveProfile() {
            return profile
        }
        if let profileId = effectiveProfileId,
           let profile = browserContext.profiles().first(where: { $0.id == profileId }) {
            return profile
        }
        return browserContext.currentProfile()
    }

    var siteControlsSnapshot: SiteControlsSnapshot {
        browserContext.siteControlsSnapshot(
            activePageURL,
            effectiveProfile,
            currentTab?.isProtectionReloadRequired == true,
            currentTab?.isSafariContentBlockerReloadRequired == true
        )
    }
}
