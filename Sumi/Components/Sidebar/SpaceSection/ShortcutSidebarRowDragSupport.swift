//
//  ShortcutSidebarRowDragSupport.swift
//  Sumi
//

import SwiftUI
import SumiDomain

@MainActor
func makeShortcutSidebarDragSourceConfiguration(
    pin: ShortcutPin,
    resolvedTitle: String,
    runtimeAffordance: SumiLauncherRuntimeAffordanceState,
    dragSourceZone: DropZoneID?,
    dragHasTrailingActionExclusion: Bool,
    hasLiveAudioExclusion: Bool = false,
    trailingActionExclusionWidth: CGFloat = 40,
    previewIcon: Image,
    action: (() -> Void)? = nil,
    dragIsEnabled: Bool = true
) -> SidebarDragSourceConfiguration? {
    guard let dragSourceZone else { return nil }

    return SidebarDragSourceConfiguration(
        item: SumiDragItem(
            tabId: pin.id,
            title: resolvedTitle,
            urlString: pin.launchURL.absoluteString
        ),
        sourceZone: dragSourceZone,
        previewKind: .row,
        previewIcon: previewIcon,
        exclusionZones: makeShortcutSidebarDragExclusionZones(
            runtimeAffordance: runtimeAffordance,
            dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
            hasLiveAudioExclusion: hasLiveAudioExclusion,
            trailingActionExclusionWidth: trailingActionExclusionWidth
        ),
        onActivate: action,
        isEnabled: dragIsEnabled
    )
}

@MainActor
func makeShortcutSidebarDragExclusionZones(
    runtimeAffordance: SumiLauncherRuntimeAffordanceState,
    dragHasTrailingActionExclusion: Bool,
    hasLiveAudioExclusion: Bool = false
) -> [SidebarDragSourceExclusionZone] {
    makeShortcutSidebarDragExclusionZones(
        runtimeAffordance: runtimeAffordance,
        dragHasTrailingActionExclusion: dragHasTrailingActionExclusion,
        hasLiveAudioExclusion: hasLiveAudioExclusion,
        trailingActionExclusionWidth: 40
    )
}

@MainActor
func makeShortcutSidebarDragExclusionZones(
    runtimeAffordance: SumiLauncherRuntimeAffordanceState,
    dragHasTrailingActionExclusion: Bool,
    hasLiveAudioExclusion: Bool = false,
    trailingActionExclusionWidth: CGFloat = 40
) -> [SidebarDragSourceExclusionZone] {
    var exclusions: [SidebarDragSourceExclusionZone] = []
    if runtimeAffordance.usesResetLeadingAction {
        exclusions.append(.leadingStrip(SidebarRowLayout.changedLauncherResetWidth + 12))
    }
    if hasLiveAudioExclusion {
        exclusions.append(
            .fixedRect(
                ShortcutSidebarAudioHitArea.frameInRow(
                    usesResetLeadingAction: runtimeAffordance.usesResetLeadingAction
                )
            )
        )
    }
    if dragHasTrailingActionExclusion {
        exclusions.append(.trailingStrip(trailingActionExclusionWidth))
    }
    return exclusions
}

enum ShortcutSidebarAudioHitArea {
    static let size: CGFloat = 22

    static func contentStartX(usesResetLeadingAction: Bool) -> CGFloat {
        guard usesResetLeadingAction else { return 0 }

        return SidebarRowLayout.changedLauncherResetWidth
            + SidebarRowLayout.changedLauncherResetTrailingGap
    }

    static func frameInRow(usesResetLeadingAction: Bool) -> CGRect {
        let x: CGFloat
        if usesResetLeadingAction {
            x = contentStartX(usesResetLeadingAction: true)
                + SidebarRowLayout.changedLauncherTitleLeading
        } else {
            x = SidebarRowLayout.leadingInset
                + SidebarRowLayout.faviconSize
                + SidebarRowLayout.iconTrailingSpacing
        }

        return CGRect(
            x: x,
            y: (SidebarRowLayout.rowHeight - size) / 2,
            width: size,
            height: size
        )
    }
}
extension String {
    func replacingPrefix(_ prefix: String, with replacement: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return replacement + String(dropFirst(prefix.count))
    }
}
