//
//  RuntimeDiagnostics.swift
//  Sumi
//

import Foundation
import OSLog

enum SumiAppIdentity {
    static let bundleIdentifier = "com.sumi.browser"

    static var runtimeBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? bundleIdentifier
    }
}

enum RuntimeDiagnostics {
    static let subsystem = SumiAppIdentity.runtimeBundleIdentifier
    private static let debugRuntimeDefaultsOptInKey = "SUMI_ALLOW_DEBUG_DEFAULTS"
    static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    static let hasExplicitDebugLaunchIntent =
        ProcessInfo.processInfo.arguments.contains("--sumi-debug-runtime")
        || ProcessInfo.processInfo.environment["SUMI_DEBUG_RUNTIME"] == "1"

    #if DEBUG
    static let allowsPersistedDebugDefaults =
        ProcessInfo.processInfo.arguments.contains("--sumi-allow-debug-defaults")
        || ProcessInfo.processInfo.environment[debugRuntimeDefaultsOptInKey] == "1"
    #else
    static let allowsPersistedDebugDefaults = false
    #endif

    static let isVerboseEnabled =
        hasExplicitDebugLaunchIntent
        || (
            allowsPersistedDebugDefaults
            && UserDefaults.standard.bool(forKey: "debug.runtime.logging.enabled")
        )

    static let isDeveloperInspectionEnabled = isVerboseEnabled

    static let isSwipeTraceEnabled =
        ProcessInfo.processInfo.arguments.contains("--sumi-debug-swipe")
        || ProcessInfo.processInfo.environment["SUMI_DEBUG_SWIPE"] == "1"

    static func debugDefaultBool(forKey key: String) -> Bool {
        if isRunningTests {
            return UserDefaults.standard.bool(forKey: key)
        }
        guard hasExplicitDebugLaunchIntent || allowsPersistedDebugDefaults else {
            return false
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    static func debug(_ message: String, category: String) {
        guard isVerboseEnabled else { return }
        logger(category: category).debug("\(message, privacy: .public)")
    }

    static func emit(
        _ items: Any...,
        separator: String = " ",
        fileID: String = #fileID
    ) {
        guard isVerboseEnabled else { return }
        let category = fileID
            .split(separator: "/")
            .last
            .map { $0.split(separator: ".").first.map(String.init) ?? "Runtime" }
            ?? "Runtime"
        let message = items.map { String(describing: $0) }.joined(separator: separator)
        logger(category: category).debug("\(message, privacy: .public)")
    }

    static func swipeTrace(_ message: String) {
        guard isSwipeTraceEnabled else { return }
        logger(category: "BackForwardSwipe").debug("\(message, privacy: .public)")
    }
}

extension Logger {
    static func sumi(category: String) -> Logger {
        RuntimeDiagnostics.logger(category: category)
    }
}
