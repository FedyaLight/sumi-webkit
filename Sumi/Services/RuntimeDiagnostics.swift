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

    #if DEBUG || SUMI_DIAGNOSTICS
        static let supportsVerboseDiagnostics = true
        static let hasExplicitDebugLaunchIntent =
            ProcessInfo.processInfo.arguments.contains("--sumi-debug-runtime")
            || ProcessInfo.processInfo.environment["SUMI_DEBUG_RUNTIME"] == "1"

        static let allowsPersistedDebugDefaults =
            ProcessInfo.processInfo.arguments.contains("--sumi-allow-debug-defaults")
            || ProcessInfo.processInfo.environment[debugRuntimeDefaultsOptInKey] == "1"

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
    #else
        static let supportsVerboseDiagnostics = false
        static let hasExplicitDebugLaunchIntent = false
        static let allowsPersistedDebugDefaults = false
        static let isVerboseEnabled = false
        static let isDeveloperInspectionEnabled = false
        static let isSwipeTraceEnabled = false
    #endif

    static func debugDefaultBool(forKey key: String) -> Bool {
        #if DEBUG || SUMI_DIAGNOSTICS
            if isRunningTests {
                return UserDefaults.standard.bool(forKey: key)
            }
            guard hasExplicitDebugLaunchIntent || allowsPersistedDebugDefaults else {
                return false
            }
            return UserDefaults.standard.bool(forKey: key)
        #else
            _ = key
            return false
        #endif
    }

    static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    @inline(__always)
    private static func inferredCategory(for fileID: String) -> String {
        fileID
            .split(separator: "/")
            .last
            .map { $0.split(separator: ".").first.map(String.init) ?? "Runtime" }
            ?? "Runtime"
    }

    @inline(__always)
    private static func emitVerbose(
        category: String,
        _ message: () -> String
    ) {
        guard supportsVerboseDiagnostics else { return }
        guard isVerboseEnabled else { return }
        let renderedMessage = message()
        logger(category: category).debug("\(renderedMessage, privacy: .public)")
    }

    static func debug(
        _ message: @autoclosure () -> String,
        category: String
    ) {
        emitVerbose(category: category) { message() }
    }

    static func debug(
        category: String,
        _ message: () -> String
    ) {
        emitVerbose(category: category, message)
    }

    static func emit(
        _ message: @autoclosure () -> String,
        fileID: String = #fileID
    ) {
        guard supportsVerboseDiagnostics else { return }
        emitVerbose(category: inferredCategory(for: fileID)) { message() }
    }

    static func emit(
        _ items: Any...,
        separator: String = " ",
        fileID: String = #fileID
    ) {
        guard supportsVerboseDiagnostics else { return }
        emitVerbose(category: inferredCategory(for: fileID)) {
            items.map { String(describing: $0) }.joined(separator: separator)
        }
    }

    static func emit(
        fileID: String = #fileID,
        _ message: () -> String
    ) {
        guard supportsVerboseDiagnostics else { return }
        emitVerbose(category: inferredCategory(for: fileID), message)
    }

    static func swipeTrace(_ message: @autoclosure () -> String) {
        guard supportsVerboseDiagnostics else { return }
        guard isSwipeTraceEnabled else { return }
        let renderedMessage = message()
        logger(category: "BackForwardSwipe").debug("\(renderedMessage, privacy: .public)")
    }
}

extension Logger {
    static func sumi(category: String) -> Logger {
        RuntimeDiagnostics.logger(category: category)
    }
}
