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
    let extensionsModule: SumiExtensionsModule
    let userscriptsModule: SumiUserscriptsModule
    let boostsModule: SumiBoostsModule
    let liveFoldersModule: SumiLiveFoldersModule

    init(
        extensionsModule: SumiExtensionsModule,
        userscriptsModule: SumiUserscriptsModule,
        boostsModule: SumiBoostsModule,
        liveFoldersModule: SumiLiveFoldersModule
    ) {
        self.extensionsModule = extensionsModule
        self.userscriptsModule = userscriptsModule
        self.boostsModule = boostsModule
        self.liveFoldersModule = liveFoldersModule
    }

    func isEnabled(_ moduleID: SumiModuleID) -> Bool {
        switch moduleID {
        case .extensions:
            return extensionsModule.isEnabled
        case .userScripts:
            return userscriptsModule.isEnabled
        case .boosts:
            return boostsModule.isEnabled
        case .liveFolders:
            return liveFoldersModule.isEnabled
        }
    }

    var isExtensionsEnabled: Bool { extensionsModule.isEnabled }
    var isUserscriptsEnabled: Bool { userscriptsModule.isEnabled }
    var isBoostsEnabled: Bool { boostsModule.isEnabled }
    var isLiveFoldersEnabled: Bool { liveFoldersModule.isEnabled }

    /// Wires optional-module runtimes from BrowserManager factories.
    ///
    /// W4/R9: attaches **only** when a module is currently enabled. Disabled
    /// modules keep a runtime provider so a later `setEnabled(true)` can attach
    /// without a second wiring pass.
    func attachEnabled(into browserManager: BrowserManager) {
        bindRuntimeProviders(into: browserManager)

        if extensionsModule.isEnabled {
            extensionsModule.attach(
                runtime: BrowserExtensionsModuleRuntimeFactory.runtime(for: browserManager)
            )
        }
        if userscriptsModule.isEnabled {
            userscriptsModule.attach(
                runtime: BrowserUserscriptRuntimeFactory.runtime(for: browserManager)
            )
        }
        if boostsModule.isEnabled {
            boostsModule.attach(
                runtime: BrowserBoostRuntimeFactory.runtime(for: browserManager)
            )
        }
        if liveFoldersModule.isEnabled {
            liveFoldersModule.attach(
                runtime: BrowserLiveFolderRuntimeService.runtime(for: browserManager)
            )
        }
    }

    /// Binds lazy runtime providers so enable-after-startup can attach without
    /// re-running BrowserManagerRuntimeWiring.
    private func bindRuntimeProviders(into browserManager: BrowserManager) {
        extensionsModule.bindRuntimeProvider { [weak browserManager] in
            guard let browserManager else { return .inactive }
            return BrowserExtensionsModuleRuntimeFactory.runtime(for: browserManager)
        }
        userscriptsModule.bindRuntimeProvider { [weak browserManager] in
            guard let browserManager else { return .inactive }
            return BrowserUserscriptRuntimeFactory.runtime(for: browserManager)
        }
        boostsModule.bindRuntimeProvider { [weak browserManager] in
            guard let browserManager else { return .empty }
            return BrowserBoostRuntimeFactory.runtime(for: browserManager)
        }
        liveFoldersModule.bind(
            manager: browserManager.liveFolderManager,
            runtimeProvider: { [weak browserManager] in
                guard let browserManager else { return .inactive }
                return BrowserLiveFolderRuntimeService.runtime(for: browserManager)
            }
        )
    }
}
