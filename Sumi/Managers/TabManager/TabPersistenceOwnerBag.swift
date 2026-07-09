//
//  TabPersistenceOwnerBag.swift
//  Sumi
//
//  Capability bag: structural persistence, store restore, and session restore.
//

import Foundation

/// Groups persistence-adjacent TabManager owners so they are not peer `lazy var`
/// Owners on the TabManager façade.
@MainActor
final class TabPersistenceOwnerBag {
    private weak var tabManager: TabManager?

    func bind(_ tabManager: TabManager) {
        self.tabManager = tabManager
    }

    private var tm: TabManager {
        guard let tabManager else {
            preconditionFailure("TabPersistenceOwnerBag used before bind(tabManager:)")
        }
        return tabManager
    }

    lazy var runtimeStore = DefaultTabRuntimeStore(tabManager: tm)
    lazy var lastSessionRestoreOwner = TabLastSessionRestoreOwner(dependencies: .live(tabManager: tm))
    lazy var structuralPersistence = TabStructuralPersistenceOwner(
        persistence: tm.persistence,
        runtimeStateCoalescer: tm.runtimeStateCoalescer,
        dependencies: .live(tabManager: tm)
    )
    lazy var storeRestore = TabStoreRestoreOwner(dependencies: .live(tabManager: tm))
}
