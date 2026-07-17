import Combine

@MainActor
final class BrowserBookmarkEditorPresentationState: ObservableObject {
    @Published private(set) var request: SumiBookmarkEditorPresentationRequest?

    func present(_ request: SumiBookmarkEditorPresentationRequest) {
        self.request = request
    }

    func clear(_ expected: SumiBookmarkEditorPresentationRequest) {
        guard request?.id == expected.id else { return }
        request = nil
    }
}
