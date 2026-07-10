import Foundation
import SumiWebRuntime

@MainActor
final class WindowWebContentHoverSession {
    private let mutationGate: WindowWebContentCompositorMutationGate
    private var tab: Tab?
    private var tabID: UUID?
    private var registration: WebViewCompositorContainerRegistration?
    private var deliver: ((String?) -> Void)?

    init(mutationGate: WindowWebContentCompositorMutationGate) {
        self.mutationGate = mutationGate
    }

    func update(
        tabID: UUID?,
        tab: Tab?,
        registration: WebViewCompositorContainerRegistration,
        deliver: @escaping (String?) -> Void
    ) {
        self.deliver = deliver
        self.registration = registration

        guard tabID != nil else {
            detachCurrentTab()
            deliver(nil)
            return
        }

        guard self.tabID != tabID || self.tab !== tab else { return }
        detachCurrentTab()
        self.tabID = tabID
        self.tab = tab
        tab?.onLinkHover = { [weak self] href in
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let registration = self.registration,
                      self.mutationGate.owns(registration)
                else {
                    return
                }
                self.deliver?(href)
            }
        }
    }

    func invalidate() {
        detachCurrentTab()
        registration = nil
        deliver = nil
    }

    private func detachCurrentTab() {
        tab?.onLinkHover = nil
        tab = nil
        tabID = nil
    }
}
