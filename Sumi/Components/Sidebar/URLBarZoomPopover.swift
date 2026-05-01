//
//  URLBarZoomPopover.swift
//  Sumi
//
//  Canonical Sumi browser URL bar hosted from the sidebar shell.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension URLBarView {
    func zoomButton(for currentTab: Tab) -> some View {
        let action = {
            toggleZoomPopoverFromToolbar(for: currentTab)
        }

        return Button(action: action) {
            Image(zoomButtonImageName(for: currentTab))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
        }
        .buttonStyle(URLBarButtonStyle())
        .help("Zoom")
        .sidebarAppKitPrimaryAction(action: action)
        .onHover { hovering in
            isZoomButtonHovering = hovering
            updateZoomPopoverAutoCloseTask()
        }
        .popover(isPresented: $isZoomPopoverPresented, arrowEdge: .bottom) {
            URLBarZoomPopoverView(
                currentTab: currentTab,
                onMouseOverChange: { hovering in
                    isZoomPopoverHovering = hovering
                    updateZoomPopoverAutoCloseTask()
                }
            )
            .environmentObject(browserManager)
            .environment(windowState)
            .frame(width: zoomPopoverSize.width, height: zoomPopoverSize.height)
            .onDisappear {
                cancelZoomPopoverHideTask()
                isZoomPopoverHovering = false
            }
        }
    }

    func shouldShowZoomButton(for tab: Tab) -> Bool {
        _ = browserManager.zoomStateRevision
        return URLBarZoomButtonVisibility.shouldShow(
            hasURL: isZoomButtonURLAvailable(for: tab),
            isEditing: windowState.isCommandPaletteVisible,
            isPopoverPresented: isZoomPopoverPresented,
            isDefaultZoom: browserManager.zoomManager.isDefaultZoom(for: tab.id)
        )
    }

    func isZoomButtonURLAvailable(for tab: Tab) -> Bool {
        tab.url.scheme?.isEmpty == false
    }

    func zoomButtonImageName(for tab: Tab) -> String {
        _ = browserManager.zoomStateRevision
        return browserManager.zoomManager.getZoomLevel(for: tab.id) < 1.0 ? "ZoomOut" : "ZoomIn"
    }

    func toggleZoomPopoverFromToolbar(for tab: Tab) {
        isHubPresented = false
        zoomPopoverSource = .toolbar
        if isZoomPopoverPresented {
            closeZoomPopover()
        } else {
            isZoomPopoverPresented = true
            browserManager.requestZoomPopover(for: tab, in: windowState, source: .toolbar)
            updateZoomPopoverAutoCloseTask()
        }
    }

    func handleZoomPopoverRequest(_ request: ZoomPopoverRequest?) {
        guard let request,
              request.windowId == windowState.id,
              request.tabId == currentTab?.id
        else { return }

        isHubPresented = false
        zoomPopoverSource = request.source
        isZoomPopoverPresented = true
        updateZoomPopoverAutoCloseTask()
    }

    func updateZoomPopoverAutoCloseTask() {
        cancelZoomPopoverHideTask()
        guard isZoomPopoverPresented,
              let interval = zoomPopoverSource.autoCloseInterval,
              !isZoomButtonHovering,
              !isZoomPopoverHovering
        else { return }

        let delay = UInt64(max(interval, 0) * 1_000_000_000)
        zoomPopoverHideTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            closeZoomPopover()
        }
    }

    func closeZoomPopover() {
        cancelZoomPopoverHideTask()
        isZoomPopoverPresented = false
        isZoomPopoverHovering = false
    }

    func cancelZoomPopoverHideTask() {
        zoomPopoverHideTask?.cancel()
        zoomPopoverHideTask = nil
    }

}

struct URLBarZoomButtonVisibility {
    static func shouldShow(
        hasURL: Bool,
        isEditing: Bool,
        isPopoverPresented: Bool,
        isDefaultZoom: Bool
    ) -> Bool {
        hasURL && !isEditing && (!isDefaultZoom || isPopoverPresented)
    }
}

private struct URLBarZoomPopoverView: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    let currentTab: Tab
    let onMouseOverChange: (Bool) -> Void

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        let zoomManager = browserManager.zoomManager
        let tabId = currentTab.id
        let _ = browserManager.zoomStateRevision

        HStack(spacing: 0) {
            Text(zoomManager.getZoomPercentageDisplay(for: tabId))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tokens.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(width: 69)
                .padding(.leading, 16)

            Button("Reset") {
                browserManager.resetZoomCurrentTab(in: windowState)
            }
            .buttonStyle(URLBarZoomPopoverButtonStyle(minWidth: 59))
            .help("Reset Zoom")
            .padding(.leading, 8)

            Button("Zoom Out", systemImage: "minus") {
                browserManager.zoomOutCurrentTab(in: windowState)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(URLBarZoomPopoverButtonStyle(width: 37))
            .help("Zoom Out")
            .disabled(zoomManager.isAtMinimumZoom(for: tabId))
            .padding(.leading, 8)

            Button("Zoom In", systemImage: "plus") {
                browserManager.zoomInCurrentTab(in: windowState)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(URLBarZoomPopoverButtonStyle(width: 37))
            .help("Zoom In")
            .disabled(zoomManager.isAtMaximumZoom(for: tabId))
            .padding(.leading, 1)
            .padding(.trailing, 16)
        }
        .frame(height: 48)
        .background(tokens.commandPaletteBackground)
        .onHover(perform: onMouseOverChange)
    }
}

struct URLBarZoomPopoverButtonStyle: ButtonStyle {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let width: CGFloat?
    let minWidth: CGFloat?

    init(width: CGFloat? = nil, minWidth: CGFloat? = nil) {
        self.width = width
        self.minWidth = minWidth
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(tokens.primaryText)
            .padding(.horizontal, width == nil ? 12 : 0)
            .frame(width: width, height: 28)
            .frame(minWidth: minWidth, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        ThemeChromeRecipeBuilder.urlBarPillFieldBackground(
            tokens: tokens,
            isPressed: isPressed,
            isHovering: isHovering,
            isEnabled: isEnabled
        )
    }
}
