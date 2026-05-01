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

enum URLBarHubInitialMode {
    case controls
    case permissions
}

struct URLBarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) var windowState
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(\.resolvedThemeContext) var themeContext

    let presentationMode: URLBarPresentationMode

    @State var isHovering = false
    @State var showCheckmark = false
    @State var isHubPresented = false
    @State var hubInitialMode: URLBarHubInitialMode = .controls
    @State var hubModeRequestNonce = 0
    @State var isZoomPopoverPresented = false
    @State var zoomPopoverSource: ZoomPopoverSource = .toolbar
    @State var zoomPopoverSize = CGSize(width: 252, height: 48)
    @State var isZoomButtonHovering = false
    @State var isZoomPopoverHovering = false
    @State var zoomPopoverHideTask: Task<Void, Never>?
    @State var didConfigurePermissionIndicator = false
    @State var didConfigurePermissionPrompt = false
    @StateObject var permissionIndicatorViewModel = SumiPermissionIndicatorViewModel()
    @StateObject var permissionPromptPresenter = SumiPermissionPromptPresenter()

    init(
        presentationMode: URLBarPresentationMode = .sidebar
    ) {
        self.presentationMode = presentationMode
    }

    var body: some View {
        let cornerRadius = sumiSettings.resolvedCornerRadius(
            presentationMode.cornerRadius
        )

        VStack(alignment: .leading, spacing: presentationMode == .sidebar ? 6 : 0) {
            HStack(spacing: 8) {
                leadingContent
                Spacer(minLength: 8)

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
            .onTapGesture {
                guard !isZoomButtonHovering else { return }
                let currentURL = currentTab?.url.absoluteString ?? ""
                browserManager.openCommandPalette(
                    in: windowState,
                    reason: .keyboard,
                    prefill: currentURL,
                    navigateCurrentTab: true
                )
            }
        }
        .onChange(of: browserManager.zoomPopoverRequest) { _, request in
            handleZoomPopoverRequest(request)
        }
        .onChange(of: browserManager.bookmarkEditorPresentationRequest) { _, request in
            handleBookmarkEditorPresentationRequest(request)
        }
        .onChange(of: currentTab?.id) { _, _ in
            DispatchQueue.main.async {
                closeZoomPopover()
                isHubPresented = false
                permissionPromptPresenter.closeForCurrentTabChange()
            }
        }
        .onChange(of: permissionPromptPresenter.isPresented) { _, isPresented in
            if isPresented {
                isHubPresented = false
            }
        }
        .onDisappear {
            cancelZoomPopoverHideTask()
            isHubPresented = false
            permissionPromptPresenter.clear()
        }
    }

    var currentTab: Tab? {
        let currentTabId = windowState.currentTabId
        if windowState.isIncognito {
            return windowState.ephemeralTabs.first { $0.id == currentTabId }
        }
        guard let currentTabId else { return nil }
        return browserManager.tabManager.tab(for: currentTabId)
            ?? browserManager.currentTab(for: windowState)
    }

    var effectiveProfileId: UUID? {
        windowState.currentProfileId ?? browserManager.currentProfile?.id
    }

    var effectiveProfile: Profile? {
        if let profile = currentTab?.resolveProfile() {
            return profile
        }
        if let profileId = effectiveProfileId,
           let profile = browserManager.profileManager.profiles.first(where: { $0.id == profileId }) {
            return profile
        }
        return browserManager.currentProfile
    }

    var siteControlsSnapshot: SiteControlsSnapshot {
        SiteControlsSnapshot.resolve(
            url: currentTab?.url,
            profile: effectiveProfile,
            showsAutoplayPermission: currentTab?.audioState.isPlayingAudio == true
        )
    }

}
