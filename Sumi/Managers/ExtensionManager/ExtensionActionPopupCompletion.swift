import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupCompletion {
    private var handler: ((Error?) -> Void)?

    init(_ handler: @escaping (Error?) -> Void) {
        self.handler = handler
    }

    func settle(_ error: Error?) {
        guard let handler else { return }
        self.handler = nil
        handler(error)
    }
}
