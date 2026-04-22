//
//  ExtensionManagerSupport.swift
//  Sumi
//
//  Small support types used by ExtensionManager orchestration.
//

import AppKit
import Foundation

@available(macOS 15.5, *)
final class WeakAnchor {
    weak var view: NSView?
    weak var window: NSWindow?

    init(view: NSView?, window: NSWindow?) {
        self.view = view
        self.window = window
    }
}

@available(macOS 15.5, *)
struct BoundedRecentDateTracker {
    let ttl: TimeInterval
    let maxKeys: Int
    let maxDatesPerKey: Int

    private var datesByKey: [String: [Date]] = [:]
    private var keyOrder: [String] = []

    init(ttl: TimeInterval, maxKeys: Int, maxDatesPerKey: Int) {
        self.ttl = ttl
        self.maxKeys = maxKeys
        self.maxDatesPerKey = maxDatesPerKey
    }

    var keyCount: Int {
        datesByKey.count
    }

    var dateCount: Int {
        datesByKey.values.reduce(0) { $0 + $1.count }
    }

    mutating func record(key: String, at now: Date = Date()) {
        prune(now: now)

        var dates = datesByKey[key] ?? []
        dates.append(now)
        if dates.count > maxDatesPerKey {
            dates.removeFirst(dates.count - maxDatesPerKey)
        }

        datesByKey[key] = dates
        touch(key)
        evictIfNeeded()
    }

    mutating func consume(key: String, at now: Date = Date()) -> Bool {
        prune(now: now)

        guard var dates = datesByKey[key], dates.isEmpty == false else {
            return false
        }

        dates.removeLast()
        if dates.isEmpty {
            datesByKey.removeValue(forKey: key)
            keyOrder.removeAll { $0 == key }
        } else {
            datesByKey[key] = dates
            touch(key)
        }

        return true
    }

    mutating func removeAll() {
        datesByKey.removeAll()
        keyOrder.removeAll()
    }

    private mutating func prune(now: Date) {
        for key in Array(datesByKey.keys) {
            let dates = (datesByKey[key] ?? []).filter {
                now.timeIntervalSince($0) <= ttl
            }

            if dates.isEmpty {
                datesByKey.removeValue(forKey: key)
                keyOrder.removeAll { $0 == key }
            } else {
                datesByKey[key] = dates
            }
        }
    }

    private mutating func touch(_ key: String) {
        keyOrder.removeAll { $0 == key }
        keyOrder.append(key)
    }

    private mutating func evictIfNeeded() {
        while datesByKey.count > maxKeys, let key = keyOrder.first {
            keyOrder.removeFirst()
            datesByKey.removeValue(forKey: key)
        }
    }
}
