import Foundation

@MainActor
final class DisplayedShortcutResidenceContribution {
    enum PreparedLookup {
        case exactSource
        case absentFresh
    }

    struct Entry {
        let window: BrowserWindowState
        let pinID: UUID
        let tab: Tab
        let page: LiveShortcutPresentationPageReceipt
        let source: ShortcutSplitLauncherTabReceipt
        let target: ShortcutBindingIdentity
        let targetFolderID: UUID?
        let preparedLookup: PreparedLookup
    }

    private let pin: ShortcutPin
    private let registry: LiveShortcutTabRegistry
    private let membership: TabCollectionMembershipOwner
    private let residences: LiveShortcutPresentationResidenceTransaction
    private let entries: [Entry]

    init?(
        pin: ShortcutPin,
        registry: LiveShortcutTabRegistry,
        membership: TabCollectionMembershipOwner,
        residences: LiveShortcutPresentationResidenceTransaction,
        entries: [Entry]
    ) {
        let slots = Set(entries.map {
            ShortcutPresentationSlot(windowID: $0.window.id, pinID: $0.pinID)
        })
        guard entries.isEmpty == false,
              slots.count == entries.count,
              entries.allSatisfy({ $0.pinID == pin.id }) else { return nil }
        self.pin = pin
        self.registry = registry
        self.membership = membership
        self.residences = residences
        self.entries = entries
    }

    func prepare(
        _ requests: [ShortcutPresentationActivationService.Request],
        preview: ShortcutPresentationCatalogInsertionPreview
    ) -> PreparedDisplayedShortcutResidenceContribution? {
        guard preview.resolvePin(withID: pin.id, canonical: { nil }) === pin,
              preparedIdentityIsExact() else { return nil }
        var selections: [PreparedDisplayedShortcutResidenceContribution.Selection]
            = []
        var remaining: [ShortcutPresentationActivationService.Request] = []
        for request in requests {
            guard request.pinID == pin.id else {
                selections.append(.activation(remaining.count))
                remaining.append(request)
                continue
            }
            guard let index = entries.firstIndex(where: {
                $0.window.id == request.windowID
            }), entries[index].page.page.spaceID
                == (pin.spaceId ?? request.presentationSpaceID) else { return nil }
            selections.append(.contributed(index))
        }
        return PreparedDisplayedShortcutResidenceContribution(
            contribution: self,
            selections: selections,
            remainder: DisplayedShortcutActivationRemainder(
                excludingPinID: pin.id,
                requests: remaining
            )
        )
    }

    func preparedIdentityIsExact() -> Bool {
        residences.validateForStaging() && entries.allSatisfy { entry in
            guard entry.source.accepts(entry.tab),
                  registry.entry(containing: entry.tab) == nil,
                  registry.tab(for: entry.pinID, in: entry.window.id) == nil
            else { return false }
            switch entry.preparedLookup {
            case .exactSource:
                return membership.lookupContainsExact(entry.tab)
            case .absentFresh:
                return membership.tab(for: entry.tab.id) == nil
            }
        }
    }

    func boundIdentityIsExact() -> Bool {
        residences.stagedModelIsExact() && entries.allSatisfy(boundEntryIsExact)
    }

    func terminalIdentityIsExact() -> Bool {
        entries.allSatisfy { entry in
            boundEntryIsExact(entry)
                && membership.lookupContainsExact(entry.tab)
        }
    }

    func entry(at index: Int) -> Entry? {
        entries.indices.contains(index) ? entries[index] : nil
    }

    private func boundEntryIsExact(_ entry: Entry) -> Bool {
        guard let current = registry.entry(containing: entry.tab),
              current.windowId == entry.window.id,
              current.pinId == entry.pinID,
              current.tab === entry.tab,
              current.presentationPage == entry.page,
              ShortcutBindingIdentity(tab: entry.tab) == entry.target,
              entry.tab.folderId == entry.targetFolderID else { return false }
        switch entry.preparedLookup {
        case .exactSource:
            return membership.lookupContainsExact(entry.tab)
        case .absentFresh:
            return membership.lookupContainsNone(of: [entry.tab.id])
                || membership.lookupContainsExact(entry.tab)
        }
    }
}

private struct ShortcutPresentationSlot: Hashable {
    let windowID: UUID
    let pinID: UUID
}
