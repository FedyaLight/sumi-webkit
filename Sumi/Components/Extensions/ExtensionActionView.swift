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

@MainActor
final class ExtensionIconCache {
    static let shared = ExtensionIconCache()

    typealias Key = String

    private struct Entry {
        let modificationDate: Date?
        let image: NSImage
        var lastChecked: Double
    }

    private static let maxEntries = 128
    var imageLoader: (String) -> NSImage? = { path in
        NSImage(contentsOfFile: path)
    }

    private var entries: [Key: Entry] = [:]
    private var entryOrder: [Key] = []

    func image(extensionId: String, iconPath: String) -> NSImage? {
        let key = Self.cacheKey(extensionId: extensionId, iconPath: iconPath)
        let now = Date.timeIntervalSinceReferenceDate

        if var entry = entries[key] {
            if now - entry.lastChecked < 5.0 {
                touch(key)
                return entry.image
            }

            let modificationDate = Self.modificationDate(for: iconPath)
            if entry.modificationDate == modificationDate {
                entry.lastChecked = now
                entries[key] = entry
                touch(key)
                return entry.image
            }
        }

        let modificationDate = Self.modificationDate(for: iconPath)
        guard let image = imageLoader(iconPath) else {
            entries.removeValue(forKey: key)
            entryOrder.removeAll { $0 == key }
            return nil
        }

        entries[key] = Entry(
            modificationDate: modificationDate,
            image: image,
            lastChecked: now
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
    var visibleActionLimit: Int?
    var profileId: UUID?
    let browserContext: ExtensionActionBrowserContext

    var body: some View {
        switch layout {
        case .compactStrip:
            CompactExtensionActionStrip(
                extensions: extensions,
                visibleActionLimit: visibleActionLimit,
                browserContext: browserContext
            )
        case .sidebarGrid:
            SidebarExtensionActionGrid(
                extensions: extensions,
                profileId: profileId,
                browserContext: browserContext
            )
        case .hubTiles:
            HubExtensionTilesGrid(
                extensions: extensions,
                profileId: profileId,
                browserContext: browserContext
            )
        }
    }
}

@available(macOS 15.5, *)
private struct HubExtensionTilesGrid: View {
    let extensions: [InstalledExtension]
    let profileId: UUID?
    let browserContext: ExtensionActionBrowserContext

    @State private var reorder = ReorderDragState<String>()
    @State private var frames = ReorderFrameStore()
    @State private var lastDropAt = Date.distantPast

    private static let axis: ReorderAxis = .grid
    private static let spacing: CGFloat = 8
    private static let coordinateSpaceName = "hub-extension-reorder"

    var body: some View {
        let base = hubExtensions
        let baseIDs = base.map(\.id)
        let displayed = reorder.displayOrder(base, id: \.id)

        LazyVGrid(columns: columns, alignment: .leading, spacing: Self.spacing) {
            if browserContext.userscriptsModule.isEnabled {
                SumiScriptsToolbarControl(layout: .hubTile, browserContext: browserContext)
                    .sumiAppKitContextMenu(entries: {
                        sumiScriptsToolbarMenuEntries(browserContext: browserContext)
                    })
            }

            ForEach(displayed, id: \.id) { ext in
                tileView(ext)
                    .opacity(reorder.hidesInlineItem(ext.id) ? 0 : 1)
                    .reorderSlotFrame(
                        id: ext.id,
                        coordinateSpace: Self.coordinateSpaceName,
                        into: $frames.live
                    )
                    .simultaneousGesture(reorderGesture(for: ext.id, baseIDs: baseIDs))
                    .sumiAppKitContextMenu(entries: { menuEntries(for: ext) })
            }
        }
        .coordinateSpace(name: Self.coordinateSpaceName)
        .overlay(alignment: .topLeading) { draggedOverlay(displayed) }
        .animation(
            .interactiveSpring(duration: 0.22, extraBounce: 0.05),
            value: displayed.map(\.id)
        )
    }

    private func tileView(_ ext: InstalledExtension, isOverlay: Bool = false) -> some View {
        ExtensionActionButton(
            ext: ext,
            layout: .hubTiles,
            profileId: profileId,
            browserContext: browserContext,
            suppressActivation: isOverlay ? nil : { shouldSuppressActivation }
        )
    }

    @ViewBuilder
    private func draggedOverlay(_ tiles: [InstalledExtension]) -> some View {
        if let id = reorder.draggedID,
           let ext = tiles.first(where: { $0.id == id }),
           let frame = reorder.draggedOverlayFrame() {
            tileView(ext, isOverlay: true)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
                .animation(nil, value: reorder.currentLocation)
                .zIndex(2)
        }
    }

    private func reorderGesture(for id: String, baseIDs: [String]) -> some Gesture {
        makeReorderDragGesture(
            id: id,
            coordinateSpaceName: Self.coordinateSpaceName,
            isEnabled: { baseIDs.count > 1 },
            orderedIDs: { baseIDs },
            geometry: {
                frames.geometry(
                    axis: Self.axis,
                    isDragging: reorder.isDragging,
                    baseOrder: baseIDs
                )
            },
            state: $reorder,
            onBeginDrag: { frames.freeze(order: baseIDs) },
            onEndDrag: { lastDropAt = Date() },
            onCommit: { move in
                browserContext.extensionsModule.moveUnpinnedExtension(
                    id: move.id,
                    to: move.targetIndex,
                    within: baseIDs
                )
            }
        )
    }

    private var shouldSuppressActivation: Bool {
        Date().timeIntervalSince(lastDropAt) < 0.25
    }

    private func menuEntries(for ext: InstalledExtension) -> [SidebarContextMenuEntry] {
        extensionActionMenuEntries(
            for: ext,
            layout: .hubTiles,
            presentation: ExtensionActionPresentationContext(
                browserContext: browserContext,
                profileId: profileId
            )
        )
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: Self.spacing),
            count: 4
        )
    }

    /// Unpinned, enabled, action-bearing extensions in their persisted hub
    /// order (falling back to the incoming order for any not yet ordered).
    private var hubExtensions: [InstalledExtension] {
        let candidates = extensions
            .filter { $0.isEnabled && $0.hasAction }
            .filter { browserContext.extensionsModule.isPinnedToToolbar($0.id) == false }

        let orderedIDs = browserContext.extensionsModule.orderedUnpinnedExtensionIDs(
            candidateIDs: candidates.map(\.id),
            profileId: profileId
        )
        let candidatesByID = Dictionary(
            candidates.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return orderedIDs.compactMap { candidatesByID[$0] }
    }
}

@available(macOS 15.5, *)
private struct SidebarExtensionActionGrid: View {
    let extensions: [InstalledExtension]
    let profileId: UUID?
    let browserContext: ExtensionActionBrowserContext
    private static let gridSpacing: CGFloat = 8
    private static let axis: ReorderAxis = .horizontal
    private static let coordinateSpaceName = "sidebar-extension-reorder"

    @State private var reorder = ReorderDragState<String>()
    @State private var frames = ReorderFrameStore()
    @State private var lastDropAt = Date.distantPast

    var body: some View {
        let base = pinnedSlots
        let baseIDs = base.map(\.id)
        let displayed = reorder.displayOrder(base, id: \.id)

        LazyVGrid(columns: columns(slotCount: displayed.count), alignment: .leading, spacing: Self.gridSpacing) {
            ForEach(displayed) { slot in
                slotView(slot)
                    .opacity(reorder.hidesInlineItem(slot.id) ? 0 : 1)
                    .reorderSlotFrame(
                        id: slot.id,
                        coordinateSpace: Self.coordinateSpaceName,
                        into: $frames.live
                    )
                    .simultaneousGesture(reorderGesture(for: slot.id, baseIDs: baseIDs))
                    // Inside the sidebar, the background/column owns an AppKit
                    // context menu that competes for right-clicks through the
                    // sidebar controller's routing priority. A plain
                    // `sumiAppKitContextMenu` overlay does not register with that
                    // controller, so the sidebar menu wins. Route through
                    // `sidebarAppKitContextMenu` (right-click only, no primary
                    // action) so this slot registers as an AppKit owner and wins
                    // the right-click while still passing the primary mouse to
                    // the SwiftUI button and reorder drag.
                    .sidebarAppKitContextMenu(
                        surfaceKind: .button,
                        entries: { menuEntries(for: slot) }
                    )
            }
        }
        .padding(.horizontal, 2)
        .coordinateSpace(name: Self.coordinateSpaceName)
        .overlay(alignment: .topLeading) { draggedOverlay(displayed) }
        .animation(
            .interactiveSpring(duration: 0.22, extraBounce: 0.05),
            value: displayed.map(\.id)
        )
        .accessibilityIdentifier("sidebar-extension-action-grid")
    }

    @ViewBuilder
    private func slotView(_ slot: PinnedToolbarSlot, isOverlay: Bool = false) -> some View {
        switch slot {
        case .sumiScriptsManager:
            SumiScriptsToolbarControl(
                layout: .sidebarGrid,
                browserContext: browserContext,
                suppressActivation: isOverlay ? nil : { shouldSuppressActivation }
            )
        case .webExtension(let ext):
            ExtensionActionButton(
                ext: ext,
                layout: .sidebarGrid,
                profileId: profileId,
                browserContext: browserContext,
                suppressActivation: isOverlay ? nil : { shouldSuppressActivation }
            )
        }
    }

    @ViewBuilder
    private func draggedOverlay(_ slots: [PinnedToolbarSlot]) -> some View {
        if let id = reorder.draggedID,
           let slot = slots.first(where: { $0.id == id }),
           let frame = reorder.draggedOverlayFrame() {
            slotView(slot, isOverlay: true)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
                .animation(nil, value: reorder.currentLocation)
                .zIndex(2)
        }
    }

    private func reorderGesture(for id: String, baseIDs: [String]) -> some Gesture {
        makeReorderDragGesture(
            id: id,
            coordinateSpaceName: Self.coordinateSpaceName,
            isEnabled: { baseIDs.count > 1 },
            orderedIDs: { baseIDs },
            geometry: {
                frames.geometry(
                    axis: Self.axis,
                    isDragging: reorder.isDragging,
                    baseOrder: baseIDs
                )
            },
            state: $reorder,
            onBeginDrag: { frames.freeze(order: baseIDs) },
            onEndDrag: { lastDropAt = Date() },
            onCommit: { move in
                browserContext.extensionsModule.movePinnedToolbarSlot(
                    id: move.id,
                    to: move.targetIndex
                )
            }
        )
    }

    private var shouldSuppressActivation: Bool {
        Date().timeIntervalSince(lastDropAt) < 0.25
    }

    private func menuEntries(for slot: PinnedToolbarSlot) -> [SidebarContextMenuEntry] {
        switch slot {
        case .sumiScriptsManager:
            return sumiScriptsToolbarMenuEntries(browserContext: browserContext)
        case .webExtension(let ext):
            return extensionActionMenuEntries(
                for: ext,
                layout: .sidebarGrid,
                presentation: ExtensionActionPresentationContext(
                    browserContext: browserContext,
                    profileId: profileId
                )
            )
        }
    }

    private func columns(slotCount: Int) -> [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(minimum: 0, maximum: .infinity),
                spacing: Self.gridSpacing,
                alignment: .center
            ),
            count: max(slotCount, 1)
        )
    }

    private var enabledExtensions: [InstalledExtension] {
        extensions.filter { $0.isEnabled }
    }

    private var pinnedSlots: [PinnedToolbarSlot] {
        browserContext.extensionsModule.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            sumiScriptsManagerEnabled: browserContext.userscriptsModule.isEnabled,
            profileId: profileId
        )
    }
}

@available(macOS 15.5, *)
private struct CompactExtensionActionStrip: View {
    let extensions: [InstalledExtension]
    let visibleActionLimit: Int?
    let browserContext: ExtensionActionBrowserContext

    @State private var reorder = ReorderDragState<String>()
    @State private var frames = ReorderFrameStore()
    @State private var lastDropAt = Date.distantPast

    private static let axis: ReorderAxis = .horizontal
    private static let coordinateSpaceName = "compact-extension-reorder"

    var body: some View {
        let base = visiblePinnedSlots
        let baseIDs = base.map(\.id)
        let displayed = reorder.displayOrder(base, id: \.id)

        HStack(spacing: 4) {
            ForEach(displayed) { slot in
                slotView(slot)
                    .opacity(reorder.hidesInlineItem(slot.id) ? 0 : 1)
                    .reorderSlotFrame(
                        id: slot.id,
                        coordinateSpace: Self.coordinateSpaceName,
                        into: $frames.live
                    )
                    .simultaneousGesture(reorderGesture(for: slot.id, baseIDs: baseIDs))
                    .sumiAppKitContextMenu(entries: { menuEntries(for: slot) })
            }
        }
        .coordinateSpace(name: Self.coordinateSpaceName)
        .overlay(alignment: .topLeading) { draggedOverlay(displayed) }
        .animation(
            .interactiveSpring(duration: 0.22, extraBounce: 0.05),
            value: displayed.map(\.id)
        )
    }

    @ViewBuilder
    private func slotView(_ slot: PinnedToolbarSlot, isOverlay: Bool = false) -> some View {
        switch slot {
        case .sumiScriptsManager:
            SumiScriptsToolbarControl(
                layout: .compactStrip,
                browserContext: browserContext,
                suppressActivation: isOverlay ? nil : { shouldSuppressActivation }
            )
        case .webExtension(let ext):
            ExtensionActionButton(
                ext: ext,
                layout: .compactStrip,
                browserContext: browserContext,
                suppressActivation: isOverlay ? nil : { shouldSuppressActivation }
            )
        }
    }

    @ViewBuilder
    private func draggedOverlay(_ slots: [PinnedToolbarSlot]) -> some View {
        if let id = reorder.draggedID,
           let slot = slots.first(where: { $0.id == id }),
           let frame = reorder.draggedOverlayFrame() {
            slotView(slot, isOverlay: true)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
                .animation(nil, value: reorder.currentLocation)
                .zIndex(2)
        }
    }

    private func reorderGesture(for id: String, baseIDs: [String]) -> some Gesture {
        makeReorderDragGesture(
            id: id,
            coordinateSpaceName: Self.coordinateSpaceName,
            isEnabled: { baseIDs.count > 1 },
            orderedIDs: { baseIDs },
            geometry: {
                frames.geometry(
                    axis: Self.axis,
                    isDragging: reorder.isDragging,
                    baseOrder: baseIDs
                )
            },
            state: $reorder,
            onBeginDrag: { frames.freeze(order: baseIDs) },
            onEndDrag: { lastDropAt = Date() },
            onCommit: { move in
                browserContext.extensionsModule.movePinnedToolbarSlot(
                    id: move.id,
                    to: move.targetIndex
                )
            }
        )
    }

    private var shouldSuppressActivation: Bool {
        Date().timeIntervalSince(lastDropAt) < 0.25
    }

    private func menuEntries(for slot: PinnedToolbarSlot) -> [SidebarContextMenuEntry] {
        switch slot {
        case .sumiScriptsManager:
            return sumiScriptsToolbarMenuEntries(browserContext: browserContext)
        case .webExtension(let ext):
            return extensionActionMenuEntries(
                for: ext,
                layout: .compactStrip,
                presentation: ExtensionActionPresentationContext(
                    browserContext: browserContext,
                    profileId: nil
                )
            )
        }
    }

    private var enabledExtensions: [InstalledExtension] {
        extensions.filter { $0.isEnabled }
    }

    private var compactLimit: Int {
        visibleActionLimit ?? Int.max
    }

    private var pinnedSlots: [PinnedToolbarSlot] {
        browserContext.extensionsModule.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            sumiScriptsManagerEnabled: browserContext.userscriptsModule.isEnabled
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
    let browserContext: ExtensionActionBrowserContext
    /// When it returns true, a just-completed reorder drag suppresses the
    /// synthetic click so dragging the control does not also open its popover.
    var suppressActivation: (() -> Bool)?

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovering = false
    @State private var isPressed = false
    @State private var showingPopup = false

    var body: some View {
        Button {
            guard suppressActivation?() != true else { return }
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
                    .clipShape(RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(12), style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(12), style: .continuous))
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
                .sumiNativeSurfaceColorScheme()
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .modifier(HubTilePressGestureModifier(layout: layout, isPressed: $isPressed))
    }

    @ViewBuilder
    private var sumiScriptsPopover: some View {
        let currentTab = browserContext.currentTab()
        if let manager = browserContext.userscriptsModule.managerIfEnabled() {
            SumiScriptsPopupView(
                manager: manager,
                currentURL: currentTab?.url,
                webView: currentTab.flatMap(browserContext.webView)
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

// MARK: - Right-click menu entries

// The right-click-only AppKit menu is attached by the enclosing strip/grid as
// the *outermost* layer, above the reorder drag gesture. Nesting it under the
// container-level reorder `.simultaneousGesture` (as an inner overlay on the
// button) lets that gesture shadow the AppKit host, so `rightMouseDown` never
// reaches it — which is why pinned surfaces lost their context menu. Building
// the entries here (rather than inside the button) lets each surface own the
// overlay placement while sharing the menu contents.

@available(macOS 15.5, *)
@MainActor
private func extensionActionMenuEntries(
    for ext: InstalledExtension,
    layout: ExtensionActionLayout,
    presentation: ExtensionActionPresentationContext
) -> [SidebarContextMenuEntry] {
    var entries: [SidebarContextMenuEntry] = [
        .action(
            SidebarContextMenuAction(
                title: "Manage Extensions",
                systemImage: "gearshape",
                classification: .presentationOnly,
                action: {
                    presentation.openExtensionsSettings()
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
                        presentation.pinToToolbar(extensionId: ext.id)
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
                        presentation.unpinFromToolbar(extensionId: ext.id)
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
                            await presentation.openOptionsPage(for: ext)
                        }
                    }
                )
            )
        )
    }

    return entries
}

@available(macOS 15.5, *)
@MainActor
private func sumiScriptsToolbarMenuEntries(
    browserContext: ExtensionActionBrowserContext
) -> [SidebarContextMenuEntry] {
    [
        .action(
            SidebarContextMenuAction(
                title: "Manage Userscripts",
                systemImage: "gearshape",
                classification: .presentationOnly,
                action: {
                    browserContext.openSettingsTab(.userScripts)
                }
            )
        ),
    ]
}

@available(macOS 15.5, *)
struct ExtensionActionButton: View {
    let ext: InstalledExtension
    var layout: ExtensionActionLayout = .compactStrip
    var profileId: UUID?
    let browserContext: ExtensionActionBrowserContext
    /// When it returns true, a just-completed reorder drag suppresses the
    /// synthetic click so dragging the icon does not also open its popup.
    var suppressActivation: (() -> Bool)?
    @EnvironmentObject private var extensionSurfaceStore:
        BrowserExtensionSurfaceStore
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovering: Bool = false
    @State private var isPressed = false

    var body: some View {
        Group {
            // A plain SwiftUI Button on every surface: the reorder drag gesture
            // (attached by the enclosing strip/grid) needs the primary mouse,
            // so no surface may use AppKit primary-mouse tracking.
            Button(action: {
                showExtensionPopup()
            }) {
                buttonLabel
            }
            .buttonStyle(.plain)
        }
        .help(actionTitle)
        .disabled(actionState?.isEnabled == false)
        .opacity(actionState?.isEnabled == false ? 0.55 : 1)
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
                            extensionsModule: browserContext.extensionsModule
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
                            extensionsModule: browserContext.extensionsModule
                        )
                        .allowsHitTesting(false)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(12), style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: sumiSettings.resolvedCornerRadius(12), style: .continuous))
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
                            extensionsModule: browserContext.extensionsModule
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
           ) {
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
        guard suppressActivation?() != true else { return }
        Task { @MainActor in
            await actionPresentationContext.presentActionPopup(for: ext)
        }
    }

    private var actionPresentationContext: ExtensionActionPresentationContext {
        ExtensionActionPresentationContext(
            browserContext: browserContext,
            profileId: profileId
        )
    }
}

@available(macOS 15.5, *)
#Preview {
    ExtensionActionView(
        extensions: [],
        browserContext: ExtensionActionBrowserContext(
            extensionsModule: SumiExtensionsModule(),
            userscriptsModule: SumiUserscriptsModule(),
            windowState: BrowserWindowState(),
            currentTab: { nil },
            currentProfileID: { nil },
            hasLoadedInitialData: { true },
            webView: { $0.existingWebView },
            openSettingsTab: { _ in /* No-op. */ },
            showExtensionUnavailableAlert: { _, _ in /* No-op. */ }
        )
    )
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
