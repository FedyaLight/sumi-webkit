//
//  TabFaviconPresentation+Image.swift
//  Sumi
//
//

import SwiftUI

/// UI-layer mapping from the model-neutral `TabFaviconPresentation` to `SwiftUI.Image`.
///
/// `Tab` (in `Sumi/Models/Tab/`) has no SwiftUI dependency and publishes
/// `faviconPresentation` instead. Views read `tab.favicon` here to get a displayable
/// `Image`, keeping SwiftUI entirely out of the model layer.
extension Tab {
    var favicon: SwiftUI.Image {
        switch faviconPresentation {
        case .systemSymbol(let name):
            return Image(systemName: name)
        case .bitmap(let image):
            return Image(nsImage: image)
        }
    }

}
