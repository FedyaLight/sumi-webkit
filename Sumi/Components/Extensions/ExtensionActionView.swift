//
//  ExtensionActionView.swift
//  Sumi
//
//  Browser extension action strip.
//

import AppKit
import SwiftUI

enum ExtensionActionLayout {
    case compactStrip
    case sidebarGrid
    case hubTiles
}

enum ExtensionActionPlacement: Equatable {
    case hidden
    case urlBar
    case sidebarGrid

    static let sidebarGridThreshold = 3

    static func resolve(totalActions: Int) -> Self {
        if totalActions <= 0 {
            return .hidden
        }
        if totalActions >= sidebarGridThreshold {
            return .sidebarGrid
        }
        return .urlBar
    }
}

enum ExtensionActionVisibility {
    static func visibleCount(
        totalActions: Int,
        availableWidth: CGFloat,
        buttonWidth: CGFloat = 28,
        spacing: CGFloat = 4
    ) -> Int {
        guard totalActions > 0,
              availableWidth >= buttonWidth,
              buttonWidth > 0
        else {
            return 0
        }

        let availableSlots = Int(floor((availableWidth + spacing) / (buttonWidth + spacing)))
        return min(totalActions, max(0, availableSlots))
    }
}

@MainActor
final class ExtensionIconCache {
    static let shared = ExtensionIconCache()

    typealias Key = String

    private struct Entry {
        let modificationDate: Date?
        let image: NSImage
    }

    private static let maxEntries = 128
    var imageLoader: (String) -> NSImage? = { path in
        NSImage(contentsOfFile: path)
    }

    private var entries: [Key: Entry] = [:]
    private var entryOrder: [Key] = []

    func image(extensionId: String, iconPath: String) -> NSImage? {
        let key = Self.cacheKey(extensionId: extensionId, iconPath: iconPath)
        let modificationDate = Self.modificationDate(for: iconPath)

        if let entry = entries[key],
           entry.modificationDate == modificationDate
        {
            touch(key)
            return entry.image
        }

        guard let image = imageLoader(iconPath) else {
            entries.removeValue(forKey: key)
            entryOrder.removeAll { $0 == key }
            return nil
        }

        entries[key] = Entry(
            modificationDate: modificationDate,
            image: image
        )
        touch(key)
        evictIfNeeded()
        return image
    }

    private func touch(_ key: Key) {
        entryOrder.removeAll { $0 == key }
        entryOrder.append(key)
    }

    private func evictIfNeeded() {
        while entries.count > Self.maxEntries, let key = entryOrder.first {
            entryOrder.removeFirst()
            entries.removeValue(forKey: key)
        }
    }

    private static func cacheKey(extensionId: String, iconPath: String) -> Key {
        "\(extensionId)\u{0}\(iconPath)"
    }

    private static func modificationDate(for path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate])
            as? Date
    }
}

@available(macOS 15.5, *)
struct ExtensionActionView: View {
    let extensions: [InstalledExtension]
    var layout: ExtensionActionLayout = .compactStrip
    var visibleActionLimit: Int? = nil
    var profileId: UUID? = nil
    @EnvironmentObject var browserManager: BrowserManager
    
    var body: some View {
        switch layout {
        case .compactStrip:
            CompactExtensionActionStrip(
                extensions: extensions,
                visibleActionLimit: visibleActionLimit
            )
            .environmentObject(browserManager)
        case .sidebarGrid:
            SidebarExtensionActionGrid(
                extensions: extensions,
                profileId: profileId
            )
                .environmentObject(browserManager)
        case .hubTiles:
            LazyVGrid(columns: hubTileColumns, alignment: .leading, spacing: 8) {
                if browserManager.userscriptsModule.isEnabled {
                    SumiScriptsToolbarControl(layout: .hubTile)
                        .environmentObject(browserManager)
                }

                ForEach(hubExtensions, id: \.id) { ext in
                    ExtensionActionButton(ext: ext, layout: .hubTiles)
                        .environmentObject(browserManager)
                }

            }
        }
    }

    private var hubTileColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8),
            count: 4
        )
    }

    private var hubExtensions: [InstalledExtension] {
        extensions
            .filter { $0.isEnabled && $0.hasAction }
            .filter { browserManager.extensionsModule.isPinnedToToolbar($0.id) == false }
    }
}

@available(macOS 15.5, *)
private struct SidebarExtensionActionGrid: View {
    let extensions: [InstalledExtension]
    let profileId: UUID?
    @EnvironmentObject private var browserManager: BrowserManager

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(pinnedSlots) { slot in
                switch slot {
                case .sumiScriptsManager:
                    SumiScriptsToolbarControl(layout: .sidebarGrid)
                        .environmentObject(browserManager)
                case .webExtension(let ext):
                    ExtensionActionButton(
                        ext: ext,
                        layout: .sidebarGrid,
                        profileId: profileId
                    )
                        .environmentObject(browserManager)
                }
            }
        }
        .padding(.horizontal, 2)
        .accessibilityIdentifier("sidebar-extension-action-grid")
    }

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 32, maximum: .infinity),
                spacing: 8,
                alignment: .center
            ),
        ]
    }

    private var enabledExtensions: [InstalledExtension] {
        extensions.filter { $0.isEnabled }
    }

    private var pinnedSlots: [PinnedToolbarSlot] {
        browserManager.extensionsModule.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            sumiScriptsManagerEnabled: browserManager.userscriptsModule.isEnabled,
            profileId: profileId
        )
    }
}

@available(macOS 15.5, *)
private struct CompactExtensionActionStrip: View {
    let extensions: [InstalledExtension]
    let visibleActionLimit: Int?
    @EnvironmentObject private var browserManager: BrowserManager

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visiblePinnedSlots) { slot in
                switch slot {
                case .sumiScriptsManager:
                    SumiScriptsToolbarControl(layout: .compactStrip)
                        .environmentObject(browserManager)
                case .webExtension(let ext):
                    ExtensionActionButton(ext: ext, layout: .compactStrip)
                        .environmentObject(browserManager)
                }
            }
        }
    }

    private var enabledExtensions: [InstalledExtension] {
        extensions.filter { $0.isEnabled }
    }

    private var compactLimit: Int {
        visibleActionLimit ?? Int.max
    }

    private var pinnedSlots: [PinnedToolbarSlot] {
        browserManager.extensionsModule.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            sumiScriptsManagerEnabled: browserManager.userscriptsModule.isEnabled
        )
    }

    private var visiblePinnedSlots: [PinnedToolbarSlot] {
        Array(pinnedSlots.prefix(compactLimit))
    }
}

// MARK: - Native SumiScripts toolbar control

@available(macOS 15.5, *)
private enum SumiScriptsToolbarLayout {
    case compactStrip
    case sidebarGrid
    case hubTile
}

@available(macOS 15.5, *)
private struct SumiScriptsToolbarControl: View {
    let layout: SumiScriptsToolbarLayout

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovering = false
    @State private var isPressed = false
    @State private var showingPopup = false

    var body: some View {
        Button {
            showingPopup.toggle()
        } label: {
            switch layout {
            case .compactStrip:
                Image(systemName: "curlybraces.square")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .padding(6)
                    .background(isHovering ? .white.opacity(0.1) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            case .sidebarGrid:
                Image(systemName: "curlybraces.square")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .padding(5)
                    .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
                    .background(sidebarGridBackgroundFill)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            case .hubTile:
                Image(systemName: "curlybraces.square")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(URLBarHubNativeStyle.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(hubBackgroundFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(URLBarHubNativeStyle.separator, lineWidth: 0.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .scaleEffect(hubButtonScale)
            }
        }
        .buttonStyle(.plain)
        .help("SumiScripts")
        .popover(isPresented: $showingPopup, arrowEdge: .bottom) {
            sumiScriptsPopover
        }
        .sumiAppKitContextMenu(entries: sumiScriptsContextMenuEntries)
        .onHover { hovering in
            isHovering = hovering
        }
        .modifier(HubTilePressGestureModifier(layout: layout, isPressed: $isPressed))
    }

    @ViewBuilder
    private var sumiScriptsPopover: some View {
        let currentTab = browserManager.currentTab(for: windowState)
        if let manager = browserManager.userscriptsModule.managerIfEnabled() {
            SumiScriptsPopupView(
                manager: manager,
                currentURL: currentTab?.url,
                webView: currentTab.map {
                    browserManager.getWebView(for: $0.id, in: windowState.id)
                        ?? $0.existingWebView
                } ?? nil
            )
        }
    }

    private var hubBackgroundFill: Color {
        isHovering ? URLBarHubNativeStyle.hoveredControlBackground : URLBarHubNativeStyle.controlBackground
    }

    private var sidebarGridBackgroundFill: Color {
        isHovering ? tokens.pinnedHoverBackground : tokens.pinnedIdleBackground
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var hubButtonScale: CGFloat {
        if isPressed && isHovering {
            return 0.97
        }
        if isHovering {
            return 1.03
        }
        return 1
    }

    private func sumiScriptsContextMenuEntries() -> [SidebarContextMenuEntry] {
        [
            .action(
                SidebarContextMenuAction(
                    title: "Manage Userscripts",
                    systemImage: "gearshape",
                    classification: .presentationOnly,
                    action: {
                        browserManager.openSettingsTab(selecting: .userScripts, in: windowState)
                    }
                )
            ),
        ]
    }
}

@available(macOS 15.5, *)
private struct HubTilePressGestureModifier: ViewModifier {
    let layout: SumiScriptsToolbarLayout
    @Binding var isPressed: Bool

    func body(content: Content) -> some View {
        switch layout {
        case .compactStrip, .sidebarGrid:
            content
        case .hubTile:
            content
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            isPressed = true
                        }
                        .onEnded { _ in
                            isPressed = false
                        }
                )
        }
    }
}

@available(macOS 15.5, *)
private struct ExtensionActionContextMenuModifier: ViewModifier {
    let layout: ExtensionActionLayout
    let entries: () -> [SidebarContextMenuEntry]

    func body(content: Content) -> some View {
        switch layout {
        case .sidebarGrid:
            content
        case .compactStrip, .hubTiles:
            content.sumiAppKitContextMenu(entries: entries)
        }
    }
}

@available(macOS 15.5, *)
struct ExtensionActionButton: View {
    let ext: InstalledExtension
    var layout: ExtensionActionLayout = .compactStrip
    var profileId: UUID? = nil
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject private var extensionSurfaceStore:
        BrowserExtensionSurfaceStore
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovering: Bool = false
    @State private var isPressed = false
    
    var body: some View {
        Group {
            if layout == .sidebarGrid {
                buttonLabel
                    .sidebarAppKitContextMenu(
                        surfaceKind: .button,
                        primaryAction: showExtensionPopup,
                        entries: extensionContextMenuEntries
                    )
            } else {
                Button(action: {
                    showExtensionPopup()
                }) {
                    buttonLabel
                }
                .buttonStyle(.plain)
            }
        }
        .help(actionTitle)
        .disabled(actionState?.isEnabled == false)
        .opacity(actionState?.isEnabled == false ? 0.55 : 1)
        .modifier(ExtensionActionContextMenuModifier(
            layout: layout,
            entries: extensionContextMenuEntries
        ))
        .onHover { state in
            isHovering = state
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isPressed = true
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }

    private var buttonLabel: some View {
        Group {
            switch layout {
            case .compactStrip:
                iconView(tint: .white)
                    .frame(width: 16, height: 16)
                    .padding(6)
                    .background(isHovering ? .white.opacity(0.1) : .clear)
                    .background(
                        ActionAnchorView(
                            extensionId: ext.id,
                            extensionsModule: browserManager.extensionsModule
                        )
                        .allowsHitTesting(false)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(alignment: .topTrailing) {
                        actionBadgeView
                    }
            case .sidebarGrid:
                iconView(tint: URLBarHubNativeStyle.primaryText)
                    .frame(width: 16, height: 16)
                    .padding(5)
                    .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
                    .background(sidebarGridBackgroundFill)
                    .background(
                        ActionAnchorView(
                            extensionId: ext.id,
                            extensionsModule: browserManager.extensionsModule
                        )
                        .allowsHitTesting(false)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if let badgeText = visibleBadgeText {
                            actionBadge(badgeText)
                                .padding(2)
                        }
                    }
            case .hubTiles:
                iconView(tint: URLBarHubNativeStyle.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(hubBackgroundFill)
                    .background(
                        ActionAnchorView(
                            extensionId: ext.id,
                            extensionsModule: browserManager.extensionsModule
                        )
                        .allowsHitTesting(false)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(URLBarHubNativeStyle.separator, lineWidth: 0.5)
                    }
                    .overlay(alignment: .topTrailing) {
                        if let badgeText = visibleBadgeText {
                            actionBadge(badgeText)
                                .padding(3)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .scaleEffect(hubButtonScale)
            }
        }
    }

    @ViewBuilder
    private func iconView(tint: Color) -> some View {
        if let actionIcon = actionState?.icon {
            Image(nsImage: actionIcon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else if let iconPath = ext.iconPath,
           let nsImage = ExtensionIconCache.shared.image(
               extensionId: ext.id,
               iconPath: iconPath
           )
        {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 16, height: 16)
        }
    }

    @ViewBuilder
    private var actionBadgeView: some View {
        if let badgeText = visibleBadgeText {
            actionBadge(badgeText)
                .offset(x: 4, y: -4)
        }
    }

    private func actionBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 3)
            .frame(minWidth: 10, minHeight: 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.red.opacity(actionState?.hasUnreadBadgeText == true ? 0.95 : 0.78))
            )
    }

    private var actionState: BrowserExtensionActionSurfaceState? {
        extensionSurfaceStore.actionStatesByExtensionID[ext.id]
    }

    private var actionTitle: String {
        guard let label = actionState?.label
            .trimmingCharacters(in: .whitespacesAndNewlines),
            label.isEmpty == false
        else {
            return ext.name
        }
        return label
    }

    private var visibleBadgeText: String? {
        guard let badgeText = actionState?.badgeText
            .trimmingCharacters(in: .whitespacesAndNewlines),
            badgeText.isEmpty == false
        else {
            return nil
        }
        return String(badgeText.prefix(4))
    }

    private var hubBackgroundFill: Color {
        isHovering ? URLBarHubNativeStyle.hoveredControlBackground : URLBarHubNativeStyle.controlBackground
    }

    private var sidebarGridBackgroundFill: Color {
        isHovering ? tokens.pinnedHoverBackground : tokens.pinnedIdleBackground
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var hubButtonScale: CGFloat {
        if isPressed && isHovering {
            return 0.97
        }
        if isHovering {
            return 1.03
        }
        return 1
    }

    private func showExtensionPopup() {
        Task { @MainActor in
            let currentTab = await currentExtensionActionTabForClick()
            let profileId =
                currentTab?.profileId
                ?? windowState.currentProfileId
                ?? browserManager.currentProfile?.id
            browserManager.extensionsModule.captureActionPopupAnchor(
                extensionId: ext.id,
                windowId: windowState.id,
                profileId: profileId
            )
            let result = await browserManager.extensionsModule
                .openActionPopupFromURLHub(
                    extensionId: ext.id,
                    currentTab: currentTab
                )
            guard result.opened == false else { return }
            browserManager.showBrowserExtensionsUnavailableAlert(
                extensionName: ext.name,
                informativeText: result.message
            )
        }
    }

    @MainActor
    private func currentExtensionActionTabForClick() async -> Tab? {
        if let currentTab = currentExtensionActionTab {
            return currentTab
        }

        guard windowState.isAwaitingInitialSessionResolution
                || !browserManager.tabManager.hasLoadedInitialData
        else {
            return nil
        }

        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let currentTab = currentExtensionActionTab {
                return currentTab
            }
            if !windowState.isAwaitingInitialSessionResolution
                && browserManager.tabManager.hasLoadedInitialData
            {
                return nil
            }
        }
        return currentExtensionActionTab
    }

    private var currentExtensionActionTab: Tab? {
        browserManager.currentTab(for: windowState)
            ?? windowState.currentTabId.flatMap { browserManager.tabManager.tab(for: $0) }
            ?? browserManager.shellSelectionService.currentTab(
                for: windowState,
                tabStore: browserManager.tabManager.runtimeStore
            )
            ?? browserManager.windowRegistry?.activeWindow.flatMap {
                browserManager.currentTab(for: $0)
                    ?? browserManager.shellSelectionService.currentTab(
                        for: $0,
                        tabStore: browserManager.tabManager.runtimeStore
                    )
            }
            ?? browserManager.tabManager.currentTab
    }

    private func extensionContextMenuEntries() -> [SidebarContextMenuEntry] {
        var entries: [SidebarContextMenuEntry] = [
            .action(
                SidebarContextMenuAction(
                    title: "Manage Extensions",
                    systemImage: "gearshape",
                    classification: .presentationOnly,
                    action: {
                        browserManager.openSettingsTab(selecting: .extensions, in: windowState)
                    }
                )
            ),
        ]

        switch layout {
        case .hubTiles:
            entries.append(
                .action(
                    SidebarContextMenuAction(
                        title: "Pin to Toolbar",
                        systemImage: "pin",
                        classification: .presentationOnly,
                        action: {
                            browserManager.extensionsModule.pinToToolbar(ext.id)
                        }
                    )
                )
            )
        case .compactStrip, .sidebarGrid:
            entries.append(
                .action(
                    SidebarContextMenuAction(
                        title: "Unpin from Toolbar",
                        systemImage: "pin.slash",
                        classification: .presentationOnly,
                        action: {
                            browserManager.extensionsModule.unpinFromToolbar(ext.id)
                        }
                    )
                )
            )
        }

        if ext.hasOptionsPage {
            entries.append(
                .action(
                    SidebarContextMenuAction(
                        title: "Options",
                        systemImage: "slider.horizontal.3",
                        classification: .presentationOnly,
                        action: {
                            Task { @MainActor in
                                await browserManager.extensionsModule.openOptionsPage(
                                    extensionId: ext.id,
                                    profileId: extensionActionProfileId
                                )
                            }
                        }
                    )
                )
            )
        }

        return entries
    }

    private var extensionActionProfileId: UUID? {
        profileId
            ?? currentExtensionActionTab?.profileId
            ?? windowState.currentProfileId
            ?? browserManager.currentProfile?.id
    }
}

@available(macOS 15.5, *)
#Preview {
    ExtensionActionView(extensions: [])
}

@available(macOS 15.5, *)
private struct ActionAnchorView: NSViewRepresentable {
    let extensionId: String
    let extensionsModule: SumiExtensionsModule

    func makeNSView(context: Context) -> NSView {
        let view = ActionAnchorHostView(frame: .zero)
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let nsView = nsView as? ActionAnchorHostView else { return }
        configure(nsView)
    }

    private func configure(_ view: ActionAnchorHostView) {
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]
        view.extensionId = extensionId
        view.extensionsModule = extensionsModule
        view.registerAnchor()
    }
}

@available(macOS 15.5, *)
private final class ActionAnchorHostView: NSView {
    var extensionId: String?
    weak var extensionsModule: SumiExtensionsModule?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerAnchor()
    }

    func registerAnchor() {
        guard let extensionId, let extensionsModule else { return }
        extensionsModule.setActionAnchorIfLoaded(
            for: extensionId,
            anchorView: self
        )
    }
}
