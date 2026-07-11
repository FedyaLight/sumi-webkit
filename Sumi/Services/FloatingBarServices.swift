/// Behavior-free floating-bar capability group. Presentation state, commit
/// routing, and UI-context construction remain independently testable.
@MainActor
struct FloatingBarServices {
    let presentation: FloatingBarPresentationService
    let commit: FloatingBarCommitService
    let browserContext: FloatingBarBrowserContextFactory
}
