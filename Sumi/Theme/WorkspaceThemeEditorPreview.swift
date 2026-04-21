import Foundation
import SwiftUI

@MainActor
final class WorkspaceThemeEditorPreview: ObservableObject {
    @Published var displayGradient: SpaceGradient = .default
    @Published private(set) var isEditing: Bool = false
    @Published var isAnimating: Bool = false
    @Published var activePrimaryNodeID: UUID?
    @Published var preferredPrimaryNodeID: UUID?

    func setImmediate(_ gradient: SpaceGradient) {
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            displayGradient = gradient
        }
    }

    func beginInteractivePreview() {
        isEditing = true
    }

    func endInteractivePreview() {
        isEditing = false
        activePrimaryNodeID = nil
    }
}
