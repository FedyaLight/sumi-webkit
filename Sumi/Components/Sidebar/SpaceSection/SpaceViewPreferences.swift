//
//  SpaceViewPreferences.swift
//  Sumi
//

import SwiftUI

extension SpaceView {


    var sidebarContentMutationAnimation: Animation? {
        isInteractive && !reduceMotion && !sumiSettings.shouldReduceChromeMotion && !dragState.isCompletingDrop
            ? SidebarDropMotion.contentLayout
            : nil
    }



    var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}
