//
//  SpaceViewPreferences.swift
//  Sumi
//

import SwiftUI

extension SpaceView {
    var dropGuideAnimation: Animation? {
        isInteractive ? .easeInOut(duration: 0.14) : nil
    }

    var sidebarContentMutationAnimation: Animation? {
        isInteractive && !reduceMotion && !dragState.isCompletingDrop
            ? SidebarDropMotion.contentLayout
            : nil
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
