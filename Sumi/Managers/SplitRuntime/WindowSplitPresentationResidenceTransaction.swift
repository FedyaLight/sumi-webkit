import Foundation

@MainActor
enum WindowSplitPresentationResidenceTransaction {
    case activation(ShortcutPresentationActivationReceipt)
    case displayedBinding(DisplayedWindowSplitPresentationResidenceTransaction)

    var shortcutWitnesses: [WindowSplitPresentationShortcutWitness] {
        switch self {
        case .activation(let receipt):
            return receipt.tabs.enumerated().map { index, tab in
                .activated(
                    request: receipt.requests[index],
                    tab: tab
                )
            }
        case .displayedBinding(let transaction):
            return transaction.shortcutWitnesses
        }
    }

    func stagePrepared() -> Bool {
        switch self {
        case .activation(let receipt):
            guard receipt.stage() else { return false }
            guard receipt.canPublish() else {
                receipt.rollback()
                return false
            }
            return true
        case .displayedBinding(let transaction):
            return transaction.stagePrepared()
        }
    }

    func preparedIdentityIsExact() -> Bool {
        switch self {
        case .activation(let receipt): receipt.canPublish()
        case .displayedBinding(let transaction):
            transaction.preparedIdentityIsExact()
        }
    }

    func admitCatalogIdentityHandoff(
        _ handoff: ShortcutPresentationCatalogIdentityHandoff
    ) -> Bool {
        switch self {
        case .activation(let receipt):
            receipt.admitCatalogIdentityHandoff(handoff)
        case .displayedBinding(let transaction):
            transaction.admitCatalogIdentityHandoff(handoff)
        }
    }

    func acceptBoundIdentity() -> Bool {
        switch self {
        case .activation(let receipt): receipt.canPublish()
        case .displayedBinding(let transaction):
            transaction.acceptBoundIdentity()
        }
    }

    func canPublish() -> Bool {
        switch self {
        case .activation(let receipt): receipt.canPublish()
        case .displayedBinding(let transaction): transaction.canPublish()
        }
    }

    func publish() {
        switch self {
        case .activation(let receipt): receipt.publish()
        case .displayedBinding(let transaction): transaction.publish()
        }
    }

    func publishedModelIsExact() -> Bool {
        switch self {
        case .activation(let receipt): receipt.publishedModelIsExact()
        case .displayedBinding(let transaction):
            transaction.publishedModelIsExact()
        }
    }

    func rollback() {
        switch self {
        case .activation(let receipt): receipt.rollback()
        case .displayedBinding(let transaction): transaction.rollback()
        }
    }

    func abandonForTerminalDrain() {
        switch self {
        case .activation(let receipt): receipt.abandonForTerminalDrain()
        case .displayedBinding(let transaction):
            transaction.abandonForTerminalDrain()
        }
    }

    func forfeitPreservingCurrent() {
        switch self {
        case .activation(let receipt): receipt.forfeitPreservingCurrent()
        case .displayedBinding(let transaction):
            transaction.forfeitPreservingCurrent()
        }
    }
}
