import Foundation

@MainActor
final class BrowserProfileSwitchTransitionOwner {
    actor ProfileOps {
        func run(_ body: @MainActor () -> Bool) async -> Bool {
            await body()
        }
    }

    private let admission: BrowserProfileSwitchAdmission
    private let application: BrowserProfileSwitchApplication
    private let feedback: BrowserProfileSwitchFeedback
    private let cleanup: BrowserProfileSwitchCleanup
    private let profileOps = ProfileOps()

    init(
        admission: BrowserProfileSwitchAdmission,
        application: BrowserProfileSwitchApplication,
        feedback: BrowserProfileSwitchFeedback,
        cleanup: BrowserProfileSwitchCleanup
    ) {
        self.admission = admission
        self.application = application
        self.feedback = feedback
        self.cleanup = cleanup
    }

    func switchToProfile(
        _ profile: Profile,
        context: BrowserProfileSwitchContext,
        in windowState: BrowserWindowState?
    ) async {
        guard let receipt = admission.admitReference(to: profile.id) else {
            return
        }
        let shouldRunCleanup = await profileOps.run { [weak self] in
            guard let self,
                  let transition = self.admission.prepare(
                      profileID: profile.id,
                      receipt: receipt,
                      context: context,
                      requestedWindow: windowState
                  )
            else { return false }
            defer { self.admission.finish(transition) }

            let isAnimated = context.shouldAnimateTransition
            self.application.apply(
                profile,
                transition: transition,
                isAnimated: isAnimated
            )
            if context.shouldProvideFeedback {
                self.feedback.present(
                    for: profile,
                    in: transition.targetWindow
                )
            }
            if isAnimated {
                self.application.finishAnimationAfterDelay()
            }
            return true
        }

        guard shouldRunCleanup else { return }
        await cleanup.run(for: profile)
    }
}
