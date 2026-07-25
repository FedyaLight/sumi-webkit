//
//  TabStructureEventBus.swift
//  Sumi
//
//  Browser-runtime tab-structure event bus.
//

import Combine
import Foundation

/// Typed structural / lifecycle events for tab organization.
/// Replaces ad-hoc fan-out across PassthroughSubject + NotificationCenter + revision counters.
struct TabStructurePageScope: Equatable, Hashable, Sendable {
    let windowID: UUID
    let spaceID: UUID
    let profileID: UUID?
}

struct TabStructureChangeScope: Equatable, Sendable {
    let affectedSpaceIDs: Set<UUID>
    let affectedProfileIDs: Set<UUID>
    let affectedPages: Set<TabStructurePageScope>
    let affectsSpaceCatalog: Bool
    let affectsAllPages: Bool

    init(
        affectedSpaceIDs: Set<UUID>,
        affectedProfileIDs: Set<UUID>,
        affectedPages: Set<TabStructurePageScope> = [],
        affectsSpaceCatalog: Bool,
        affectsAllPages: Bool
    ) {
        self.affectedSpaceIDs = affectedSpaceIDs
        self.affectedProfileIDs = affectedProfileIDs
        self.affectedPages = affectedPages
        self.affectsSpaceCatalog = affectsSpaceCatalog
        self.affectsAllPages = affectsAllPages
    }

    static let all = Self(
        affectedSpaceIDs: [],
        affectedProfileIDs: [],
        affectedPages: [],
        affectsSpaceCatalog: true,
        affectsAllPages: true
    )

    /// Structural runtime bookkeeping that does not change a persisted sidebar
    /// page snapshot (for example a transient live-shortcut lease).
    static let runtimeOnly = Self(
        affectedSpaceIDs: [],
        affectedProfileIDs: [],
        affectedPages: [],
        affectsSpaceCatalog: false,
        affectsAllPages: false
    )

    static func space(_ spaceID: UUID, catalog: Bool = false) -> Self {
        Self(
            affectedSpaceIDs: [spaceID],
            affectedProfileIDs: [],
            affectedPages: [],
            affectsSpaceCatalog: catalog,
            affectsAllPages: false
        )
    }

    static func spaces(_ spaceIDs: Set<UUID>, catalog: Bool = false) -> Self {
        Self(
            affectedSpaceIDs: spaceIDs,
            affectedProfileIDs: [],
            affectedPages: [],
            affectsSpaceCatalog: catalog,
            affectsAllPages: false
        )
    }

    static func profile(_ profileID: UUID) -> Self {
        Self(
            affectedSpaceIDs: [],
            affectedProfileIDs: [profileID],
            affectedPages: [],
            affectsSpaceCatalog: false,
            affectsAllPages: false
        )
    }

    static func page(_ page: TabStructurePageScope) -> Self {
        Self(
            affectedSpaceIDs: [],
            affectedProfileIDs: [],
            affectedPages: [page],
            affectsSpaceCatalog: false,
            affectsAllPages: false
        )
    }

    func affectsPage(
        windowID: UUID,
        spaceID: UUID,
        profileID: UUID?
    ) -> Bool {
        affectsAllPages
            || affectedPages.contains(
                TabStructurePageScope(
                    windowID: windowID,
                    spaceID: spaceID,
                    profileID: profileID
                )
            )
            || affectedSpaceIDs.contains(spaceID)
            || profileID.map(affectedProfileIDs.contains) == true
    }

    func merging(_ other: Self) -> Self {
        Self(
            affectedSpaceIDs: affectedSpaceIDs.union(other.affectedSpaceIDs),
            affectedProfileIDs: affectedProfileIDs.union(other.affectedProfileIDs),
            affectedPages: affectedPages.union(other.affectedPages),
            affectsSpaceCatalog: affectsSpaceCatalog || other.affectsSpaceCatalog,
            affectsAllPages: affectsAllPages || other.affectsAllPages
        )
    }
}

struct TabFolderExpansionChange: Equatable, Sendable {
    let revision: UInt64
    let spaceID: UUID
    let expansionByFolderID: [UUID: Bool]
}

@MainActor
enum TabStructureEvent: Equatable, Sendable {
    case structureChanged(TabStructureChangeScope)
    case folderExpansionChanged(TabFolderExpansionChange)
    case initialDataLoaded
}

@MainActor
final class TabStructureEventBus {
    private let subject = PassthroughSubject<TabStructureEvent, Never>()
    private let initialDataLoadedState = CurrentValueSubject<Bool, Never>(false)

    init() {}

    var publisher: AnyPublisher<TabStructureEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    var structureChangedPublisher: AnyPublisher<Void, Never> {
        subject
            .compactMap { event -> Void? in
                if case .structureChanged = event { return () }
                return nil
            }
            .eraseToAnyPublisher()
    }

    var scopedStructureChangesPublisher: AnyPublisher<TabStructureChangeScope, Never> {
        subject
            .compactMap { event -> TabStructureChangeScope? in
                guard case .structureChanged(let scope) = event else { return nil }
                return scope
            }
            .eraseToAnyPublisher()
    }

    var folderExpansionChangesPublisher: AnyPublisher<TabFolderExpansionChange, Never> {
        subject
            .compactMap { event -> TabFolderExpansionChange? in
                guard case .folderExpansionChanged(let change) = event else { return nil }
                return change
            }
            .eraseToAnyPublisher()
    }

    var initialDataLoadedPublisher: AnyPublisher<Void, Never> {
        initialDataLoadedState
            .filter { $0 }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func publish(_ event: TabStructureEvent) {
        if case .initialDataLoaded = event {
            initialDataLoadedState.send(true)
        }
        subject.send(event)
    }

    func publishStructureChanged(scope: TabStructureChangeScope = .all) {
        publish(.structureChanged(scope))
    }

    func publishFolderExpansionChanged(_ change: TabFolderExpansionChange) {
        publish(.folderExpansionChanged(change))
    }

    func publishInitialDataLoaded() {
        publish(.initialDataLoaded)
    }

    func resetInitialDataLoaded() {
        initialDataLoadedState.send(false)
    }
}
