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
@MainActor
enum TabStructureEvent: Equatable, Sendable {
    case structureChanged
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

    func publishStructureChanged() {
        publish(.structureChanged)
    }

    func publishInitialDataLoaded() {
        publish(.initialDataLoaded)
    }

    func resetInitialDataLoaded() {
        initialDataLoadedState.send(false)
    }
}
