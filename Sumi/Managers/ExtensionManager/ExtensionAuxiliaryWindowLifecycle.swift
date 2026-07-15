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
            ledger: ExtensionAuxiliaryWindowPublicationLedger,
            publications: ExtensionAuxiliaryWindowPublicationQuery,
            adapterStore: ExtensionBrowserAdapterStore,
            profileRuntime: ExtensionProfileRuntime,
            tabProfiles: any ExtensionTabProfileResolving,
            windowProfileID: @escaping @MainActor (BrowserWindowState) -> UUID?,
            tabPublication: any ExtensionAuxiliaryTabPublicationPreparing,
            normalWindows: ExtensionNormalWindowLifecycle,
            debugEvent: @escaping @MainActor (
                ExtensionAuxiliaryPublicationDebugEvent
            ) -> Void
        ) {
            let resolver = ExtensionAuxiliaryWindowPublicationResolver(
                adapterStore: adapterStore,
                profileRuntime: profileRuntime,
                tabProfiles: tabProfiles,
                windowProfileID: windowProfileID,
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
            self.publications = publications
        }
    #else
        init(
            ledger: ExtensionAuxiliaryWindowPublicationLedger,
            publications: ExtensionAuxiliaryWindowPublicationQuery,
            adapterStore: ExtensionBrowserAdapterStore,
            profileRuntime: ExtensionProfileRuntime,
            tabProfiles: any ExtensionTabProfileResolving,
            windowProfileID: @escaping @MainActor (BrowserWindowState) -> UUID?,
            tabPublication: any ExtensionAuxiliaryTabPublicationPreparing,
            normalWindows: ExtensionNormalWindowLifecycle
        ) {
            let resolver = ExtensionAuxiliaryWindowPublicationResolver(
                adapterStore: adapterStore,
                profileRuntime: profileRuntime,
                tabProfiles: tabProfiles,
                windowProfileID: windowProfileID,
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
            self.publications = publications
        }
    #endif

    @discardableResult
    func opened(
        _ session: AuxiliaryWindowSession,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) -> Bool {
        opening.open(
            session,
            control: control,
            shouldFocus: session.shouldActivateApp
        )
    }

    func focused(
        _ session: AuxiliaryWindowSession,
        control: (any ExtensionAuxiliaryWindowControl)?
    ) {
        opening.focus(session, control: control)
    }

    func closed(
        _ session: AuxiliaryWindowSession,
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
            windowQuery: windowQuery,
            control: nil,
            mode: .terminal(restoreNormalFocus: true)
        )
    }

    /// Closes old-generation owner-context publications while native sessions
    /// remain alive for exact republishing into the next generation.
    func suspendForRuntimeReload(
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
                windowQuery: nil,
                control: control,
                mode: .runtimeSuspension
            )
        }
        return sessions
    }

    func republishAfterRuntimeReload(
        _ sessions: [AuxiliaryWindowSession],
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
                control: control,
                shouldFocus: NSApp.keyWindow === session.window
            )
            guard shouldContinue() else { return }
            if reopened == false,
               let receipt = control.auxiliaryWindowSessionReceipt(
                for: session
               ) {
                control.closeAuxiliaryWindowSession(receipt)
            }
        }
    }

    /// Retires the extension-visible graph before controllers/contexts leave.
    /// Later native teardown sees an empty ledger and cannot duplicate closes.
    func closeAllForRuntimeTeardown(
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
                windowQuery: nil,
                control: control,
                mode: .terminal(restoreNormalFocus: false)
            )
        }
    }
}
