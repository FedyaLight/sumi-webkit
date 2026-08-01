import Combine
import Foundation

/// Bridges nested SwiftUI settings routes to the real AppKit window toolbar.
/// The closures stay transient and are never part of persisted settings state.
@MainActor
final class SettingsWindowToolbarOwner: ObservableObject {
    struct Presentation: Equatable {
        var title: String
        var canGoBack: Bool
        var canGoForward: Bool
    }

    @Published private(set) var presentation = Presentation(
        title: "",
        canGoBack: false,
        canGoForward: false
    )

    private var backAction: (() -> Void)?
    private var forwardAction: (() -> Void)?

    func showRoot(title: String) {
        show(title: title, backAction: nil, forwardAction: nil)
    }

    func show(
        title: String,
        backAction: (() -> Void)?,
        forwardAction: (() -> Void)? = nil
    ) {
        self.backAction = backAction
        self.forwardAction = forwardAction
        let updated = Presentation(
            title: title,
            canGoBack: backAction != nil,
            canGoForward: forwardAction != nil
        )
        if presentation != updated {
            presentation = updated
        }
    }

    func goBack() {
        backAction?()
    }

    func goForward() {
        forwardAction?()
    }
}
