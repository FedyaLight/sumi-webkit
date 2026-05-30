import Foundation
import SwiftUI

@MainActor
final class WorkspaceThemeEditorPreview: ObservableObject {
    @Published var displayGradient: WorkspaceResolvedGradient = .default
    @Published private(set) var isEditing: Bool = false
    @Published var activePrimaryStopID: UUID?
    @Published var preferredPrimaryStopID: UUID?

    func setImmediate(_ gradient: WorkspaceResolvedGradient) {
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
        activePrimaryStopID = nil
    }
}
