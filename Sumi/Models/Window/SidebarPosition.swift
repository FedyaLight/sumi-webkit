import Foundation

enum SidebarPosition: String, CaseIterable, Identifiable {
    case left
    case right

    var id: String { rawValue }
}
