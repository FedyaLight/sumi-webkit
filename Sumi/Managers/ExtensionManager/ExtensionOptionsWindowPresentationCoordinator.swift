import Foundation

@available(macOS 15.5, *)
@MainActor
enum ExtensionOptionsWindowPresentationCoordinator {
    static func present(
        service: ExtensionOptionsWindowService,
        invocation: ExtensionOptionsWindowCallbackComposition.Invocation,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let receipt = invocation.receipt
        let runtime = invocation.runtime
        guard runtime.isCurrent(receipt) else {
            completionHandler(CancellationError())
            return
        }
        let claim = service.issuePresentationClaim(
            for: receipt.evidence.extensionID,
            profileID: receipt.evidence.profileID
        )
        guard service.presentationIsCurrent(
            claim,
            receipt: receipt,
            runtime: runtime
        ) else {
            completionHandler(CancellationError())
            return
        }

        if runtime.websiteDataAdmission.isBlocked(
            profileID: receipt.evidence.profileID
        ) {
            Task { @MainActor [weak service] in
                guard let service,
                      service.presentationIsCurrent(
                          claim,
                          receipt: receipt,
                          runtime: runtime
                      ),
                      await runtime.websiteDataAdmission.wait(
                          profileID: receipt.evidence.profileID
                      ),
                      service.presentationIsCurrent(
                          claim,
                          receipt: receipt,
                          runtime: runtime
                      )
                else {
                    completionHandler(CancellationError())
                    return
                }
                commit(
                    service: service,
                    receipt: receipt,
                    runtime: runtime,
                    claim: claim,
                    completionHandler: completionHandler
                )
            }
            return
        }
        commit(
            service: service,
            receipt: receipt,
            runtime: runtime,
            claim: claim,
            completionHandler: completionHandler
        )
    }

    private static func commit(
        service: ExtensionOptionsWindowService,
        receipt: ExtensionOptionsWindowPresentationReceipt,
        runtime: ExtensionOptionsWindowCallbackRuntime,
        claim: ExtensionOptionsWindowPresentationClaim,
        completionHandler: @escaping (Error?) -> Void
    ) {
        ExtensionOptionsWindowPresentationTransaction(
            service: service,
            receipt: receipt,
            runtime: runtime,
            claim: claim
        ).commit(completionHandler: completionHandler)
    }
}
