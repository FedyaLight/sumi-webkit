//
//  NSObjectExtension.swift
//

import Foundation

extension NSObject {

    public final class DeinitObserver: NSObject {
        fileprivate var callback: (() -> Void)?

        public init(_ callback: (() -> Void)? = nil) {
            self.callback = callback
        }

        @MainActor
        public func disarm() {
            dispatchPrecondition(condition: .onQueue(.main))
            callback = nil
        }

        deinit {
            callback?()
        }
    }

    @discardableResult
    public func onDeinit(_ onDeinit: @escaping () -> Void) -> DeinitObserver {
        dispatchPrecondition(condition: .onQueue(.main))
        if let deinitObserver = self as? DeinitObserver {
            assert(deinitObserver.callback == nil, "disarm DeinitObserver first before re-setting its callback")
            deinitObserver.callback = onDeinit
            return deinitObserver
        }
        return deinitObservers.insert(DeinitObserver(onDeinit)).memberAfterInsert
    }

    private static let deinitObserversKey = UnsafeRawPointer(bitPattern: "deinitObserversKey".hashValue)!
    public var deinitObservers: Set<DeinitObserver> {
        get {
            dispatchPrecondition(condition: .onQueue(.main))
            return objc_getAssociatedObject(self, Self.deinitObserversKey) as? Set<DeinitObserver> ?? []
        }
        set {
            dispatchPrecondition(condition: .onQueue(.main))
            objc_setAssociatedObject(self, Self.deinitObserversKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}
