//
//  TabStructureStore.swift
//  SumiBrowserCore
//
//  Structural publish / transaction surface for tab organization.
//  TabManager conforms in the app target; consumers can depend on this
//  protocol instead of the concrete manager.
//

import Foundation

/// Read/publish surface for tab structural organization (Foundation-safe).
@MainActor
public protocol TabStructureStore: AnyObject {
    var tabStructureEventBus: TabStructureEventBus { get }

    func requestStructuralPublish()

    @discardableResult
    func withStructuralUpdateTransaction<T>(_ operation: () throws -> T) rethrows -> T
}
