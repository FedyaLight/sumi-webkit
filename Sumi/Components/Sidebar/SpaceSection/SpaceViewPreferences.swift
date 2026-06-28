//
//  SpaceViewPreferences.swift
//  Sumi
//

import SwiftUI

extension SpaceView {
    var sidebarContentMutationAnimation: Animation? {
        guard isInteractive,
              !reduceMotion,
              !sumiSettings.shouldReduceChromeMotion,
              !dragState.isCompletingDrop
        else {
            return nil
        }
        return SidebarMotionPolicy.folderLayoutAnimation(
            for: SidebarMotionPolicy.currentMode(
                reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
            )
        )
    }

    var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}
