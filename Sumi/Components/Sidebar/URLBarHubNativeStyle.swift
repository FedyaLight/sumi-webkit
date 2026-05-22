import AppKit
import SwiftUI

enum URLBarHubNativeStyle {
    static let backgroundFallback = Color(nsColor: .windowBackgroundColor)
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let separator = Color(nsColor: .separatorColor)
    static let controlBackground = Color(nsColor: .controlBackgroundColor)
    static let hoveredControlBackground = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let accentBackground = Color(nsColor: .controlAccentColor)
    static let accentText = Color(nsColor: .alternateSelectedControlTextColor)
    static let destructiveText = Color(nsColor: .systemRed)
    static let destructiveBackground = Color(nsColor: .systemRed)
}
