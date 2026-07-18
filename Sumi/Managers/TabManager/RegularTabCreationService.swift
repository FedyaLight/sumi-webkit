import Foundation
import WebKit

/// Owns the structural batch and active-selection phase around regular-tab
/// creation. Candidate construction and admitted publication stay below it.
@MainActor
final class RegularTabCreationService {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let creation: RegularTabCreationTransaction
    private let candidates: RegularTabCreationCandidateFactory
    private let selection: TabActiveSelectionOwner

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        creation: RegularTabCreationTransaction,
        candidates: RegularTabCreationCandidateFactory,
        selection: TabActiveSelectionOwner
    ) {
        self.structuralLookup = structuralLookup
        self.creation = creation
        self.candidates = candidates
        self.selection = selection
    }

    func create(
        url: String,
        in space: Space?,
        activate: Bool,
        webViewConfigurationOverride: WKWebViewConfiguration?,
        webExtensionContextOverride: WKWebExtensionContext?,
        executionProfileID: UUID?,
        regularInsertionIndex: Int?,
        prepareBeforePublication: @MainActor (Tab) -> Void
    ) -> Tab {
        structuralLookup.withTransaction {
            guard let newTab = creation.create(
                url: url,
                in: space,
                webViewConfigurationOverride: webViewConfigurationOverride,
                webExtensionContextOverride: webExtensionContextOverride,
                executionProfileID: executionProfileID,
                regularInsertionIndex: regularInsertionIndex,
                prepareBeforePublication: prepareBeforePublication
            ) else { return candidates.makeFallbackTab() }
            if activate { selection.setActiveTab(newTab) }
            return newTab
        }
    }

    func createPopup(
        in space: Space?,
        activate: Bool,
        webViewConfigurationOverride: WKWebViewConfiguration?,
        executionProfileID: UUID?,
        regularInsertionIndex: Int?
    ) -> Tab {
        structuralLookup.withTransaction {
            guard let newTab = creation.createPopup(
                in: space,
                webViewConfigurationOverride: webViewConfigurationOverride,
                executionProfileID: executionProfileID,
                regularInsertionIndex: regularInsertionIndex
            ) else { return candidates.makeFallbackTab() }
            if activate { selection.setActiveTab(newTab) }
            return newTab
        }
    }
}
