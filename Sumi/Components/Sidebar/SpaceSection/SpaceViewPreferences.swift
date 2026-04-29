//
//  SpaceViewPreferences.swift
//  Sumi
//

import SwiftUI

struct TabPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

@MainActor
final class SidebarSelectionScrollGuard {
    private var lockedUntil: Date = .distantPast

    func lock(for duration: TimeInterval = 0.3) {
        lockedUntil = Date().addingTimeInterval(duration)
    }

    var isLocked: Bool {
        Date() < lockedUntil
    }
}

@MainActor
final class SidebarPreferenceUpdateCoalescer {
    private var lastTabPositionUpdate: Date = .distantPast

    func shouldApplyTabPositionUpdate(minimumInterval: TimeInterval = 0.1) -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastTabPositionUpdate) > minimumInterval else { return false }
        lastTabPositionUpdate = now
        return true
    }
}

extension SpaceView {
    var dropGuideAnimation: Animation? {
        isInteractive ? .easeInOut(duration: 0.14) : nil
    }

    @ViewBuilder
    func dropLine(isFolder: Bool = false) -> some View {
        SidebarInsertionGuide()
            .padding(.horizontal, isFolder ? 16 : 8)
    }

    var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}
