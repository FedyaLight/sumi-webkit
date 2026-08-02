import Foundation
import SumiDomain
import WebKit

@MainActor
final class AuxiliaryMiniWindowTabLifecycleTransaction {
    private let runtimeConnection: TabRuntimePortConnection
    private let membership: TabCollectionMembershipOwner
    private let profileAdmissions: ProfileReferenceAdmissionLedger
    private let tabFactory: TabFactory

    init(
        runtimeConnection: TabRuntimePortConnection,
        membership: TabCollectionMembershipOwner,
        profileAdmissions: ProfileReferenceAdmissionLedger,
        tabFactory: TabFactory
    ) {
        self.runtimeConnection = runtimeConnection
        self.membership = membership
        self.profileAdmissions = profileAdmissions
        self.tabFactory = tabFactory
    }

    func containsExact(_ tab: Tab) -> Bool {
        membership.auxiliaryMiniWindowTab(for: tab.id) === tab
    }

    func create(
        openerTab: Tab?,
        profileID: UUID?,
        urlString: String?,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab? {
        let resolvedProfileID = profileID
            ?? openerTab?.profileId
            ?? openerTab?.resolveProfile()?.id
            ?? runtimeConnection.current?.currentProfileId
        let admissionLease: ProfileReferenceMutationLease?
        if let resolvedProfileID {
            do {
                admissionLease = try profileAdmissions.beginReferenceMutation(
                    to: [resolvedProfileID]
                )
            } catch {
                return nil
            }
        } else {
            admissionLease = nil
        }
        defer {
            if let admissionLease {
                precondition(
                    profileAdmissions.endReferenceMutation(admissionLease),
                    "Auxiliary Tab creation lost its admission lease"
                )
            }
        }
        if let admissionLease {
            guard profileAdmissions.validate(admissionLease) else { return nil }
        }

        let tab = tabFactory.makeTab(
            url: urlString.flatMap(URL.init(string:)) ?? SumiSurface.emptyTabURL,
            name: "Popup",
            favicon: "globe",
            spaceId: openerTab?.spaceId,
            index: -1
        )
        tab.isAuxiliaryMiniWindow = true
        tab.profileId = resolvedProfileID
        tab.webExtensionContextOverride = webExtensionContextOverride
        membership.attach(tab)
        membership.registerAuxiliaryMiniWindowTab(tab)

        precondition(
            containsExact(tab),
            "Auxiliary Tab creation must publish its exact residence"
        )
        if let admissionLease {
            precondition(
                profileAdmissions.validate(admissionLease),
                "Auxiliary Tab creation crossed a retired profile boundary"
            )
        }
        return tab
    }

    func remove(_ tab: Tab) {
        guard containsExact(tab) else { return }
        let runtimePorts = runtimeConnection.requireLease()
        membership.removeAuxiliaryMiniWindowTab(tab)
        runtimePorts.webViewLifecycle.unloadTab(tab)
        runtimePorts.webViewLifecycle.requireRemoveAllWebViews(for: tab)
        membership.detach(tab)
        NotificationCenter.default.post(
            name: .sumiTabLifecycleDidChange,
            object: tab
        )
    }

    @discardableResult
    func closeIfPresent(id: UUID) -> Bool {
        guard let tab = membership.auxiliaryMiniWindowTab(for: id) else {
            return false
        }
        runtimeConnection.requireLease().closeAuxiliaryMiniWindow(
            for: tab,
            reason: .extensionRequestedClose
        )
        return true
    }
}
