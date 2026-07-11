//
//  OptionalModuleHost.swift
//  Sumi
//
//  Architecture plan R5/W4: host for optional feature modules (extensions,
//  userscripts, boosts, live folders). Runtime wiring attaches through this
//  host only when a module is enabled (true lazy modules).
//

import Foundation

/// Holds optional-module shells and centralizes enablement checks + runtime attach.
@MainActor
final class OptionalModuleHost {
    let extensions: SumiExtensionsModule
    let userscripts: SumiUserscriptsModule
    let boosts: SumiBoostsModule
    let liveFolders: SumiLiveFoldersModule

    init(
        extensionsModule: SumiExtensionsModule,
        userscriptsModule: SumiUserscriptsModule,
        boostsModule: SumiBoostsModule,
        liveFoldersModule: SumiLiveFoldersModule
    ) {
        self.extensions = extensionsModule
        self.userscripts = userscriptsModule
        self.boosts = boostsModule
        self.liveFolders = liveFoldersModule
    }

    func isEnabled(_ moduleID: SumiModuleID) -> Bool {
        switch moduleID {
        case .extensions:
            return extensions.isEnabled
        case .userScripts:
            return userscripts.isEnabled
        case .boosts:
            return boosts.isEnabled
        case .liveFolders:
            return liveFolders.isEnabled
        }
    }

    var isExtensionsEnabled: Bool { extensions.isEnabled }
    var isUserscriptsEnabled: Bool { userscripts.isEnabled }
    var isBoostsEnabled: Bool { boosts.isEnabled }
    var isLiveFoldersEnabled: Bool { liveFolders.isEnabled }

    /// Wires optional-module runtimes from BrowserManager factories.
    ///
    /// W4/R9: attaches **only** when a module is currently enabled. Disabled
    /// modules keep a runtime provider so a later `setEnabled(true)` can attach
    /// without a second wiring pass.
    func attachEnabled(into browserManager: BrowserManager) {
        bindRuntimeProviders(into: browserManager)

        if extensions.isEnabled {
            extensions.attach(
                runtime: BrowserExtensionsModuleRuntimeFactory.runtime(for: browserManager)
            )
        }
        if userscripts.isEnabled {
            userscripts.attach(
                runtime: BrowserUserscriptRuntimeFactory.runtime(for: browserManager)
            )
        }
        if boosts.isEnabled {
            boosts.attach(
                runtime: BrowserBoostRuntimeFactory.runtime(for: browserManager)
            )
        }
        if liveFolders.isEnabled {
            liveFolders.attach(
                runtime: BrowserLiveFolderRuntimeService.runtime(for: browserManager)
            )
        }
    }

    /// Binds lazy runtime providers so enable-after-startup can attach without
    /// re-running BrowserManagerRuntimeWiring.
    private func bindRuntimeProviders(into browserManager: BrowserManager) {
        extensions.bindRuntimeProvider { [weak browserManager] in
            guard let browserManager else { return .inactive }
            return BrowserExtensionsModuleRuntimeFactory.runtime(for: browserManager)
        }
        userscripts.bindRuntimeProvider { [weak browserManager] in
            guard let browserManager else { return .inactive }
            return BrowserUserscriptRuntimeFactory.runtime(for: browserManager)
        }
        boosts.bindRuntimeProvider { [weak browserManager] in
            guard let browserManager else { return .empty }
            return BrowserBoostRuntimeFactory.runtime(for: browserManager)
        }
        liveFolders.bind(
            manager: browserManager.liveFolderManager,
            runtimeProvider: { [weak browserManager] in
                guard let browserManager else { return .inactive }
                return BrowserLiveFolderRuntimeService.runtime(for: browserManager)
            }
        )
    }
}
