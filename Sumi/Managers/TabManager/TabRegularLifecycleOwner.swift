import Foundation
import SumiDomain
import WebKit

@MainActor
final class TabRegularLifecycleOwner {
    private let publication: RegularTabPublicationTransaction
    private let glanceAdoption: GlanceTabAdoptionTransaction
    private let creation: RegularTabCreationService

    init(
        publication: RegularTabPublicationTransaction,
        glanceAdoption: GlanceTabAdoptionTransaction,
        creation: RegularTabCreationService
    ) {
        self.publication = publication
        self.glanceAdoption = glanceAdoption
        self.creation = creation
    }

    @discardableResult
    func addTab(
        _ tab: Tab,
        regularInsertionIndex: Int? = nil,
        admissionProfileIDs: Set<UUID>? = nil
    ) -> Bool {
        publication.add(
            tab,
            regularInsertionIndex: regularInsertionIndex,
            admissionProfileIDs: admissionProfileIDs
        )
    }

    @discardableResult
    func adoptGlanceTab(
        _ tab: Tab,
        sourceTab: Tab?,
        in space: Space? = nil
    ) -> Tab? {
        glanceAdoption.adopt(tab, sourceTab: sourceTab, in: space)
    }

    @discardableResult
    func createNewTab(
        url: String = SumiSurface.emptyTabURL.absoluteString,
        in space: Space? = nil,
        activate: Bool = true,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil,
        webExtensionContextOverride: WKWebExtensionContext? = nil,
        executionProfileID: UUID? = nil,
        regularInsertionIndex: Int? = nil
    ) -> Tab {
        creation.create(
            url: url,
            in: space,
            activate: activate,
            webViewConfigurationOverride: webViewConfigurationOverride,
            webExtensionContextOverride: webExtensionContextOverride,
            executionProfileID: executionProfileID,
            regularInsertionIndex: regularInsertionIndex
        )
    }

    @discardableResult
    func createPopupTab(
        in space: Space? = nil,
        activate: Bool = true,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil,
        executionProfileID: UUID? = nil,
        regularInsertionIndex: Int? = nil
    ) -> Tab {
        creation.createPopup(
            in: space,
            activate: activate,
            webViewConfigurationOverride: webViewConfigurationOverride,
            executionProfileID: executionProfileID,
            regularInsertionIndex: regularInsertionIndex
        )
    }
}
