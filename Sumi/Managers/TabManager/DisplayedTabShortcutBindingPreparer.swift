import Foundation

@MainActor
final class DisplayedTabShortcutBindingPreparer {
    private let registry: LiveShortcutTabRegistry
    private let membership: TabCollectionMembershipOwner
    private let resolution: ShortcutPinRuntimeResolutionOwner
    private let freshTabs: ShortcutFreshTabFactory

    init(
        registry: LiveShortcutTabRegistry,
        membership: TabCollectionMembershipOwner,
        resolution: ShortcutPinRuntimeResolutionOwner,
        freshTabs: ShortcutFreshTabFactory
    ) {
        self.registry = registry
        self.membership = membership
        self.resolution = resolution
        self.freshTabs = freshTabs
    }

    func preflight(
        pin: ShortcutPin,
        authorization: AuthorizedDisplayedTabShortcutConversion,
        builder: ShortcutTabBindingBatchBuilder
    ) -> DisplayedTabShortcutBindingPreflight? {
        guard let presentations = DisplayedShortcutPresentationResidencePlan(
            pin: pin,
            authorization: authorization,
            registry: registry,
            resolution: resolution
        ) else { return nil }
        return preflight(
            pin: pin,
            authorization: authorization,
            presentations: presentations,
            builder: builder
        )
    }

    func preflight(
        pin: ShortcutPin,
        authorization: AuthorizedDisplayedTabShortcutConversion,
        presentations: DisplayedShortcutPresentationResidencePlan,
        builder: ShortcutTabBindingBatchBuilder
    ) -> DisplayedTabShortcutBindingPreflight? {
        guard builder.isCurrent(),
              presentations.acceptsCurrentResidences(
                  for: pin,
                  registry: registry,
                  resolution: resolution
              ) else { return nil }
        let source = presentations.source
        guard builder.windowState(for: source.window.id) === source.window else {
            return nil
        }
        let sourceTarget = target(
            pin,
            currentSpaceID: source.spaceID,
            builder: builder
        )
        guard let sourceTarget,
              let profile = builder.prepareProfileAdmission(
            tab: authorization.tab,
            target: sourceTarget
        ) else { return nil }

        var planned = [(authorization.tab, source, sourceTarget)]
        var tabsByWindowID = [source.window.id: authorization.tab]
        var detached: [(Tab, BrowserWindowState)] = []
        for presentation in presentations.replicas {
            guard builder.windowState(for: presentation.window.id)
                    === presentation.window else { return nil }
            let tab = freshTabs.makeDetached(
                for: pin,
                currentSpaceID: presentation.spaceID
            )
            guard let target = target(
                pin,
                currentSpaceID: presentation.spaceID,
                builder: builder
            ) else { return nil }
            planned.append((
                tab,
                presentation,
                target
            ))
            tabsByWindowID[presentation.window.id] = tab
            detached.append((tab, presentation.window))
        }
        return DisplayedTabShortcutBindingPreflight(
            candidate: pin,
            registry: registry,
            membership: membership,
            profile: profile,
            planned: planned,
            sourceTab: authorization.tab,
            sourceSpaceID: authorization.tab.spaceId,
            liveTabsByWindowID: tabsByWindowID,
            freshTabs: detached
        )
    }

    private func target(
        _ pin: ShortcutPin,
        currentSpaceID: UUID?,
        builder: ShortcutTabBindingBatchBuilder
    ) -> ShortcutSplitLauncherBindingTarget? {
        guard let profileTarget = builder.resolvedProfileTarget(
            resolution.resolvedExecutionProfileId(
                for: pin,
                currentSpaceId: currentSpaceID
            )
        ) else { return nil }
        return ShortcutSplitLauncherBindingTarget(
            spaceID: resolution.resolvedLiveSpaceId(
                for: pin,
                currentSpaceId: currentSpaceID
            ),
            desiredProfileID: resolution.desiredLiveTabProfileId(for: pin),
            resolvedProfileID: profileTarget.profileID,
            runtimeFallback: profileTarget.runtimeFallback,
            folderID: pin.role == .essential ? nil : pin.folderId
        )
    }
}
