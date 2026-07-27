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

    init() {}

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
    let extensions: [BrowserExtensionToolbarDisplayRecord]
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
                profileId: profileId,
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
    let extensions: [BrowserExtensionToolbarDisplayRecord]
    let profileId: UUID?
    let browserContext: ExtensionActionBrowserContext

    private static let spacing: CGFloat = 8
    private static let coordinateSpaceName = "hub-extension-reorder"

    var body: some View {
        let base = hubExtensions
        ExtensionActionReorderSurface(
            base: base,
            id: \.id,
            axis: .grid,
            coordinateSpaceName: Self.coordinateSpaceName,
            onCommit: { move in
                browserContext.extensionsModule.moveUnpinnedExtension(
                    id: move.id,
                    to: move.targetIndex,
                    within: base.map(\.id),
                    profileId: profileId
                )
            },
            content: { surface in
                LazyVGrid(columns: columns, alignment: .leading, spacing: Self.spacing) {
                    ForEach(surface.displayed, id: \.id) { ext in
                        surface.slot(ext) {
                            tileView(
                                ext,
                                suppressActivation: surface.shouldSuppressActivation
                            )
                        }
                        .sumiAppKitContextMenu(entries: { menuEntries(for: ext) })
                    }
                }
            },
            overlayContent: { ext in
                tileView(ext, suppressActivation: nil)
            }
        )
    }

    private func tileView(
        _ ext: BrowserExtensionToolbarDisplayRecord,
        suppressActivation: (() -> Bool)?
    ) -> some View {
        ExtensionActionButton(
            ext: ext,
            layout: .hubTiles,
            profileId: profileId,
            browserContext: browserContext,
            suppressActivation: suppressActivation
        )
    }

    private func menuEntries(
        for ext: BrowserExtensionToolbarDisplayRecord
    ) -> [SidebarContextMenuEntry] {
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

    private var hubExtensions: [BrowserExtensionToolbarDisplayRecord] {
        extensions.filter { $0.isEnabled && $0.hasAction }
    }
}

@available(macOS 15.5, *)
private struct SidebarExtensionActionGrid: View {
    let extensions: [BrowserExtensionToolbarDisplayRecord]
    let profileId: UUID?
    let browserContext: ExtensionActionBrowserContext
    private static let gridSpacing: CGFloat = 8
    private static let coordinateSpaceName = "sidebar-extension-reorder"

    var body: some View {
        ExtensionActionReorderSurface(
            base: pinnedSlots,
            id: \.id,
            axis: .horizontal,
            coordinateSpaceName: Self.coordinateSpaceName,
            onCommit: { move in
                browserContext.extensionsModule.movePinnedToolbarSlot(
                    id: move.id,
                    to: move.targetIndex,
                    profileId: profileId
                )
            },
            content: { surface in
                LazyVGrid(
                    columns: columns(slotCount: surface.displayed.count),
                    alignment: .leading,
                    spacing: Self.gridSpacing
                ) {
                    ForEach(surface.displayed) { slot in
                        surface.slot(slot) {
                            slotView(
                                slot,
                                suppressActivation: surface.shouldSuppressActivation
                            )
                        }
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
                .accessibilityIdentifier("sidebar-extension-action-grid")
            },
            overlayContent: { slot in
                slotView(slot, suppressActivation: nil)
            }
        )
    }

    @ViewBuilder
    private func slotView(
        _ slot: PinnedToolbarSlot,
        suppressActivation: (() -> Bool)?
    ) -> some View {
        switch slot {
        case .webExtension(let ext):
            ExtensionActionButton(
                ext: ext,
                layout: .sidebarGrid,
                profileId: profileId,
                browserContext: browserContext,
                suppressActivation: suppressActivation
            )
        }
    }

    private func menuEntries(for slot: PinnedToolbarSlot) -> [SidebarContextMenuEntry] {
        switch slot {
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

    private var enabledExtensions: [BrowserExtensionToolbarDisplayRecord] {
        extensions.filter { $0.isEnabled }
    }

    private var pinnedSlots: [PinnedToolbarSlot] {
        browserContext.extensionsModule.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            profileId: profileId
        )
    }
}

@available(macOS 15.5, *)
private struct CompactExtensionActionStrip: View {
    let extensions: [BrowserExtensionToolbarDisplayRecord]
    let visibleActionLimit: Int?
    let profileId: UUID?
    let browserContext: ExtensionActionBrowserContext

    private static let coordinateSpaceName = "compact-extension-reorder"

    var body: some View {
        ExtensionActionReorderSurface(
            base: visiblePinnedSlots,
            id: \.id,
            axis: .horizontal,
            coordinateSpaceName: Self.coordinateSpaceName,
            onCommit: { move in
                browserContext.extensionsModule.movePinnedToolbarSlot(
                    id: move.id,
                    to: move.targetIndex,
                    profileId: profileId
                )
            },
            content: { surface in
                HStack(spacing: 4) {
                    ForEach(surface.displayed) { slot in
                        surface.slot(slot) {
                            slotView(
                                slot,
                                suppressActivation: surface.shouldSuppressActivation
                            )
                        }
                        .sumiAppKitContextMenu(entries: { menuEntries(for: slot) })
                    }
                }
            },
            overlayContent: { slot in
                slotView(slot, suppressActivation: nil)
            }
        )
    }

    @ViewBuilder
    private func slotView(
        _ slot: PinnedToolbarSlot,
        suppressActivation: (() -> Bool)?
    ) -> some View {
        switch slot {
        case .webExtension(let ext):
            ExtensionActionButton(
                ext: ext,
                layout: .compactStrip,
                profileId: profileId,
                browserContext: browserContext,
                suppressActivation: suppressActivation
            )
        }
    }

    private func menuEntries(for slot: PinnedToolbarSlot) -> [SidebarContextMenuEntry] {
        switch slot {
        case .webExtension(let ext):
            return extensionActionMenuEntries(
                for: ext,
                layout: .compactStrip,
                presentation: ExtensionActionPresentationContext(
                    browserContext: browserContext,
                    profileId: profileId
                )
            )
        }
    }

    private var enabledExtensions: [BrowserExtensionToolbarDisplayRecord] {
        extensions.filter { $0.isEnabled }
    }

    private var compactLimit: Int {
        visibleActionLimit ?? Int.max
    }

    private var pinnedSlots: [PinnedToolbarSlot] {
        browserContext.extensionsModule.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            profileId: profileId
        )
    }

    private var visiblePinnedSlots: [PinnedToolbarSlot] {
        Array(pinnedSlots.prefix(compactLimit))
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
    for ext: BrowserExtensionToolbarDisplayRecord,
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
struct ExtensionActionButton: View {
    let ext: BrowserExtensionToolbarDisplayRecord
    var layout: ExtensionActionLayout = .compactStrip
    var profileId: UUID?
    let browserContext: ExtensionActionBrowserContext
    /// When it returns true, a just-completed reorder drag suppresses the
    /// synthetic click so dragging the icon does not also open its popup.
    var suppressActivation: (() -> Bool)?
    private let iconCache: ExtensionIconCache
    @StateObject private var actionModel: BrowserExtensionActionButtonModel
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens
    @State private var isHovering: Bool = false
    @State private var isPressed = false

    init(
        ext: BrowserExtensionToolbarDisplayRecord,
        layout: ExtensionActionLayout = .compactStrip,
        profileId: UUID? = nil,
        browserContext: ExtensionActionBrowserContext,
        suppressActivation: (() -> Bool)? = nil
    ) {
        self.ext = ext
        self.layout = layout
        self.profileId = profileId
        self.browserContext = browserContext
        self.suppressActivation = suppressActivation
        let surfaceStore = browserContext.extensionsModule.surfaceStore
        iconCache = surfaceStore.iconCache
        _actionModel = StateObject(
            wrappedValue: BrowserExtensionActionButtonModel(
                changes: surfaceStore.actionPresentationChanges,
                query: { target in
                    guard browserContext.windowState === target.window,
                          browserContext.currentTab() === target.tab
                    else { return nil }
                    return browserContext.extensionsModule
                        .actionPresentationSnapshot(for: target)
                }
            )
        )
    }

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
        .disabled(actionState.isEnabled == false)
        .opacity(actionState.isEnabled == false ? 0.55 : 1)
        .sidebarHover($isHovering)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isPressed = true
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
        .task(id: actionPresentationTarget) {
            actionModel.setTarget(actionPresentationTarget)
        }
        .onDisappear {
            actionModel.setTarget(nil)
        }
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
        if let actionIcon = actionState.icon {
            Image(nsImage: actionIcon)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else if let iconPath = ext.iconPath,
                  let nsImage = iconCache.image(
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
                    .fill(Color.red.opacity(actionState.hasUnreadBadgeText ? 0.95 : 0.78))
            )
    }

    private var actionState: BrowserExtensionActionButtonSnapshot {
        actionModel.snapshot(for: actionPresentationTarget)
    }

    private var actionPresentationTarget: ExtensionActionPresentationTarget? {
        guard let tab = browserContext.currentTab(),
              browserContext.windowState.currentTabId == tab.id
        else { return nil }
        return browserContext.extensionsModule.actionPresentationTarget(
            extensionID: ext.id,
            tab: tab,
            window: browserContext.windowState
        )
    }

    private var actionTitle: String {
        guard let label = actionState.label?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            label.isEmpty == false
        else {
            return ext.name
        }
        return label
    }

    private var visibleBadgeText: String? {
        guard let badgeText = actionState.badgeText?
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
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
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
        browserContext: ExtensionActionBrowserContext.unavailable(
            extensionsModule: SumiExtensionsModule(
                compiledRuleListCatalog: SumiCompiledContentRuleListCatalog()
            ),
            windowState: BrowserWindowState()
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
