import Foundation

/// Owns the single per-window chrome toast and its auto-dismiss timer.
@MainActor
@Observable
final class WindowToastPresentationOwner {
    /// Lightweight, per-window chrome feedback. Only one toast is mounted at a time.
    private(set) var toast: BrowserToast?

    @ObservationIgnored private var toastDismissTask: Task<Void, Never>?

    func present(_ nextToast: BrowserToast) {
        toastDismissTask?.cancel()
        toast = nextToast

        toastDismissTask = Task { [weak self, id = nextToast.id, duration = nextToast.duration] in
            let nanoseconds = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.dismiss(id: id)
            }
        }
    }

    func dismiss(id: BrowserToast.ID? = nil) {
        if let id, toast?.id != id { return }
        toastDismissTask?.cancel()
        toastDismissTask = nil
        toast = nil
    }
}
