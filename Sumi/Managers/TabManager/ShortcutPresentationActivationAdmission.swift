import Foundation

@MainActor
struct ShortcutPresentationActivationAdmission {
    let request: ShortcutPresentationActivationService.Request
    let pin: ShortcutPin
    let pinTitle: String
    let targetSpaceID: UUID?
    let page: LiveShortcutPresentationPageReceipt
    let tab: Tab
    let existing: LiveShortcutTabEntry?
}

/// Pure admission/revalidation half of shortcut presentation activation.
/// Fresh tabs are detached candidates; no registry, lookup, or window state is
/// changed until the aggregate receipt is staged.
@MainActor
final class ShortcutPresentationActivationPlanner {
    private let pins: ShortcutPinCollectionStateOwner
    private let registry: LiveShortcutTabRegistry
    private let resolution: ShortcutPinRuntimeResolutionOwner
    private let freshTabs: ShortcutFreshTabFactory
    private let membership: TabCollectionMembershipOwner

    init(
        pins: ShortcutPinCollectionStateOwner,
        registry: LiveShortcutTabRegistry,
        resolution: ShortcutPinRuntimeResolutionOwner,
        freshTabs: ShortcutFreshTabFactory,
        membership: TabCollectionMembershipOwner
    ) {
        self.pins = pins
        self.registry = registry
        self.resolution = resolution
        self.freshTabs = freshTabs
        self.membership = membership
    }

    func prepare(
        _ requests: [ShortcutPresentationActivationService.Request]
    ) -> [ShortcutPresentationActivationAdmission]? {
        prepare(requests) { request in
            self.pins.shortcutPin(by: request.pinID)
        }
    }

    func prepare(
        _ remainder: DisplayedShortcutActivationRemainder,
        preview: ShortcutPresentationCatalogInsertionPreview
    ) -> [ShortcutPresentationActivationAdmission]? {
        prepare(remainder.requests) { request in
            preview.resolvePin(withID: request.pinID) {
                self.pins.shortcutPin(by: request.pinID)
            }
        }
    }

    private func prepare(
        _ requests: [ShortcutPresentationActivationService.Request],
        resolvingPin: (ShortcutPresentationActivationService.Request)
            -> ShortcutPin?
    ) -> [ShortcutPresentationActivationAdmission]? {
        let slots = Set(requests.map { request in
            "\(request.windowID.uuidString):\(request.pinID.uuidString)"
        })
        guard slots.count == requests.count else { return nil }
        let admissions = requests.compactMap {
            prepare($0, pin: resolvingPin($0))
        }
        return admissions.count == requests.count ? admissions : nil
    }

    func acceptsStaged(
        _ admissions: [ShortcutPresentationActivationAdmission],
        authority: ShortcutPresentationPinIdentityAuthority
    ) -> Bool {
        admissions.allSatisfy { expected in
            guard acceptsStableIntent(
                expected,
                authority: authority
            ),
                  let current = registry.entry(containing: expected.tab),
                  current.windowId == expected.request.windowID,
                  current.pinId == expected.pin.id,
                  current.tab === expected.tab,
                  current.presentationPage == expected.page else {
                return false
            }
            return membership.tab(for: expected.tab.id) === expected.tab
        }
    }

    func canStage(
        _ admissions: [ShortcutPresentationActivationAdmission],
        authority: ShortcutPresentationPinIdentityAuthority
    ) -> Bool {
        acceptsCurrent(admissions, authority: authority)
            && acceptsResidenceForStaging(admissions)
    }

    private func prepare(
        _ request: ShortcutPresentationActivationService.Request,
        pin: ShortcutPin?
    ) -> ShortcutPresentationActivationAdmission? {
        guard let pin, pin.id == request.pinID else { return nil }
        let targetSpaceID = pin.spaceId ?? request.presentationSpaceID
        guard let page = resolution.presentationPageReceipt(
            for: pin,
            windowID: request.windowID,
            presentationSpaceID: targetSpaceID
        ) else { return nil }
        let existing = registry.tab(for: pin.id, in: request.windowID)
            .flatMap(registry.entry(containing:))
        guard existing.map({ entry in
            entry.windowId == request.windowID
                && entry.pinId == pin.id
                && acceptsBinding(
                    entry.tab,
                    pin: pin,
                    presentationSpaceID: targetSpaceID
                )
                && membership.tab(for: entry.tab.id) === entry.tab
        }) != false else { return nil }
        let tab = existing?.tab ?? freshTabs.makeDetached(
            for: pin,
            currentSpaceID: targetSpaceID
        )
        return ShortcutPresentationActivationAdmission(
            request: request,
            pin: pin,
            pinTitle: pin.title,
            targetSpaceID: targetSpaceID,
            page: page,
            tab: tab,
            existing: existing
        )
    }

    private func acceptsCurrent(
        _ admissions: [ShortcutPresentationActivationAdmission],
        authority: ShortcutPresentationPinIdentityAuthority
    ) -> Bool {
        admissions.allSatisfy { expected in
            acceptsCurrentResidence(expected)
                && acceptsStableIntent(expected, authority: authority)
        }
    }

    private func acceptsCurrentResidence(
        _ expected: ShortcutPresentationActivationAdmission
    ) -> Bool {
        let current = registry.tab(
            for: expected.pin.id,
            in: expected.request.windowID
        ).flatMap(registry.entry(containing:))
        switch (expected.existing, current) {
        case (.none, .none):
            return membership.tab(for: expected.tab.id) == nil
        case (.some(let lhs), .some(let rhs)):
            return lhs.tab === rhs.tab
                && lhs.windowId == rhs.windowId
                && lhs.pinId == rhs.pinId
                && lhs.presentationPage == rhs.presentationPage
                && membership.tab(for: rhs.tab.id) === rhs.tab
        default:
            return false
        }
    }

    private func acceptsResidenceForStaging(
        _ admissions: [ShortcutPresentationActivationAdmission]
    ) -> Bool {
        admissions.allSatisfy { admission in
            if admission.existing != nil {
                guard let entry = registry.entry(containing: admission.tab)
                else { return false }
                return entry.presentationPage == admission.page
                    || registry.staging.canRelocate(
                        admission.tab,
                        from: admission.pin.id,
                        to: admission.pin.id,
                        in: admission.request.windowID,
                        presentationPage: admission.page
                    )
            }
            return admission.page.page.windowID == admission.request.windowID
                && registry.entry(containing: admission.tab) == nil
                && registry.tab(
                    for: admission.pin.id,
                    in: admission.request.windowID
                ) == nil
                && membership.tab(for: admission.tab.id) == nil
        }
    }

    private func acceptsStableIntent(
        _ expected: ShortcutPresentationActivationAdmission,
        authority: ShortcutPresentationPinIdentityAuthority
    ) -> Bool {
        guard let currentPin = pins.shortcutPin(by: expected.pin.id),
              authority.accepts(
                  current: currentPin,
                  expected: expected.pin
              ) else { return false }
        return currentPin.title == expected.pinTitle
            && resolution.presentationPageReceipt(
                for: currentPin,
                windowID: expected.request.windowID,
                presentationSpaceID: expected.targetSpaceID
            ) == expected.page
            && acceptsBinding(
                expected.tab,
                pin: currentPin,
                presentationSpaceID: expected.targetSpaceID
            )
    }

    private func acceptsBinding(
        _ tab: Tab,
        pin: ShortcutPin,
        presentationSpaceID: UUID?
    ) -> Bool {
        tab.shortcutPinId == pin.id
            && tab.shortcutPinRole == pin.role
            && tab.isShortcutLiveInstance
            && tab.isPinned == false
            && tab.isSpacePinned == false
            && tab.spaceId == resolution.resolvedLiveSpaceId(
                for: pin,
                currentSpaceId: presentationSpaceID
            )
            && tab.profileId == resolution.desiredLiveTabProfileId(for: pin)
            && tab.folderId == (pin.role == .essential ? nil : pin.folderId)
    }
}
