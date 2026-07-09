//
//  Persisted.swift
//  Sumi
//
//  Shared UserDefaults write helpers for settings domain stores.
//  Prefer these over copy-pasted `didSet { userDefaults.set(...) }` bodies.
//

import Foundation

@MainActor
enum Persisted {
    static func bool(_ value: Bool, key: String, defaults: UserDefaults) {
        defaults.set(value, forKey: key)
    }

    static func double(_ value: Double, key: String, defaults: UserDefaults) {
        defaults.set(value, forKey: key)
    }

    static func int(_ value: Int, key: String, defaults: UserDefaults) {
        defaults.set(value, forKey: key)
    }

    static func string(_ value: String, key: String, defaults: UserDefaults) {
        defaults.set(value, forKey: key)
    }

    static func stringArray(_ value: [String], key: String, defaults: UserDefaults) {
        defaults.set(value, forKey: key)
    }

    static func data(_ value: Data, key: String, defaults: UserDefaults) {
        defaults.set(value, forKey: key)
    }

    static func rawRepresentable<Value: RawRepresentable>(
        _ value: Value,
        key: String,
        defaults: UserDefaults
    ) where Value.RawValue == String {
        defaults.set(value.rawValue, forKey: key)
    }

    static func rawRepresentable<Value: RawRepresentable>(
        _ value: Value,
        key: String,
        defaults: UserDefaults
    ) where Value.RawValue == Int {
        defaults.set(value.rawValue, forKey: key)
    }
}
