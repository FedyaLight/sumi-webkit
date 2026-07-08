//
//  TabFaviconPresentation.swift
//  Sumi
//
//

import AppKit
import Foundation

/// Model-neutral favicon representation for `Tab`.
///
/// `Tab` publishes this instead of a `SwiftUI.Image` so the model layer has no SwiftUI
/// dependency. The UI layer maps it to `SwiftUI.Image` for display; see
/// `Sumi/Components/TabFaviconPresentation+Image.swift`.
enum TabFaviconPresentation: Equatable {
    /// An SF Symbol, used for placeholders and Sumi-native surfaces (settings/history/bookmarks/globe).
    case systemSymbol(String)
    /// A resolved bitmap favicon loaded from the favicon cache/pipeline.
    case bitmap(NSImage)

    static func == (lhs: TabFaviconPresentation, rhs: TabFaviconPresentation) -> Bool {
        switch (lhs, rhs) {
        case (.systemSymbol(let lhsName), .systemSymbol(let rhsName)):
            return lhsName == rhsName
        case (.bitmap(let lhsImage), .bitmap(let rhsImage)):
            return lhsImage === rhsImage
        default:
            return false
        }
    }
}
