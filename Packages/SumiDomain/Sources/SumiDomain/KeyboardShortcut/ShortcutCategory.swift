import Foundation

public enum ShortcutCategory: String, CaseIterable, Hashable, Codable, Sendable {
    case navigation = "navigation"
    case tabs = "tabs"
    case spaces = "spaces"
    case window = "window"
    case tools = "tools"

    public var displayName: String {
        switch self {
        case .navigation: return "Navigation"
        case .tabs: return "Tabs"
        case .spaces: return "Spaces"
        case .window: return "Window"
        case .tools: return "Tools"
        }
    }

    public var icon: String {
        switch self {
        case .navigation: return "arrow.left.arrow.right"
        case .tabs: return "doc.on.doc"
        case .spaces: return "rectangle.3.group"
        case .window: return "macwindow"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}
