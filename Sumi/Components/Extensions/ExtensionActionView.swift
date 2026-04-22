//
//  ExtensionActionView.swift
//  Sumi
//
//  Compatibility-only browser extension action strip.
//

import AppKit
import SwiftUI

enum ExtensionActionLayout {
    case compactStrip
    case hubTiles
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
    @EnvironmentObject var browserManager: BrowserManager
    
    var body: some View {
        switch layout {
        case .compactStrip:
            CompactExtensionActionStrip(
                extensions: extensions,
                visibleActionLimit: visibleActionLimit,
                extensionManager: browserManager.extensionManager
            )
            .environmentObject(browserManager)
        case .hubTiles:
            LazyVGrid(columns: hubTileColumns, alignment: .leading, spacing: 8) {
                if browserManager.sumiScriptsManager.isEnabled {
                    SumiScriptsToolbarControl(layout: .hubTile)
                        .environmentObject(browserManager)
                }

                ForEach(extensions.filter { $0.isEnabled }, id: \.id) { ext in
                    ExtensionActionButton(ext: ext, layout: .hubTiles)
                        .environmentObject(browserManager)
                }

                InstallExtensionTileButton()
                    .environmentObject(browserManager)
            }
        }
    }

    private var hubTileColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8),
            count: 4
        )
    }
}

@available(macOS 15.5, *)
private struct CompactExtensionActionStrip: View {
    let extensions: [InstalledExtension]
    let visibleActionLimit: Int?
    @ObservedObject var extensionManager: ExtensionManager
    @EnvironmentObject private var browserManager: BrowserManager

    var body: some View {
        HStack(spacing: 4) {
            ForEach(visiblePinnedSlots) { slot in
                switch slot {
                case .sumiScriptsManager:
                    SumiScriptsToolbarControl(layout: .compactStrip)
                        .environmentObject(browserManager)
                case .safariWebExtension(let ext):
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
        extensionManager.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            sumiScriptsManagerEnabled: browserManager.sumiScriptsManager.isEnabled
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

    private var sumiToolbarId: String { SumiScriptsToolbarConstants.nativeToolbarItemID }

    private var isPinnedToToolbar: Bool {
        browserManager.extensionManager.isPinnedToToolbar(sumiToolbarId)
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

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
            case .hubTile:
                Image(systemName: "curlybraces.square")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(tokens.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(hubBackgroundFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(tokens.separator.opacity(0.75), lineWidth: 0.5)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isPinnedToToolbar {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(tokens.primaryText.opacity(0.75))
                                .padding(6)
                        }
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
        SumiScriptsPopupView(
            manager: browserManager.sumiScriptsManager,
            currentURL: currentTab?.url,
            webView: currentTab.map {
                browserManager.getWebView(for: $0.id, in: windowState.id)
                    ?? $0.existingWebView
            } ?? nil
        )
    }

    private var hubBackgroundFill: some ShapeStyle {
        LinearGradient(
            colors: ThemeChromeRecipeBuilder.urlBarHubVeilGradientColors(
                tokens: tokens,
                isActive: false,
                isHovered: isHovering
            ),
            startPoint: .top,
            endPoint: .bottom
        )
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

    private func toggleSumiScriptsToolbarPin() {
        if isPinnedToToolbar {
            browserManager.extensionManager.unpinFromToolbar(sumiToolbarId)
        } else {
            browserManager.extensionManager.pinToToolbar(sumiToolbarId)
        }
    }

    private func sumiScriptsContextMenuEntries() -> [SidebarContextMenuEntry] {
        [
            .action(
                SidebarContextMenuAction(
                    title: isPinnedToToolbar ? "Unpin from Toolbar" : "Pin to Toolbar",
                    systemImage: isPinnedToToolbar ? "pin.slash" : "pin",
                    classification: .stateMutationNonStructural,
                    action: {
                        toggleSumiScriptsToolbarPin()
                    }
                )
            ),
            .separator,
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
        case .compactStrip:
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
struct ExtensionActionButton: View {
    let ext: InstalledExtension
    var layout: ExtensionActionLayout = .compactStrip
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovering: Bool = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            showExtensionPopup()
        }) {
            buttonLabel
        }
        .buttonStyle(.plain)
        .help(ext.name)
        .sumiAppKitContextMenu(entries: extensionContextMenuEntries)
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
                            extensionManager: browserManager.extensionManager
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            case .hubTiles:
                iconView(tint: tokens.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(hubBackgroundFill)
                    .background(
                        ActionAnchorView(
                            extensionId: ext.id,
                            extensionManager: browserManager.extensionManager
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(tokens.separator.opacity(0.75), lineWidth: 0.5)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isPinnedToToolbar {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(tokens.primaryText.opacity(0.75))
                                .padding(6)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .scaleEffect(hubButtonScale)
            }
        }
    }

    @ViewBuilder
    private func iconView(tint: Color) -> some View {
        if let iconPath = ext.iconPath,
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

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var hubBackgroundFill: some ShapeStyle {
        LinearGradient(
            colors: ThemeChromeRecipeBuilder.urlBarHubVeilGradientColors(
                tokens: tokens,
                isActive: false,
                isHovered: isHovering
            ),
            startPoint: .top,
            endPoint: .bottom
        )
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

    private var isPinnedToToolbar: Bool {
        browserManager.extensionManager.isPinnedToToolbar(ext.id)
    }

    private func showExtensionPopup() {
        browserManager.extensionManager.requestExtensionRuntime(
            reason: .extensionAction
        )

        guard let extensionContext = browserManager.extensionManager.getExtensionContext(for: ext.id) else {
            browserManager.showBrowserExtensionsUnavailableAlert(
                extensionName: ext.name
            )
            return
        }

        let currentTab = browserManager.currentTab(for: windowState)
        let adapter = currentTab.flatMap {
            browserManager.extensionManager.stableAdapter(for: $0)
        }
        extensionContext.performAction(for: adapter)
    }

    private func toggleToolbarPin() {
        if isPinnedToToolbar {
            browserManager.extensionManager.unpinFromToolbar(ext.id)
        } else {
            browserManager.extensionManager.pinToToolbar(ext.id)
        }
    }

    private func extensionContextMenuEntries() -> [SidebarContextMenuEntry] {
        [
            .action(
                SidebarContextMenuAction(
                    title: isPinnedToToolbar ? "Unpin from Toolbar" : "Pin to Toolbar",
                    systemImage: isPinnedToToolbar ? "pin.slash" : "pin",
                    classification: .stateMutationNonStructural,
                    action: {
                        toggleToolbarPin()
                    }
                )
            ),
            .separator,
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
            .action(
                SidebarContextMenuAction(
                    title: "Open Extension Action",
                    systemImage: "arrow.up.right.square",
                    classification: .presentationOnly,
                    action: {
                        showExtensionPopup()
                    }
                )
            ),
        ]
    }
}

@available(macOS 15.5, *)
private struct InstallExtensionTileButton: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovering = false
    @State private var isPressed = false

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        Button {
            browserManager.showExtensionInstallDialog()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tokens.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(backgroundFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(tokens.separator.opacity(0.75), lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .scaleEffect(buttonScale)
        }
        .buttonStyle(.plain)
        .help("Install Extension")
        .onHover { hovering in
            isHovering = hovering
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

    private var backgroundFill: some ShapeStyle {
        LinearGradient(
            colors: ThemeChromeRecipeBuilder.urlBarHubVeilGradientColors(
                tokens: tokens,
                isActive: false,
                isHovered: isHovering
            ),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var buttonScale: CGFloat {
        if isPressed && isHovering {
            return 0.97
        }
        if isHovering {
            return 1.03
        }
        return 1
    }
}

@available(macOS 15.5, *)
#Preview {
    ExtensionActionView(extensions: [])
}

@available(macOS 15.5, *)
private struct ActionAnchorView: NSViewRepresentable {
    let extensionId: String
    let extensionManager: ExtensionManager

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [extensionManager] in
            extensionManager.setActionAnchor(for: extensionId, anchorView: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [extensionManager] in
            extensionManager.setActionAnchor(for: extensionId, anchorView: nsView)
        }
    }
}
