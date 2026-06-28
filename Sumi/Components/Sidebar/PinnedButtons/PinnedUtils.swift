//
//  PinnedUtils.swift
//  Sumi
//
//

import SwiftUI

enum PinnedTabsConfiguration {
    case large

    var faviconHeight: CGFloat {
        20
    }

    var minWidth: CGFloat {
        47
    }

    var height: CGFloat {
        47
    }

    var cornerRadius: CGFloat {
        12
    }

    var strokeWidth: CGFloat {
        2
    }

    var outlineMaskBleed: CGFloat {
        strokeWidth + 1
    }

    var gridSpacing: CGFloat { 7 }
}
