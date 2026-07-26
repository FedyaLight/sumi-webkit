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
        Group {
            if let liveTab {
                ShortcutSidebarLiveRowContent(
                    pin: pin,
                    liveTab: liveTab,
                    faviconPartition: faviconPartition,
                    faviconImageReader: faviconImageReader,
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
            } else {
                ShortcutSidebarStoredRowContent(
                    pin: pin,
                    faviconPartition: faviconPartition,
                    faviconImageReader: faviconImageReader,
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
    }
}

private struct ShortcutSidebarLiveRowContent: View {
    @ObservedObject var pin: ShortcutPin
    @ObservedObject var liveTab: Tab
    let faviconPartition: SumiFaviconPartition
    let faviconImageReader: any BrowserFaviconImageReading
    let runtimeAffordance: SumiLauncherRuntimeAffordanceState
    let projectedSplitTarget: SidebarSplitPairingTarget?
    var accessibilityID: String?
    var contextMenuEntries: () -> [SidebarContextMenuEntry]
    let action: () -> Void
    var dragSourceZone: DropZoneID?
    var dragHasTrailingActionExclusion: Bool
    var dragIsEnabled: Bool
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

private struct ShortcutSidebarStoredRowContent: View {
    @ObservedObject var pin: ShortcutPin
    let faviconPartition: SumiFaviconPartition
    let faviconImageReader: any BrowserFaviconImageReading
    let runtimeAffordance: SumiLauncherRuntimeAffordanceState
    let projectedSplitTarget: SidebarSplitPairingTarget?
    var accessibilityID: String?
    var contextMenuEntries: () -> [SidebarContextMenuEntry]
    let action: () -> Void
    var dragSourceZone: DropZoneID?
    var dragHasTrailingActionExclusion: Bool
    var dragIsEnabled: Bool
    let onResetToLaunchURL: (() -> Void)?
    let onUnload: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ShortcutSidebarRowChrome(
            pin: pin,
            liveTab: nil,
            faviconPartition: faviconPartition,
            faviconImageReader: faviconImageReader,
            resolvedTitle: pin.preferredDisplayTitle,
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
