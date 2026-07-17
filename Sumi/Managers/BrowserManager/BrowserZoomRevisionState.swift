import Combine

@MainActor
final class BrowserZoomRevisionState: ObservableObject {
    @Published private(set) var revision = 0

    func publishChange() {
        revision &+= 1
    }
}
