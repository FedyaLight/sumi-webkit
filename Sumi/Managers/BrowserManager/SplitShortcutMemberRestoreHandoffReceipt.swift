/// Prepared exact-window participant for the restore-only visual handoff. It
/// consumes one terminal presentation receipt and cannot publish twice or for
/// a same-ID replacement window.
@MainActor
final class SplitShortcutMemberRestoreHandoffReceipt:
    WindowSplitPresentationTerminalParticipant {
    private enum State {
        case prepared
        case settled
    }

    let targetWindow: BrowserWindowState
    private let publish: (BrowserWindowState) -> Void
    private var state = State.prepared

    init(
        window: BrowserWindowState,
        publish: @escaping (BrowserWindowState) -> Void
    ) {
        targetWindow = window
        self.publish = publish
    }

    func publish(after receipt: WindowSplitPresentationTerminalWindowReceipt) {
        guard case .prepared = state,
              receipt.matches(targetWindow) else { return }
        state = .settled
        publish(targetWindow)
    }
}
