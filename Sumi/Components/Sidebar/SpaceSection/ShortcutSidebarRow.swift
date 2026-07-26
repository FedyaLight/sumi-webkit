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

    var body: some View {
        ShortcutSidebarRowChrome(
            pin: pin,
            liveTab: liveTab,
            faviconPartition: faviconPartition,
            faviconImageReader: faviconImageReader,
            resolvedTitle: pin.resolvedDisplayTitle(liveTab: liveTab),
            runtimeAffordance: runtimeAffordance,
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
