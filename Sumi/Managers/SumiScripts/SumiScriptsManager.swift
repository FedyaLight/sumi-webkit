//
//  SumiScriptsManager.swift
//  Sumi
//
//  Main coordinator for the native Userscript Manager system.
//
//  This manager is owned by SumiUserscriptsModule and is constructed only
//  on the enabled userscripts path. When deactivated, all watchers,
//  handlers, and injection hooks are torn down.
//
//  Lifecycle:
//  - On module activation, loads scripts from disk
//  - On navigation policy: prepares Sumi user-script adapters for the URL
//  - On disable: releases all native GM bridge state
//
//  INTEGRATION NOTES:
//  Runtime access goes through SumiUserscriptsModule. To integrate with Tab
//  lifecycle, see INTEGRATION.md.
//
//  Dependency sketch:
//  Tab (WebView/Navigation) → SumiScriptsManager
//    → UserScriptStore (disk manifest + SwiftData mirror in UserScriptStore+SwiftData)
//    -> UserScriptInjector -> Sumi user-script adapters -> per-script UserScriptGMBridge glue
//    Remote installs: SumiScriptsRemoteInstall (URL sniffing, preview, NSAlert)
//

import AppKit
import Foundation
import WebKit
import Combine
import SwiftData

@MainActor
final class SumiScriptsManager: ObservableObject {

    // MARK: - Published State

    /// Total number of loaded (not necessarily injected) scripts.
    @Published private(set) var totalScriptCount: Int = 0

    /// Number of scripts currently matched for the active tab's URL.
    @Published private(set) var activeScriptCount: Int = 0

    /// Recent userscript runtime errors (Chrome-style extension error log).
    @Published private(set) var runtimeErrors: [UserScriptRuntimeErrorEntry] = []

    /// Whether the loaded userscript runtime is active.
    /// This is module-owned in-memory state, not a persisted master switch.
    @Published var isEnabled: Bool = false {
        didSet {
            guard oldValue != isEnabled else { return }
            if isEnabled {
                activate()
            } else {
                deactivate()
            }
        }
    }

    // MARK: - Internal Components (nil when disabled)

    private var store: UserScriptStore?
    private var injector: UserScriptInjector?
    private let context: ModelContext?
    private let storeFactory: @MainActor (ModelContext?) -> UserScriptStore
    private let injectorFactory: @MainActor () -> UserScriptInjector
    weak var browserManager: BrowserManager?

    // Track which webViews have been configured (to avoid double injection)
    private var configuredWebViews: NSHashTable<WKWebView> = .weakObjects()

    private static let runtimeErrorLimit = 200
    private var runtimeErrorObserver: NSObjectProtocol?
    private var autoUpdateTask: Task<Void, Never>?

    // MARK: - Init

    init(
        context: ModelContext? = nil,
        storeFactory: @escaping @MainActor (ModelContext?) -> UserScriptStore = {
            UserScriptStore(context: $0)
        },
        injectorFactory: @escaping @MainActor () -> UserScriptInjector = {
            UserScriptInjector()
        }
    ) {
        self.context = context
        self.storeFactory = storeFactory
        self.injectorFactory = injectorFactory
    }

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
        injector?.tabHandler = self
        injector?.browserManager = browserManager
    }

    // MARK: - Activation / Deactivation

    func activateFromUserscriptsModule() {
        guard isEnabled == false else {
            activate()
            return
        }
        isEnabled = true
    }

    func deactivateFromUserscriptsModule() {
        guard isEnabled else {
            deactivate()
            return
        }
        isEnabled = false
    }

    /// Fully activate the userscript system:
    /// - Creates the store (loads scripts from disk, starts watcher)
    /// - Creates the injector
    /// - Updates counts
    private func activate() {
        guard store == nil else { return }

        let newStore = storeFactory(context)
        newStore.onScriptsChanged = { [weak self] in
            Task { @MainActor in
                self?.totalScriptCount = self?.store?.scripts.count ?? 0
            }
        }

        store = newStore
        let newInjector = injectorFactory()
        newInjector.tabHandler = self
        newInjector.browserManager = browserManager
        injector = newInjector
        totalScriptCount = newStore.scripts.count

        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: .sumiUserScriptRuntimeError,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let snapshot = UserScriptRuntimeErrorNotificationSnapshot(notification: notification)
            Task { @MainActor in
                guard let self else { return }
                self.recordRuntimeError(from: snapshot)
            }
        }

        RuntimeDiagnostics.debug(
            "Activated with \(totalScriptCount) script(s) loaded",
            category: "SumiScripts"
        )

        if newStore.autoUpdateInterval == "startup" {
            Task { @MainActor in
                await newStore.updateInstalledScripts()
                self.reloadScripts()
            }
        }
        restartPeriodicAutoUpdateIfNeeded()
    }

    /// Fully deactivate the userscript system:
    /// - Stops file watcher
    /// - Releases injector + all bridges
    /// - Zeros out counts
    /// - Result: zero memory/CPU impact
    private func deactivate() {
        autoUpdateTask?.cancel()
        autoUpdateTask = nil
        if let runtimeErrorObserver {
            NotificationCenter.default.removeObserver(runtimeErrorObserver)
            self.runtimeErrorObserver = nil
        }
        runtimeErrors.removeAll()

        store = nil
        injector = nil
        configuredWebViews.removeAllObjects()
        totalScriptCount = 0
        activeScriptCount = 0

        RuntimeDiagnostics.debug(
            "Deactivated with zero resource impact",
            category: "SumiScripts"
        )
    }

    // MARK: - Script Access

    /// All loaded scripts (empty when disabled).
    var allScripts: [SumiInstalledUserScript] {
        store?.scripts ?? []
    }

    var scriptsDirectory: URL {
        store?.scriptsDirectory ?? UserScriptStore.defaultScriptsDirectory()
    }

    /// Rows for the toolbar popover on this page (non-empty HTTP(S) host only).
    /// - strict: every script so each row’s switch is the per-site allowlist.
    /// - always: enabled scripts whose `@match` applies here, **including** site-disabled ones so the switch can turn them back on without running `scriptsForURL` injection.
    func popoverScripts(for url: URL) -> [SumiInstalledUserScript] {
        let sorted = allScripts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        switch runMode {
        case .strictOrigin:
            return sorted
        case .alwaysMatch:
            return sorted.filter { script in
                guard script.isEnabled else { return false }
                return UserScriptMatchEngine.shouldInject(script: script, into: url)
            }
        }
    }

    /// Toggle a specific script on/off.
    func setScriptEnabled(_ enabled: Bool, filename: String) {
        store?.setEnabled(enabled, for: filename)
        totalScriptCount = store?.scripts.count ?? 0
        objectWillChange.send()
    }

    var runMode: UserScriptRunMode {
        get { store?.effectiveRunMode ?? .alwaysMatch }
        set {
            guard let store else { return }
            store.runMode = newValue
            objectWillChange.send()
        }
    }

    var lazyScriptBodyEnabled: Bool {
        get { store?.lazyScriptBodyEnabled ?? false }
        set {
            guard let store else { return }
            store.lazyScriptBodyEnabled = newValue
            objectWillChange.send()
            reloadScripts()
        }
    }

    /// `off`, `startup`, `hourly`, `daily`
    var autoUpdateInterval: String {
        get { store?.autoUpdateInterval ?? "off" }
        set {
            guard let store else { return }
            store.autoUpdateInterval = newValue
            objectWillChange.send()
            restartPeriodicAutoUpdateIfNeeded()
        }
    }

    func setOriginAllow(_ allowed: Bool, filename: String, for url: URL) {
        store?.setOriginAllow(allowed, filename: filename, for: url)
        objectWillChange.send()
    }

    func setOriginDeny(_ denied: Bool, filename: String, for url: URL) {
        store?.setOriginDeny(denied, filename: filename, for: url)
        objectWillChange.send()
    }

    func isOriginAllowed(filename: String, for url: URL) -> Bool {
        store?.isOriginAllowed(filename: filename, for: url) ?? false
    }

    func isOriginDenied(filename: String, for url: URL) -> Bool {
        store?.isOriginDenied(filename: filename, for: url) ?? false
    }

    func exportBackup(to zipURL: URL, includeOriginRules: Bool) throws {
        guard let store else {
            throw SumiScriptsManagerError.managerDisabled
        }
        try store.exportBackupArchive(to: zipURL, includeOriginRules: includeOriginRules)
    }

    func importBackup(from zipURL: URL) throws -> Int {
        guard let store else {
            throw SumiScriptsManagerError.managerDisabled
        }
        let n = try store.importBackupArchive(from: zipURL)
        totalScriptCount = store.scripts.count
        return n
    }

    private func restartPeriodicAutoUpdateIfNeeded() {
        autoUpdateTask?.cancel()
        autoUpdateTask = nil
        guard isEnabled, let store else { return }
        let interval = store.autoUpdateInterval
        guard interval == "hourly" || interval == "daily" else { return }
        let sleepNanos: UInt64 = interval == "hourly" ? 3_600_000_000_000 : 86_400_000_000_000
        autoUpdateTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: sleepNanos)
                if Task.isCancelled { break }
                await store.updateInstalledScripts()
                self.reloadScripts()
            }
        }
    }

    /// Force reload all scripts from disk.
    func reloadScripts() {
        store?.reload()
        totalScriptCount = store?.scripts.count ?? 0
    }

    func deleteScript(filename: String) {
        store?.delete(filename: filename)
        totalScriptCount = store?.scripts.count ?? 0
    }

    func updateAllScripts() {
        guard isEnabled, let store else { return }
        Task { @MainActor in
            await store.updateInstalledScripts()
            self.reloadScripts()
        }
    }

    func clearRuntimeErrors() {
        runtimeErrors.removeAll()
    }

    private func recordRuntimeError(from snapshot: UserScriptRuntimeErrorNotificationSnapshot) {
        guard isEnabled else { return }
        let message = snapshot.message
        guard UserScriptRuntimeErrorLogFilter.shouldRecord(message: message) else { return }
        let entry = UserScriptRuntimeErrorEntry(
            id: UUID(),
            date: Date(),
            scriptFilename: snapshot.scriptFilename,
            kind: snapshot.kind,
            message: message,
            location: snapshot.location,
            stack: snapshot.stack
        )
        runtimeErrors.insert(entry, at: 0)
        if runtimeErrors.count > Self.runtimeErrorLimit {
            runtimeErrors.removeSubrange(Self.runtimeErrorLimit..<runtimeErrors.count)
        }
    }

    @discardableResult
    func installScript(from url: URL, requiresConfirmation: Bool = true) async -> Bool {
        guard isEnabled else { return false }
        do {
            if requiresConfirmation {
                let preview = try await SumiScriptsRemoteInstall.previewScript(from: url)
                guard SumiScriptsRemoteInstall.confirmInstall(preview: preview, url: url) else {
                    return false
                }
            }
            let installed = try await store?.installScript(from: url)
            totalScriptCount = store?.scripts.count ?? 0
            RuntimeDiagnostics.debug(
                "Installed userscript \(installed?.name ?? url.absoluteString)",
                category: "SumiScripts"
            )
            return true
        } catch {
            SumiScriptsRemoteInstall.showInstallError(error, url: url)
            return false
        }
    }

    func interceptInstallNavigationIfNeeded(_ url: URL) -> Bool {
        guard isEnabled, SumiScriptsRemoteInstall.isUserscriptURL(url) else { return false }
        Task { @MainActor in
            _ = await self.installScript(from: url)
        }
        return true
    }

    // MARK: - Injection API (called from Tab lifecycle)

    func normalTabUserScripts(
        for url: URL,
        webViewId: UUID,
        profileId: UUID? = nil,
        isEphemeral: Bool = false
    ) -> [SumiUserScript] {
        guard isEnabled, let store, let injector else { return [] }

        let matchingScripts = store.scriptsForURL(url)
        guard !matchingScripts.isEmpty else {
            injector.cleanupBridges(for: webViewId)
            activeScriptCount = 0
            return []
        }

        let userScripts = injector.makeUserScripts(
            scripts: matchingScripts,
            webViewId: webViewId,
            profileId: profileId,
            isEphemeral: isEphemeral
        )
        activeScriptCount = matchingScripts.count

        RuntimeDiagnostics.debug(
            "Prepared \(matchingScripts.count) Sumi userscript(s) for \(url.host ?? url.absoluteString)",
            category: "SumiScripts"
        )
        return userScripts
    }

    /// Clean up when a tab is closed or webView is deallocated.
    /// Call this from Tab.closeTab() or deinit.
    func cleanupWebView(controller: WKUserContentController, webViewId: UUID) {
        injector?.cleanupBridges(for: webViewId, from: controller)
    }

    func executeMenuCommand(script: SumiInstalledUserScript, commandId: String, webView: WKWebView?) {
        injector?.executeMenuCommand(script: script, commandId: commandId, webView: webView)
    }

}

enum SumiScriptsManagerError: LocalizedError {
    case managerDisabled

    var errorDescription: String? {
        switch self {
        case .managerDisabled:
            return "Enable SumiScripts before import or export."
        }
    }
}

// MARK: - Runtime diagnostics

/// Filters known engine/page noise so the userscript error log stays actionable.
enum UserScriptRuntimeErrorLogFilter {
    static func shouldRecord(message: String) -> Bool {
        !shouldSuppress(message: message)
    }

    static func shouldSuppress(message: String) -> Bool {
        if message.contains("ResizeObserver loop completed with undelivered notifications") {
            return true
        }
        return false
    }
}

struct UserScriptRuntimeErrorEntry: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let scriptFilename: String
    let kind: String
    let message: String
    let location: String
    let stack: String
}

private struct UserScriptRuntimeErrorNotificationSnapshot: Sendable {
    let scriptFilename: String
    let kind: String
    let message: String
    let location: String
    let stack: String

    init(notification: Notification) {
        let info = notification.userInfo ?? [:]
        self.scriptFilename = info["scriptFilename"] as? String ?? "unknown"
        self.kind = info["kind"] as? String ?? "error"
        self.message = info["message"] as? String ?? ""
        self.location = info["location"] as? String ?? ""
        self.stack = info["stack"] as? String ?? ""
    }
}

// MARK: - SumiScriptsTabHandler

extension SumiScriptsManager: SumiScriptsTabHandler {
    func openTab(url: String, background: Bool) {
        guard let browserManager else { return }
        let tab = browserManager.tabManager.createNewTab(
            url: url,
            in: browserManager.tabManager.currentSpace
        )
        if background == false {
            tab.activate()
        }
    }

    func closeTab(tabId: String?) {
        guard let browserManager else { return }
        if let tabId, let uuid = UUID(uuidString: tabId) {
            browserManager.tabManager.removeTab(uuid)
        } else if let active = browserManager.tabManager.currentTab {
            browserManager.tabManager.removeTab(active.id)
        }
    }
}
