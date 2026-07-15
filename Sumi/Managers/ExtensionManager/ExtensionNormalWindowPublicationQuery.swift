import Foundation

/// Read-only normal-window publication query.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalWindowPublicationQuery {
    private let ledger: ExtensionNormalWindowPublicationLedger
    private let validator: ExtensionNormalWindowPublicationValidator

    init(
        ledger: ExtensionNormalWindowPublicationLedger,
        validator: ExtensionNormalWindowPublicationValidator
    ) {
        self.ledger = ledger
        self.validator = validator
    }

    func tabPublicationIsCurrent(_ tab: Tab, profileID: UUID) -> Bool {
        if validator.canPublishWithoutNormalWindow(tab) {
            return validator.profileID(for: tab) == profileID
        }
        guard ledger.acceptsPublishedReads,
              let window = validator.preferredWindow(for: tab),
              let published = ledger.publication(for: window.id),
              published.projection.windowIdentity == ObjectIdentifier(window),
              published.projection.profileID == profileID,
              validator.profileID(for: tab) == profileID
        else { return false }
        return validator.validate(
            published.projection,
            for: window,
            publicationStage: ledger.publicationStage
        )
    }

    func windowPublicationIsCurrent(
        _ window: BrowserWindowState,
        selectedTab: Tab,
        profileID: UUID
    ) -> Bool {
        guard ledger.acceptsPublishedReads,
              let published = ledger.publication(for: window.id),
              published.projection.windowIdentity == ObjectIdentifier(window),
              published.projection.selectedTabIdentity
                == ObjectIdentifier(selectedTab),
              published.projection.selectedTabID == selectedTab.id,
              published.projection.profileID == profileID
        else { return false }
        return validator.validate(
            published.projection,
            for: window,
            publicationStage: ledger.publicationStage
        )
    }

    func publishedAdapter(
        for window: BrowserWindowState,
        profileID: UUID
    ) -> ExtensionWindowAdapter? {
        guard ledger.acceptsPublishedReads,
              let published = ledger.publication(for: window.id),
              published.projection.windowIdentity == ObjectIdentifier(window),
              published.projection.profileID == profileID,
              validator.validate(
                  published.projection,
                  for: window,
                  publicationStage: ledger.publicationStage
              )
        else { return nil }
        return published.projection.windowAdapter
    }
}
