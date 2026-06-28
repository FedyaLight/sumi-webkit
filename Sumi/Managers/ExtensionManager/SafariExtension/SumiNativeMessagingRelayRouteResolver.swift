//
//  SumiNativeMessagingRelayRouteResolver.swift
//  Sumi
//
//  Shared route resolution for Sumi's Safari native messaging relay.
//

import Foundation

@MainActor
struct SumiNativeMessagingRelayAdapterLookup {
    let adapter: SumiNativeMessagingProtocolAdapter?
    let adapterByApplicationIdentifier: SumiNativeMessagingProtocolAdapter?
}

@MainActor
struct SumiNativeMessagingRelayResolvedRoute {
    let evaluation: SumiCompanionAppResolverResult
    let detail: SumiCompanionAppResolutionDetail
    let hostBundleIdentifier: String
    let resolverBucket: SumiNativeMessagingResolverBucket
    let loopKey: SumiNativeMessagingRelayLoopGuard.SessionKey
    let loopEvaluation: SumiNativeMessagingRelayLoopGuard.Evaluation
    let adapterLookup: SumiNativeMessagingRelayAdapterLookup
}

@MainActor
enum SumiNativeMessagingRelayRouteResolution {
    case missingDetail(SumiCompanionAppResolverResult)
    case resolved(SumiNativeMessagingRelayResolvedRoute)
}

@MainActor
final class SumiNativeMessagingRelayRouteResolver {
    private let importStore: SafariExtensionImportStore
    private let launcher: SumiHostApplicationLaunching
    private let adapterRegistry: SumiNativeMessagingAdapterRegistry
    private let launchPolicy: SumiCompanionAppLaunchPolicy
    private let loopGuard: SumiNativeMessagingRelayLoopGuard

    init(
        importStore: SafariExtensionImportStore,
        launcher: SumiHostApplicationLaunching,
        adapterRegistry: SumiNativeMessagingAdapterRegistry,
        launchPolicy: SumiCompanionAppLaunchPolicy,
        loopGuard: SumiNativeMessagingRelayLoopGuard
    ) {
        self.importStore = importStore
        self.launcher = launcher
        self.adapterRegistry = adapterRegistry
        self.launchPolicy = launchPolicy
        self.loopGuard = loopGuard
    }

    func resolve(
        applicationIdentifier: String?,
        extensionId: String,
        profileId: UUID?,
        installedExtensions: [InstalledExtension]
    ) -> SumiNativeMessagingRelayRouteResolution {
        let evaluation = SumiCompanionAppResolver.evaluate(
            requestedApplicationIdentifier: applicationIdentifier,
            extensionId: extensionId,
            installedExtensions: installedExtensions,
            importStore: importStore,
            launcher: launcher,
            adapterRegistry: adapterRegistry,
            launchPolicy: launchPolicy
        )

        guard let detail = evaluation.detail else {
            return .missingDetail(evaluation)
        }

        let hostBundleIdentifier = detail.resolvedBundleIdentifier
        let loopKey = SumiNativeMessagingRelayLoopGuard.SessionKey(
            profileId: profileId,
            extensionId: extensionId,
            applicationIdentifier: SumiNativeMessagingRelayLoopGuard
                .canonicalApplicationIdentifier(
                    requested: applicationIdentifier,
                    hostBundleIdentifier: hostBundleIdentifier
                )
        )
        let loopEvaluation = loopGuard.evaluate(
            key: loopKey,
            hostBundleIdentifier: hostBundleIdentifier
        )
        let adapterLookup = resolveRegisteredAdapter(
            applicationIdentifier: applicationIdentifier,
            hostBundleIdentifier: hostBundleIdentifier
        )

        return .resolved(
            SumiNativeMessagingRelayResolvedRoute(
                evaluation: evaluation,
                detail: detail,
                hostBundleIdentifier: hostBundleIdentifier,
                resolverBucket: evaluation.legacyResolverBucket,
                loopKey: loopKey,
                loopEvaluation: loopEvaluation,
                adapterLookup: adapterLookup
            )
        )
    }

    private func resolveRegisteredAdapter(
        applicationIdentifier: String?,
        hostBundleIdentifier: String
    ) -> SumiNativeMessagingRelayAdapterLookup {
        let byHost = adapterRegistry.adapter(forHostBundleIdentifier: hostBundleIdentifier)
        let byApplication = adapterRegistry.adapter(forApplicationIdentifier: applicationIdentifier)
        if SafariExtensionNativeMessagingRoutingProbe
            .isSafariContainingApplicationRequest(applicationIdentifier) {
            return SumiNativeMessagingRelayAdapterLookup(
                adapter: byApplication,
                adapterByApplicationIdentifier: byApplication
            )
        }
        return SumiNativeMessagingRelayAdapterLookup(
            adapter: byHost ?? byApplication,
            adapterByApplicationIdentifier: byApplication
        )
    }
}
