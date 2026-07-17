import Combine

@MainActor
final class BrowserNativeModalPresentationState: ObservableObject {
    @Published private(set) var presentation: BrowserNativeModalPresentation?

    func replace(with presentation: BrowserNativeModalPresentation?) {
        self.presentation = presentation
    }
}
