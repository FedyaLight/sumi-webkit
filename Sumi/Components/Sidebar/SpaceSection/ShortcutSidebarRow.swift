//
//  ShortcutSidebarRow.swift
//  Sumi
//

import SwiftUI
import SumiDomain

struct ShortcutSidebarRow: View {
    @ObservedObject var pin: ShortcutPin
    var liveTab: Tab?
    let faviconPartition: SumiFaviconPartition
    let faviconImageReader: any BrowserFaviconImageReading
    let runtimeAffordance: SumiLauncherRuntimeAffordanceState
    var projectedSplitTarget: SidebarSplitPairingTarget? = nil
    var accessibilityID: String?
    var contextMenuEntries: () -> [SidebarContextMenuEntry] = { [] }
    let action: () -> Void
    var dragSourceZone: DropZoneID?
    var dragHasTrailingActionExclusion: Bool = true
    var dragIsEnabled: Bool = true
    let onResetToLaunchURL: (() -> Void)?
    let onUnload: () -> Void
    let onRemove: () -> Void

    @ViewBuilder
    var body: some View {
        if let liveTab {
            LiveShortcutSidebarRow(
                row: self,
                liveTab: liveTab
            )
        } else {
            rowChrome(liveTab: nil)
        }
    }

    fileprivate func rowChrome(liveTab: Tab?) -> some View {
        let resolvedRuntimeAffordance = liveTab.map {
            runtimeAffordance.resolvingURLDrift(
                pin.hasDrifted(from: $0.url)
            )
        } ?? runtimeAffordance
        return ShortcutSidebarRowChrome(
            pin: pin,
            liveTab: liveTab,
            faviconPartition: faviconPartition,
            faviconImageReader: faviconImageReader,
            resolvedTitle: pin.resolvedDisplayTitle(liveTab: liveTab),
            runtimeAffordance: resolvedRuntimeAffordance,
            projectedSplitTarget: projectedSplitTarget,
            accessibilityID: accessibilityID,
            contextMenuEntries: contextMenuEntries,
            action: action,
            dragSourceZone: dragSourceZone,
            dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
            dragIsEnabled: dragIsEnabled,
            onResetToLaunchURL: onResetToLaunchURL,
            onUnload: onUnload,
            onRemove: onRemove
        )
    }
}

private struct LiveShortcutSidebarRow: View {
    let row: ShortcutSidebarRow
    @ObservedObject var liveTab: Tab

    var body: some View {
        row.rowChrome(liveTab: liveTab)
    }
}
