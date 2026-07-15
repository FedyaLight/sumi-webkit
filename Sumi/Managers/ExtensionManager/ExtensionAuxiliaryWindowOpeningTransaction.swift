import Foundation
import WebKit

/// Publishes one auxiliary Window and its initial Tab as a reentrant-safe,
/// two-phase transaction. Every WebKit callback boundary is followed by an
/// exact ledger/runtime revalidation.
@available(macOS 15.5, *)
@MainActor
final class ExtensionAuxiliaryWindowOpeningTransaction {
    private let ledger: ExtensionAuxiliaryWindowPublicationLedger
    private let resolver: ExtensionAuxiliaryWindowPublicationResolver
    private let retirement: ExtensionAuxiliaryWindowPublicationRetirement
    #if DEBUG
        private let debugEvent:
            @MainActor (ExtensionAuxiliaryPublicationDebugEvent) -> Void
    #endif

    #if DEBUG
        init(
            ledger: ExtensionAuxiliaryWindowPublicationLedger,
            resolver: ExtensionAuxiliaryWindowPublicationResolver,
            retirement: ExtensionAuxiliaryWindowPublicationRetirement,
            debugEvent: @escaping @MainActor (
                ExtensionAuxiliaryPublicationDebugEvent
            ) -> Void
        ) {
            self.ledger = ledger
            self.resolver = resolver
            self.retirement = retirement
            self.debugEvent = debugEvent
        }
    #else
        init(
            ledger: ExtensionAuxiliaryWindowPublicationLedger,
            resolver: ExtensionAuxiliaryWindowPublicationResolver,
            retirement: ExtensionAuxiliaryWindowPublicationRetirement
        ) {
            self.ledger = ledger
            self.resolver = resolver
            self.retirement = retirement
        }
    #endif

    @discardableResult
    func open(
        _ session: AuxiliaryWindowSession,
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?,
        shouldFocus: Bool
    ) -> Bool {
        guard ledger.isClosing(session) == false else { return false }

        if let existing = ledger.publication(for: session) {
            guard existing.represents(session) else { return false }
            if existing.tabReceipt.isCommitted,
               resolver.publicationIsCurrent(
                   existing,
                   session: session,
                   runtime: runtime,
                   control: control
               ) {
                return true
            }
            guard existing.tabReceipt.isPrepared == false else {
                return false
            }
            _ = retirement.retire(
                existing,
                session: session,
                runtime: runtime,
                windowQuery: nil,
                control: control,
                mode: .runtimeSuspension
            )
        }

        guard let publication = resolver.resolvePublication(
            for: session,
            runtime: runtime,
            control: control
        ) else {
            return false
        }
        guard resolver.projectionIsCurrent(
            publication,
            session: session,
            runtime: runtime,
            control: control
        ), ledger.insertPrepared(publication, for: session) else {
            _ = publication.tabReceipt.cancelBeforeWindowPublication()
            return false
        }

        publication.context.didOpenWindow(publication.adapter)
        #if DEBUG
            debugEvent(.didOpenWindow(sessionID: session.id))
        #endif
        guard isExactCurrent(
            publication,
            session: session,
            runtime: runtime,
            control: control,
            committed: false
        ) else {
            reject(publication, session: session, runtime: runtime, control: control)
            return false
        }

        guard publication.tabReceipt.commitOpen(runtime: runtime) else {
            reject(publication, session: session, runtime: runtime, control: control)
            return false
        }
        #if DEBUG
            debugEvent(.didOpenTab(
                sessionID: session.id,
                tabID: session.tab.id
            ))
        #endif
        guard isExactCurrent(
            publication,
            session: session,
            runtime: runtime,
            control: control,
            committed: true
        ) else {
            reject(publication, session: session, runtime: runtime, control: control)
            return false
        }

        if shouldFocus {
            guard let focusReceipt = control?
                .auxiliaryWindowSessionReceipt(for: session) else {
                reject(
                    publication,
                    session: session,
                    runtime: runtime,
                    control: control
                )
                return false
            }
            control?.recordAuxiliaryWindowSessionFocus(focusReceipt)
            guard isExactCurrent(
                publication,
                session: session,
                runtime: runtime,
                control: control,
                committed: true
            ) else {
                reject(publication, session: session, runtime: runtime, control: control)
                return false
            }
            publication.context.didFocusWindow(publication.adapter)
            #if DEBUG
                debugEvent(.didFocusWindow(sessionID: session.id))
            #endif
            guard isExactCurrent(
                publication,
                session: session,
                runtime: runtime,
                control: control,
                committed: true
            ), (publication.context.focusedWindow as AnyObject?)
                === publication.adapter else {
                reject(publication, session: session, runtime: runtime, control: control)
                return false
            }
        }

        guard isExactCurrent(
            publication,
            session: session,
            runtime: runtime,
            control: control,
            committed: true
        ) else {
            reject(publication, session: session, runtime: runtime, control: control)
            return false
        }
        return true
    }

    func focus(
        _ session: AuxiliaryWindowSession,
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) {
        guard let publication = committedPublication(
            for: session,
            runtime: runtime,
            control: control
        ), (publication.context.focusedWindow as AnyObject?)
            !== publication.adapter else {
            return
        }

        publication.context.didFocusWindow(publication.adapter)
        #if DEBUG
            debugEvent(.didFocusWindow(sessionID: session.id))
        #endif

        guard let current = committedPublication(
            for: session,
            runtime: runtime,
            control: control
        ), samePublication(current, publication),
              (publication.context.focusedWindow as AnyObject?)
                === publication.adapter else {
            guard ledger.containsExact(publication, for: session) else {
                return
            }
            _ = retirement.retire(
                publication,
                session: session,
                runtime: runtime,
                windowQuery: nil,
                control: control,
                mode: .terminal(restoreNormalFocus: false)
            )
            if let receipt = control?
                .auxiliaryWindowSessionReceipt(for: session) {
                control?.closeAuxiliaryWindowSession(receipt)
            }
            return
        }
    }

    func committedPublication(
        for session: AuxiliaryWindowSession,
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) -> ExtensionAuxiliaryWindowPublication? {
        guard let publication = ledger.publication(for: session),
              publication.tabReceipt.isCommitted,
              resolver.publicationIsCurrent(
                  publication,
                  session: session,
                  runtime: runtime,
                  control: control
              )
        else {
            return nil
        }
        return publication
    }

    private func isExactCurrent(
        _ publication: ExtensionAuxiliaryWindowPublication,
        session: AuxiliaryWindowSession,
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?,
        committed: Bool
    ) -> Bool {
        let receiptHasExpectedPhase = committed
            ? publication.tabReceipt.isCommitted
            : publication.tabReceipt.isPrepared
        return receiptHasExpectedPhase
            && ledger.containsExact(publication, for: session)
            && resolver.publicationIsCurrent(
                publication,
                session: session,
                runtime: runtime,
                control: control
            )
    }

    private func reject(
        _ publication: ExtensionAuxiliaryWindowPublication,
        session: AuxiliaryWindowSession,
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) {
        guard ledger.containsExact(publication, for: session) else { return }
        _ = retirement.retire(
            publication,
            session: session,
            runtime: runtime,
            windowQuery: nil,
            control: control,
            mode: .rejected
        )
    }

    private func samePublication(
        _ lhs: ExtensionAuxiliaryWindowPublication,
        _ rhs: ExtensionAuxiliaryWindowPublication
    ) -> Bool {
        lhs.sessionIdentity == rhs.sessionIdentity
            && lhs.adapter === rhs.adapter
            && lhs.tabReceipt === rhs.tabReceipt
    }
}
