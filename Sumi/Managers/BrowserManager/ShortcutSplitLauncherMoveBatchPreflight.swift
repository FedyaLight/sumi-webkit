import Foundation

@MainActor
extension ShortcutSplitLauncherMoveBatchStaging {
    func preflightBindingContribution(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> ShortcutSplitLauncherBindingPreflight? {
        preflightBindingContribution(
            restorations,
            bindingMode: .preservingLiveBindings
        )
    }

    func preflightBindingContribution(
        _ restorations: [PreparedShortcutSplitLauncherRestoration],
        bindingMode: ShortcutSplitLauncherComposedBindingMode
    ) -> ShortcutSplitLauncherBindingPreflight? {
        guard Set(restorations.map { $0.pin.id }).count == restorations.count,
              restorations.allSatisfy({ catalog.isCurrent($0.pin) }) else {
            return nil
        }
        let bindingBatch = bindingStaging.beginBatch()
        let exclusion: ShortcutLiveRetirementBindingExclusion?
        switch bindingMode {
        case .preservingLiveBindings: exclusion = nil
        case .consumingExactRetirement(let value): exclusion = value
        }
        var didConsumeExclusion = exclusion == nil
        let entries = restorations.compactMap { restoration in
            guard let preview = catalog.preview(
                restoration.pin,
                destination: restoration.destination
            ) else {
                return nil as ShortcutSplitLauncherBindingPreflight.Entry?
            }
            guard let admitted = bindingBatch.admission(for: preview) else {
                return nil as ShortcutSplitLauncherBindingPreflight.Entry?
            }
            let admission: LiveShortcutPresentationRefreshAdmission
            if let exclusion, exclusion.belongs(to: preview) {
                guard didConsumeExclusion == false,
                      let filtered = admitted.consuming(
                          exclusion,
                          for: preview
                      ) else {
                    return nil as ShortcutSplitLauncherBindingPreflight.Entry?
                }
                admission = filtered
                didConsumeExclusion = true
            } else {
                admission = admitted
            }
            guard let binding = bindingBatch.prepare(
                   pin: preview,
                   admission: admission
               ) else {
                return nil as ShortcutSplitLauncherBindingPreflight.Entry?
            }
            return ShortcutSplitLauncherBindingPreflight.Entry(
                restoration: restoration,
                binding: binding
            )
        }
        guard entries.count == restorations.count,
              didConsumeExclusion else { return nil }
        return ShortcutSplitLauncherBindingPreflight(
            catalog: catalog,
            bindingBatch: bindingBatch,
            entries: entries
        )
    }

    func prepareBindingContribution(
        _ preflight: ShortcutSplitLauncherBindingPreflight,
        after insertion: ShortcutSplitLauncherCatalogInsertionPlan
    ) -> ShortcutSplitLauncherBindingContribution? {
        let restorations = preflight.entries.map(\.restoration)
        guard preflight.catalog === catalog,
              restorations.allSatisfy({
                  insertion.sourceCatalog.contains($0.pinReceipt)
              }), catalog.matches(insertion.sourceCatalog) else { return nil }
        return prepareContribution(
            preflight,
            terminalRestorations: restorations,
            insertion: insertion
        )
    }
}
