//
//  TabStructureEventBus.swift
//  SumiBrowserCore
//
//  Foundation + Combine tab-structure event bus. No AppKit / SwiftUI / WebKit.
//

import Combine
import Foundation

/// Typed structural / lifecycle events for tab organization.
/// Replaces ad-hoc fan-out across PassthroughSubject + NotificationCenter + revision counters.
@MainActor
public enum TabStructureEvent: Equatable, Sendable {
    case structureChanged
    case initialDataLoaded
}

@MainActor
public final class TabStructureEventBus {
    private let subject = PassthroughSubject<TabStructureEvent, Never>()

    public init() {}

    public var publisher: AnyPublisher<TabStructureEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    public var structureChangedPublisher: AnyPublisher<Void, Never> {
        subject
            .compactMap { event -> Void? in
                if case .structureChanged = event { return () }
                return nil
            }
            .eraseToAnyPublisher()
    }

    public var initialDataLoadedPublisher: AnyPublisher<Void, Never> {
        subject
            .compactMap { event -> Void? in
                if case .initialDataLoaded = event { return () }
                return nil
            }
            .eraseToAnyPublisher()
    }

    public func publish(_ event: TabStructureEvent) {
        subject.send(event)
    }

    public func publishStructureChanged() {
        publish(.structureChanged)
    }

    public func publishInitialDataLoaded() {
        publish(.initialDataLoaded)
    }
}
