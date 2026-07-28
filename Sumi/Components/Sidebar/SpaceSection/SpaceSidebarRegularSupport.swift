import SumiDomain
import SwiftUI

struct SpaceRegularDragSnapshot: Equatable {
    let isDragging: Bool
    let isCompletingDrop: Bool
    let activeDragItemID: UUID?
    let splitPairingTarget: SidebarSplitPairingTarget?
    let geometryGeneration: Int

    init(frame: SidebarListDragPresentationFrame, geometryGeneration: Int) {
        isDragging = frame.isDragging
        isCompletingDrop = frame.isCompletingDrop
        activeDragItemID = frame.activeDragItemID
        splitPairingTarget = frame.splitPairingTarget
        self.geometryGeneration = geometryGeneration
    }
}

struct SpaceRegularNewTabRow: View {
    let space: Space
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool

    @State private var isHovered = false
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    private var sourceID: String {
        "space-new-tab-\(space.id.uuidString)"
    }

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        let cornerRadius = sumiSettings.resolvedCornerRadius(12)
        Button(action: openNewTab) {
            SidebarNewTabRowLabel(tokens: tokens)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: SidebarRowLayout.rowHeight)
        .frame(minWidth: 0, maxWidth: .infinity)
        .sidebarRowSurface(
            background: isHovered ? tokens.sidebarRowHover : Color.clear,
            cornerRadius: cornerRadius,
            tokens: tokens,
            isVisible: isHovered,
            drawsSelectionShadow: false
        )
        .contentShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .sidebarHover($isHovered, isEnabled: isInteractive)
        .sidebarZenPressEffect(sourceID: sourceID)
        .accessibilityIdentifier(sourceID)
        .sidebarAppKitPrimaryAction(
            isInteractionEnabled: isInteractive,
            sourceID: sourceID,
            action: openNewTab
        )
    }

    private func openNewTab() {
        guard isInteractive else { return }
        browserContext.commandPaletteCommit.openNewTabSurface(in: windowState)
    }
}
