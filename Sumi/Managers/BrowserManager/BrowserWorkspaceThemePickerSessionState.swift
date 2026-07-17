import Combine

@MainActor
final class BrowserWorkspaceThemePickerSessionState: ObservableObject {
    @Published private(set) var session: WorkspaceThemePickerSession?

    func present(_ session: WorkspaceThemePickerSession) {
        self.session = session
    }

    func clear(_ expected: WorkspaceThemePickerSession) {
        guard session?.id == expected.id else { return }
        session = nil
    }
}
