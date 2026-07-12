import AppKit
import Foundation
import WebKit

/// Coordinates auxiliary publication lifetime across native session close,
/// extension-runtime reload, and terminal runtime teardown. The opening
/// transaction owns WebKit callback ordering; this type owns session scope.
@available(macOS 15.5, *)
@MainActor
final class ExtensionAuxiliaryWindowLifecycle {
    private let ledger: ExtensionAuxiliaryWindowPublicationLedger
    private let resolver: ExtensionAuxiliaryWindowPublicationResolver
    private let retirement: ExtensionAuxiliaryWindowPublicationRetirement
    private let opening: ExtensionAuxiliaryWindowOpeningTransaction
    let publications: ExtensionAuxiliaryWindowPublicationQuery

    #if DEBUG
        init(
            adapterStore: ExtensionBrowserAdapterStore,
            profileRuntime: ExtensionProfileRuntime,
            tabPublication: any ExtensionAuxiliaryTabPublicationPreparing,
            normalWindows: ExtensionNormalWindowLifecycle,
            debugEvent: @escaping @MainActor (
                ExtensionAuxiliaryPublicationDebugEvent
            ) -> Void
        ) {
            let ledger = ExtensionAuxiliaryWindowPublicationLedger()
            let resolver = ExtensionAuxiliaryWindowPublicationResolver(
                adapterStore: adapterStore,
                profileRuntime: profileRuntime,
                tabPublication: tabPublication
            )
            let retirement = ExtensionAuxiliaryWindowPublicationRetirement(
                ledger: ledger,
                adapterStore: adapterStore,
                publicationResolver: resolver,
                normalWindows: normalWindows,
                debugEvent: debugEvent
            )
            self.ledger = ledger
            self.resolver = resolver
            self.retirement = retirement
            let opening = ExtensionAuxiliaryWindowOpeningTransaction(
                ledger: ledger,
                resolver: resolver,
                retirement: retirement,
                debugEvent: debugEvent
            )
            self.opening = opening
            publications = ExtensionAuxiliaryWindowPublicationQuery(
                ledger: ledger,
                resolver: resolver,
                opening: opening
            )
        }
    #else
        init(
            adapterStore: ExtensionBrowserAdapterStore,
            profileRuntime: ExtensionProfileRuntime,
            tabPublication: any ExtensionAuxiliaryTabPublicationPreparing,
            normalWindows: ExtensionNormalWindowLifecycle
        ) {
            let ledger = ExtensionAuxiliaryWindowPublicationLedger()
            let resolver = ExtensionAuxiliaryWindowPublicationResolver(
                adapterStore: adapterStore,
                profileRuntime: profileRuntime,
                tabPublication: tabPublication
            )
            let retirement = ExtensionAuxiliaryWindowPublicationRetirement(
                ledger: ledger,
                adapterStore: adapterStore,
                publicationResolver: resolver,
                normalWindows: normalWindows
            )
            self.ledger = ledger
            self.resolver = resolver
            self.retirement = retirement
            let opening = ExtensionAuxiliaryWindowOpeningTransaction(
                ledger: ledger,
                resolver: resolver,
                retirement: retirement
            )
            self.opening = opening
            publications = ExtensionAuxiliaryWindowPublicationQuery(
                ledger: ledger,
                resolver: resolver,
                opening: opening
            )
        }
    #endif

    @discardableResult
    func opened(
        _ session: AuxiliaryWindowSession,
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) -> Bool {
        opening.open(
            session,
            runtime: runtime,
            control: control,
            shouldFocus: session.shouldActivateApp
        )
    }

    func focused(
        _ session: AuxiliaryWindowSession,
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) {
        opening.focus(session, runtime: runtime, control: control)
    }

    func closed(
        _ session: AuxiliaryWindowSession,
        runtime: ExtensionManagerRuntime,
        windowQuery: (any ExtensionWindowQuery)?
    ) {
        guard let publication = ledger.publication(for: session) else {
            retirement.removeUnpublishedWindowAdapter(for: session)
            return
        }
        guard publication.represents(session) else { return }
        _ = retirement.retire(
            publication,
            session: session,
            runtime: runtime,
            windowQuery: windowQuery,
            control: nil,
            mode: .terminal(restoreNormalFocus: true)
        )
    }

    /// Closes old-generation owner-context publications while native sessions
    /// remain alive for exact republishing into the next generation.
    func suspendForRuntimeReload(
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) -> [AuxiliaryWindowSession] {
        guard let control else { return [] }
        let sessions = ledger.sessionIDs.compactMap {
            control.auxiliaryWindowSession(for: $0)
        }
        for session in sessions {
            guard let publication = ledger.publication(for: session),
                  publication.represents(session) else {
                continue
            }
            _ = retirement.retire(
                publication,
                session: session,
                runtime: runtime,
                windowQuery: nil,
                control: control,
                mode: .runtimeSuspension
            )
        }
        return sessions
    }

    func republishAfterRuntimeReload(
        _ sessions: [AuxiliaryWindowSession],
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?,
        continuingWhile shouldContinue: @MainActor () -> Bool = { true }
    ) {
        guard let control else { return }
        for session in sessions {
            guard shouldContinue(),
                  control.auxiliaryWindowSession(for: session.id)
                    === session else {
                continue
            }
            let reopened = opening.open(
                session,
                runtime: runtime,
                control: control,
                shouldFocus: NSApp.keyWindow === session.window
            )
            guard shouldContinue() else { return }
            if reopened == false,
               control.auxiliaryWindowSession(for: session.id) === session {
                control.closeAuxiliaryWindowSession(session)
            }
        }
    }

    /// Retires the extension-visible graph before controllers/contexts leave.
    /// Later native teardown sees an empty ledger and cannot duplicate closes.
    func closeAllForRuntimeTeardown(
        runtime: ExtensionManagerRuntime,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) {
        guard let control else { return }
        let sessions = ledger.sessionIDs.compactMap {
            control.auxiliaryWindowSession(for: $0)
        }
        for session in sessions {
            guard let publication = ledger.publication(for: session),
                  publication.represents(session) else {
                continue
            }
            _ = retirement.retire(
                publication,
                session: session,
                runtime: runtime,
                windowQuery: nil,
                control: control,
                mode: .terminal(restoreNormalFocus: false)
            )
        }
    }
}
