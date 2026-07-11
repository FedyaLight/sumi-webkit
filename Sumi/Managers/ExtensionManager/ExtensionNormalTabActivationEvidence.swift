import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionNormalTabActivationEvidence {
    struct TabEvidence {
        let tab: Tab
        let tabIdentity: ObjectIdentifier
        let adapter: ExtensionTabAdapter
        let profileID: UUID
        let window: BrowserWindowState?
        let windowIdentity: ObjectIdentifier?
    }

    let activated: TabEvidence
    let previous: TabEvidence?
    let controller: WKWebExtensionController
    let extensionLoadGeneration: UInt64
    let tabGeneration: UInt64
    let contextBindingGeneration: UInt64
    let windowPublication: (any BrowserWindowExtensionPublication)?
}

/// Builds and revalidates one exact normal-Tab activation receipt. Validation
/// is read-only: it cannot repair a stale adapter, generation, Tab residence,
/// controller binding, or window publication after a WebKit callback returns.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalTabActivationValidator {
    private let runtimeSession: ExtensionRuntimeSession
    private let profileRuntime: ExtensionProfileRuntime
    private let adapterStore: ExtensionBrowserAdapterStore
    private let adapterResolution: ExtensionAdapterResolutionOwner
    private let normalWindows: ExtensionNormalWindowLifecycle
    private let windowPublications: ExtensionWindowPublicationQuery
    private let runtime: @MainActor () -> ExtensionManagerRuntime
    private let windowQuery: @MainActor () -> (any ExtensionWindowQuery)?
    private let extensionsLoaded: @MainActor () -> Bool

    init(
        runtimeSession: ExtensionRuntimeSession,
        profileRuntime: ExtensionProfileRuntime,
        adapterStore: ExtensionBrowserAdapterStore,
        adapterResolution: ExtensionAdapterResolutionOwner,
        normalWindows: ExtensionNormalWindowLifecycle,
        windowPublications: ExtensionWindowPublicationQuery,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime,
        windowQuery: @escaping @MainActor () -> (any ExtensionWindowQuery)?,
        extensionsLoaded: @escaping @MainActor () -> Bool
    ) {
        self.runtimeSession = runtimeSession
        self.profileRuntime = profileRuntime
        self.adapterStore = adapterStore
        self.adapterResolution = adapterResolution
        self.normalWindows = normalWindows
        self.windowPublications = windowPublications
        self.runtime = runtime
        self.windowQuery = windowQuery
        self.extensionsLoaded = extensionsLoaded
    }

    func prepare(
        _ tab: Tab,
        previous: Tab?
    ) -> ExtensionNormalTabActivationEvidence? {
        guard windowPublications.isAuxiliarySessionTab(tab) == false,
              extensionsLoaded(),
              normalWindows.prepareTabActivation(tab)
        else {
            return nil
        }

        let extensionLoadGeneration = runtimeSession.extensionLoadGeneration
        let tabGeneration = runtimeSession.tabOpenNotificationGeneration
        let currentRuntime = runtime()
        guard let activated = prepareTabEvidence(
                  tab,
                  generation: tabGeneration,
                  runtime: currentRuntime
              ), let controller = profileRuntime.controller(
                  for: activated.profileID
              )
        else {
            return nil
        }

        let publication: (any BrowserWindowExtensionPublication)?
        if let window = activated.window {
            guard let exactPublication = normalWindows.publication(for: window),
                  exactPublication.isCurrent()
            else {
                return nil
            }
            publication = exactPublication
        } else {
            guard normalWindows.tabPublicationIsCurrent(
                tab,
                profileID: activated.profileID
            ) else {
                return nil
            }
            publication = nil
        }

        let previousEvidence: ExtensionNormalTabActivationEvidence.TabEvidence?
        if let candidate = previous,
           candidate !== tab,
           windowPublications.isAuxiliarySessionTab(candidate) == false,
           let evidence = prepareTabEvidence(
            candidate,
            generation: tabGeneration,
            runtime: currentRuntime
           ), evidence.profileID == activated.profileID,
           profileRuntime.controller(for: evidence.profileID) === controller {
            previousEvidence = evidence
        } else {
            previousEvidence = nil
        }

        return ExtensionNormalTabActivationEvidence(
            activated: activated,
            previous: previousEvidence,
            controller: controller,
            extensionLoadGeneration: extensionLoadGeneration,
            tabGeneration: tabGeneration,
            contextBindingGeneration: profileRuntime
                .contextBindingGeneration(for: activated.profileID),
            windowPublication: publication
        )
    }

    func isCurrent(_ evidence: ExtensionNormalTabActivationEvidence) -> Bool {
        guard extensionsLoaded(),
              runtimeSession.extensionLoadGeneration
                == evidence.extensionLoadGeneration,
              runtimeSession.tabOpenNotificationGeneration
                == evidence.tabGeneration,
              profileRuntime.contextBindingGeneration(
                  for: evidence.activated.profileID
              ) == evidence.contextBindingGeneration,
              profileRuntime.controller(for: evidence.activated.profileID)
                === evidence.controller,
              tabEvidenceIsCurrent(
                  evidence.activated,
                  generation: evidence.tabGeneration,
                  controller: evidence.controller
              ), evidence.windowPublication?.isCurrent()
                ?? normalWindows.tabPublicationIsCurrent(
                    evidence.activated.tab,
                    profileID: evidence.activated.profileID
                )
        else {
            return false
        }

        guard let previous = evidence.previous else { return true }
        return tabEvidenceIsCurrent(
            previous,
            generation: evidence.tabGeneration,
            controller: evidence.controller
        )
    }

    private func prepareTabEvidence(
        _ tab: Tab,
        generation: UInt64,
        runtime: ExtensionManagerRuntime
    ) -> ExtensionNormalTabActivationEvidence.TabEvidence? {
        guard tab.isEphemeral == false,
              tab.extensionPageRuntimeOwner.isEligible(for: generation),
              tab.extensionPageRuntimeOwner
                .hasDidOpenTabNotification(for: generation),
              let profileID = profileRuntime.resolvedProfileId(
                  for: tab,
                  runtime: runtime
              ), let adapter = adapterResolution.stableAdapter(for: tab),
              adapterStore.tabAdapters[tab.id] === adapter,
              adapter.represents(tab)
        else {
            return nil
        }

        let query = windowQuery()
        let window = query?.preferredExtensionWindowState(containing: tab)
        if let window {
            guard query?.extensionWindowState(for: window.id) === window,
                  query?.tabsForExtensionWindow(window).contains(
                      where: { $0 === tab }
                  ) == true
            else {
                return nil
            }
        }
        return ExtensionNormalTabActivationEvidence.TabEvidence(
            tab: tab,
            tabIdentity: ObjectIdentifier(tab),
            adapter: adapter,
            profileID: profileID,
            window: window,
            windowIdentity: window.map(ObjectIdentifier.init)
        )
    }

    private func tabEvidenceIsCurrent(
        _ evidence: ExtensionNormalTabActivationEvidence.TabEvidence,
        generation: UInt64,
        controller: WKWebExtensionController
    ) -> Bool {
        let tab = evidence.tab
        guard evidence.tabIdentity == ObjectIdentifier(tab),
              tab.extensionPageRuntimeOwner.isEligible(for: generation),
              tab.extensionPageRuntimeOwner
                .hasDidOpenTabNotification(for: generation),
              profileRuntime.resolvedProfileId(
                  for: tab,
                  runtime: runtime()
              ) == evidence.profileID,
              profileRuntime.controller(for: evidence.profileID) === controller,
              adapterStore.tabAdapters[tab.id] === evidence.adapter,
              evidence.adapter.represents(tab)
        else {
            return false
        }

        guard let window = evidence.window else { return true }
        let query = windowQuery()
        return evidence.windowIdentity == ObjectIdentifier(window)
            && query?.extensionWindowState(for: window.id) === window
            && query?.tabsForExtensionWindow(window).contains(
                where: { $0 === tab }
            ) == true
    }
}
