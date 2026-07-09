import Foundation

public enum BrowserWindowSelectionHistoryItem: Equatable, Sendable {
    case regularTab(UUID)
    case shortcutPin(UUID)
}
