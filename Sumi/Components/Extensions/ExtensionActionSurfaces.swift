import AppKit
import SwiftUI


@available(macOS 15.5, *)
struct HubExtensionTilesGrid: View {
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
struct SidebarExtensionActionGrid: View {
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
struct CompactExtensionActionStrip: View {
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
