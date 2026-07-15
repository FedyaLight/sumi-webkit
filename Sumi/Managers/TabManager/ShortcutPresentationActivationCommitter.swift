import Foundation

/// Exact staged residence and membership mutation for one activation batch.
@MainActor
final class ShortcutPresentationActivationStagedMutation {
    private let registry: LiveShortcutTabRegistry
    private let membership: TabCollectionMembershipOwner
    private let changes: [LiveShortcutResidenceMutationStaging.Change]
    private let attachedTabs: [Tab]

    init(
        registry: LiveShortcutTabRegistry,
        membership: TabCollectionMembershipOwner,
        changes: [LiveShortcutResidenceMutationStaging.Change],
        attachedTabs: [Tab]
    ) {
        self.registry = registry
        self.membership = membership
        self.changes = changes
        self.attachedTabs = attachedTabs
    }

    func canPublish() -> Bool {
        registry.staging.canPublish(changes)
    }

    func publish() {
        registry.staging.publish(changes)
    }

    func rollback() {
        precondition(
            registry.staging.rollback(changes),
            "Shortcut activation residence rollback diverged"
        )
        for tab in attachedTabs.reversed()
            where registry.entry(containing: tab) == nil
                && membership.tab(for: tab.id) === tab {
            membership.detach(tab)
        }
    }
}

/// Stages the mutation half of an already admitted activation batch.
@MainActor
final class ShortcutPresentationActivationCommitter {
    private let registry: LiveShortcutTabRegistry
    private let membership: TabCollectionMembershipOwner

    init(
        registry: LiveShortcutTabRegistry,
        membership: TabCollectionMembershipOwner
    ) {
        self.registry = registry
        self.membership = membership
    }

    func stage(
        _ admissions: [ShortcutPresentationActivationAdmission]
    ) -> ShortcutPresentationActivationStagedMutation? {
        var changes: [LiveShortcutResidenceMutationStaging.Change] = []
        var attachedTabs: [Tab] = []

        for admission in admissions {
            if let existing = admission.existing {
                guard existing.presentationPage != admission.page else {
                    continue
                }
                guard let change = registry.staging.relocate(
                    admission.tab,
                    from: admission.pin.id,
                    to: admission.pin.id,
                    in: admission.request.windowID,
                    presentationPage: admission.page
                ) else {
                    rollback(changes: changes, attachedTabs: attachedTabs)
                    return nil
                }
                changes.append(change)
                continue
            }

            membership.attach(admission.tab)
            attachedTabs.append(admission.tab)
            guard let change = registry.staging.register(
                admission.tab,
                for: admission.pin.id,
                in: admission.request.windowID,
                presentationPage: admission.page
            ) else {
                rollback(changes: changes, attachedTabs: attachedTabs)
                return nil
            }
            changes.append(change)
        }

        return ShortcutPresentationActivationStagedMutation(
            registry: registry,
            membership: membership,
            changes: changes,
            attachedTabs: attachedTabs
        )
    }

    private func rollback(
        changes: [LiveShortcutResidenceMutationStaging.Change],
        attachedTabs: [Tab]
    ) {
        precondition(registry.staging.rollback(changes))
        for tab in attachedTabs.reversed()
            where registry.entry(containing: tab) == nil
                && membership.tab(for: tab.id) === tab {
            membership.detach(tab)
        }
    }
}
