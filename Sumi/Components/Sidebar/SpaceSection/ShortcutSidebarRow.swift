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
    let runtimeAffordance: SumiLauncherRuntimeAffordanceState
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
                    runtimeAffordance: runtimeAffordance,
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
                    runtimeAffordance: runtimeAffordance,
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
    let runtimeAffordance: SumiLauncherRuntimeAffordanceState
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
            resolvedTitle: pin.resolvedDisplayTitle(liveTab: liveTab),
            runtimeAffordance: runtimeAffordance,
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
    let runtimeAffordance: SumiLauncherRuntimeAffordanceState
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
            resolvedTitle: pin.preferredDisplayTitle,
            runtimeAffordance: runtimeAffordance,
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

