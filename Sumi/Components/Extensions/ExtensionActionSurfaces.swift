import AppKit
import SwiftUI

// Every surface here takes its display order as a plain stored property rather
// than reading it back out of `SumiExtensionsModule` inside `body`. The pinning
// store is not observable, so an imperative read is invisible to SwiftUI: with
// unchanged inputs the body is never re-evaluated and a pin, unpin, or reorder
// stays on screen in its pre-change order until something else (historically, a
// space switch) rebuilds the subtree.

@available(macOS 15.5, *)
struct HubExtensionTilesGrid: View {
    let extensions: [BrowserExtensionToolbarDisplayRecord]
    /// Display order of the unpinned tiles, resolved by the caller.
    let unpinnedExtensionIDs: [String]
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
            onActivate: { ext in
                activate(ext)
            },
            content: { surface in
                LazyVGrid(columns: columns, alignment: .leading, spacing: Self.spacing) {
                    ForEach(surface.displayed, id: \.id) { ext in
                        surface.slot(ext) {
                            tileView(ext, isPressed: surface.isPressed(ext))
                        }
                        .sumiAppKitContextMenu(entries: { menuEntries(for: ext) })
                    }
                }
            },
            overlayContent: { ext in
                tileView(ext, isPressed: false)
            }
        )
    }

    private func tileView(
        _ ext: BrowserExtensionToolbarDisplayRecord,
        isPressed: Bool
    ) -> some View {
        ExtensionActionButton(
            ext: ext,
            layout: .hubTiles,
            profileId: profileId,
            browserContext: browserContext,
            isPressed: isPressed,
            onActivate: { activate(ext) }
        )
    }

    private func activate(_ ext: BrowserExtensionToolbarDisplayRecord) {
        presentActionPopup(
            for: ext,
            browserContext: browserContext,
            profileId: profileId
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
        let eligible = extensions.filter { $0.isEnabled && $0.hasAction }
        return orderedExtensions(eligible, by: unpinnedExtensionIDs)
    }
}

@available(macOS 15.5, *)
struct SidebarExtensionActionGrid: View {
    let extensions: [BrowserExtensionToolbarDisplayRecord]
    /// Ordered ids of the pinned toolbar slots, resolved by the caller.
    let pinnedExtensionIDs: [String]
    let profileId: UUID?
    let browserContext: ExtensionActionBrowserContext
    private static let gridSpacing: CGFloat = 8
    private static let coordinateSpaceName = "sidebar-extension-reorder"

    var body: some View {
        let slots = pinnedSlots
        ExtensionActionReorderSurface(
            base: slots,
            id: \.id,
            axis: .horizontal,
            coordinateSpaceName: Self.coordinateSpaceName,
            onCommit: { move in
                browserContext.extensionsModule.movePinnedToolbarSlot(
                    id: move.id,
                    to: move.targetIndex,
                    within: slots.map(\.id),
                    profileId: profileId
                )
            },
            onActivate: { slot in
                activate(slot)
            },
            content: { surface in
                LazyVGrid(
                    columns: columns(slotCount: surface.displayed.count),
                    alignment: .leading,
                    spacing: Self.gridSpacing
                ) {
                    ForEach(surface.displayed) { slot in
                        surface.slot(slot) {
                            slotView(slot, isPressed: surface.isPressed(slot))
                        }
                        // Register the slot with the sidebar's AppKit context-menu
                        // router without claiming the primary mouse used by the
                        // shared SwiftUI tap/reorder gesture.
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
                slotView(slot, isPressed: false)
            }
        )
    }

    @ViewBuilder
    private func slotView(
        _ slot: PinnedToolbarSlot,
        isPressed: Bool
    ) -> some View {
        switch slot {
        case .webExtension(let ext):
            ExtensionActionButton(
                ext: ext,
                layout: .sidebarGrid,
                profileId: profileId,
                browserContext: browserContext,
                isPressed: isPressed,
                onActivate: { activate(slot) }
            )
        }
    }

    private func activate(_ slot: PinnedToolbarSlot) {
        switch slot {
        case .webExtension(let ext):
            presentActionPopup(
                for: ext,
                browserContext: browserContext,
                profileId: profileId
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

    private var pinnedSlots: [PinnedToolbarSlot] {
        pinnedToolbarSlots(
            ids: pinnedExtensionIDs,
            enabledExtensions: extensions
        )
    }
}

@available(macOS 15.5, *)
struct CompactExtensionActionStrip: View {
    let extensions: [BrowserExtensionToolbarDisplayRecord]
    /// Ordered ids of the pinned toolbar slots, resolved by the caller.
    let pinnedExtensionIDs: [String]
    let visibleActionLimit: Int?
    let profileId: UUID?
    let browserContext: ExtensionActionBrowserContext

    private static let coordinateSpaceName = "compact-extension-reorder"

    var body: some View {
        let slots = visiblePinnedSlots
        ExtensionActionReorderSurface(
            base: slots,
            id: \.id,
            axis: .horizontal,
            coordinateSpaceName: Self.coordinateSpaceName,
            onCommit: { move in
                browserContext.extensionsModule.movePinnedToolbarSlot(
                    id: move.id,
                    to: move.targetIndex,
                    within: slots.map(\.id),
                    profileId: profileId
                )
            },
            onActivate: { slot in
                activate(slot)
            },
            content: { surface in
                HStack(spacing: 4) {
                    ForEach(surface.displayed) { slot in
                        surface.slot(slot) {
                            slotView(slot, isPressed: surface.isPressed(slot))
                        }
                        .sumiAppKitContextMenu(entries: { menuEntries(for: slot) })
                    }
                }
            },
            overlayContent: { slot in
                slotView(slot, isPressed: false)
            }
        )
    }

    @ViewBuilder
    private func slotView(
        _ slot: PinnedToolbarSlot,
        isPressed: Bool
    ) -> some View {
        switch slot {
        case .webExtension(let ext):
            ExtensionActionButton(
                ext: ext,
                layout: .compactStrip,
                profileId: profileId,
                browserContext: browserContext,
                isPressed: isPressed,
                onActivate: { activate(slot) }
            )
        }
    }

    private func activate(_ slot: PinnedToolbarSlot) {
        switch slot {
        case .webExtension(let ext):
            presentActionPopup(
                for: ext,
                browserContext: browserContext,
                profileId: profileId
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

    private var compactLimit: Int {
        visibleActionLimit ?? Int.max
    }

    private var visiblePinnedSlots: [PinnedToolbarSlot] {
        Array(
            pinnedToolbarSlots(
                ids: pinnedExtensionIDs,
                enabledExtensions: extensions
            )
            .prefix(compactLimit)
        )
    }
}

// MARK: - Shared display projection

/// The pinned slots for `ids`, in that order, keeping only ids whose extension
/// is present, enabled, and has an action. Mirrors
/// `ExtensionToolbarPinningOwner.orderedPinnedToolbarSlots` so a surface can
/// project the ids it was handed without reaching back into the module.
@available(macOS 15.5, *)
func pinnedToolbarSlots(
    ids: [String],
    enabledExtensions: [BrowserExtensionToolbarDisplayRecord]
) -> [PinnedToolbarSlot] {
    let eligibleByID = Dictionary(
        enabledExtensions
            .filter { $0.isEnabled && $0.hasAction }
            .map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )
    return ids.compactMap { id in
        eligibleByID[id].map(PinnedToolbarSlot.webExtension)
    }
}

/// `extensions` reordered to match `order`; anything `order` does not mention
/// keeps its incoming relative position at the end.
@available(macOS 15.5, *)
func orderedExtensions(
    _ extensions: [BrowserExtensionToolbarDisplayRecord],
    by order: [String]
) -> [BrowserExtensionToolbarDisplayRecord] {
    let byID = Dictionary(
        extensions.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )
    let ordered = order.compactMap { byID[$0] }
    let orderedIDs = Set(ordered.map(\.id))
    return ordered + extensions.filter { !orderedIDs.contains($0.id) }
}

@available(macOS 15.5, *)
@MainActor
private func presentActionPopup(
    for ext: BrowserExtensionToolbarDisplayRecord,
    browserContext: ExtensionActionBrowserContext,
    profileId: UUID?
) {
    guard extensionActionIsEnabled(ext, browserContext: browserContext) else {
        return
    }
    Task { @MainActor in
        await ExtensionActionPresentationContext(
            browserContext: browserContext,
            profileId: profileId
        )
        .presentActionPopup(for: ext)
    }
}
