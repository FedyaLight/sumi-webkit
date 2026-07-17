@MainActor
final class BrowserURLBarHubPresentationOwner {
    let presenter: URLBarHubPopoverPresenter

    init(presenter: URLBarHubPopoverPresenter) {
        self.presenter = presenter
    }

    func close(in windowState: BrowserWindowState) {
        presenter.close(in: windowState)
    }

    func present(
        in windowState: BrowserWindowState,
        context: URLBarHubBrowserContext
    ) {
        presenter.present(in: windowState, browserContext: context)
    }

    func toggle(
        in windowState: BrowserWindowState,
        context: URLBarHubBrowserContext
    ) {
        presenter.toggle(in: windowState, browserContext: context)
    }

    func isPresented(in windowState: BrowserWindowState) -> Bool {
        presenter.isPresented(in: windowState)
    }
}
