//
//  NativeMessagingHostManifestResolver.swift
//  Sumi
//
//  Generic standard native-messaging host discovery.
//

import AppKit
import Foundation

struct StandardNativeMessagingHostMapping: Sendable, Equatable {
    let nativeHostName: String
    let displayName: String
    let requestedApplicationIdentifiers: [String]
    let registryHostBundleIdentifiers: [String]
    let appBundleIdentifiers: [String]
    let manifestFileName: String
    let embeddedHostExecutableRelativePaths: [String]
    let explicitApplicationBundleURLs: [URL]

    init(
        nativeHostName: String,
        displayName: String,
        requestedApplicationIdentifiers: [String] = [],
        registryHostBundleIdentifiers: [String],
        appBundleIdentifiers: [String] = [],
        manifestFileName: String? = nil,
        embeddedHostExecutableRelativePaths: [String] = [],
        explicitApplicationBundleURLs: [URL] = []
    ) {
        self.nativeHostName = nativeHostName
        self.displayName = displayName
        self.requestedApplicationIdentifiers = Array(
            Set(requestedApplicationIdentifiers + [nativeHostName])
        ).sorted()
        self.registryHostBundleIdentifiers = registryHostBundleIdentifiers
        self.appBundleIdentifiers = appBundleIdentifiers
        self.manifestFileName = manifestFileName ?? "\(nativeHostName).json"
        self.embeddedHostExecutableRelativePaths = embeddedHostExecutableRelativePaths
        self.explicitApplicationBundleURLs = explicitApplicationBundleURLs
    }

    func supports(hostBundleIdentifier: String) -> Bool {
        let normalized = SumiCompanionAppIdentityMetadata
            .normalizedHostBundleIdentifier(hostBundleIdentifier)
        return registryHostBundleIdentifiers.contains(normalized)
            || requestedApplicationIdentifiers.contains(hostBundleIdentifier)
            || nativeHostName == hostBundleIdentifier
    }

    func matches(applicationIdentifier: String?) -> Bool {
        guard let applicationIdentifier = applicationIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            applicationIdentifier.isEmpty == false
        else {
            return false
        }
        if requestedApplicationIdentifiers.contains(applicationIdentifier)
            || nativeHostName == applicationIdentifier
        {
            return true
        }
        let normalized = SumiCompanionAppIdentityMetadata
            .normalizedHostBundleIdentifier(applicationIdentifier)
        return registryHostBundleIdentifiers.contains(normalized)
    }
}

enum NativeMessagingHostResolutionSourceKind: String, Codable, Sendable, Equatable {
    case nativeMessagingManifest
    case appBundleEmbeddedExecutable
    case configuredApplicationBundle
}

struct NativeMessagingHostManifest: Codable, Sendable, Equatable {
    let name: String?
    let path: String?
    let type: String?
}

enum NativeMessagingHostResolutionResult: Sendable, Equatable {
    case resolved(
        hostExecutable: URL,
        manifest: NativeMessagingHostManifest?,
        sourceKind: NativeMessagingHostResolutionSourceKind
    )
    case missingHostManifest(hostName: String)
    case missingHostExecutable(
        hostName: String,
        manifest: NativeMessagingHostManifest?,
        sourceKind: NativeMessagingHostResolutionSourceKind?
    )
    case unsupportedHostKind(
        hostName: String,
        manifest: NativeMessagingHostManifest?,
        sourceKind: NativeMessagingHostResolutionSourceKind?
    )
    case permissionDenied(hostName: String, sourceKind: NativeMessagingHostResolutionSourceKind?)
    case unknown(hostName: String)

    var hostExecutable: URL? {
        if case .resolved(let hostExecutable, _, _) = self {
            return hostExecutable
        }
        return nil
    }

    var sourceKind: NativeMessagingHostResolutionSourceKind? {
        switch self {
        case .resolved(_, _, let sourceKind):
            return sourceKind
        case .missingHostExecutable(_, _, let sourceKind):
            return sourceKind
        case .unsupportedHostKind(_, _, let sourceKind):
            return sourceKind
        case .permissionDenied(_, let sourceKind):
            return sourceKind
        case .missingHostManifest, .unknown:
            return nil
        }
    }
}

@MainActor
protocol NativeMessagingHostManifestResolving: AnyObject {
    func resolve(mapping: StandardNativeMessagingHostMapping) -> NativeMessagingHostResolutionResult
}

@MainActor
final class NativeMessagingHostManifestResolver: NativeMessagingHostManifestResolving {
    private let fileManager: FileManager
    private let appBundleURLResolver: (String) -> URL?

    init(
        fileManager: FileManager = .default,
        appBundleURLResolver: @escaping (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
    ) {
        self.fileManager = fileManager
        self.appBundleURLResolver = appBundleURLResolver
    }

    func resolve(mapping: StandardNativeMessagingHostMapping) -> NativeMessagingHostResolutionResult {
        if let manifestResult = resolveFromNativeHostManifest(mapping: mapping) {
            switch manifestResult {
            case .resolved:
                return manifestResult
            case .unsupportedHostKind, .permissionDenied, .missingHostExecutable, .unknown:
                return manifestResult
            case .missingHostManifest:
                break
            }
        }

        if let bundleResult = resolveFromApplicationBundles(mapping: mapping) {
            return bundleResult
        }

        NativeMessagingHostBackendDiagnostics.log(
            outcome: .hostManifestMissing,
            hostName: mapping.nativeHostName,
            backend: StandardNativeMessagingHostBackend.backendIdentifier,
            sourceKind: nil
        )
        return .missingHostManifest(hostName: mapping.nativeHostName)
    }

    private func resolveFromNativeHostManifest(
        mapping: StandardNativeMessagingHostMapping
    ) -> NativeMessagingHostResolutionResult? {
        for manifestURL in nativeHostManifestURLs(mapping: mapping) {
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                continue
            }

            let manifest: NativeMessagingHostManifest
            do {
                let data = try Data(contentsOf: manifestURL)
                manifest = try JSONDecoder().decode(NativeMessagingHostManifest.self, from: data)
            } catch {
                NativeMessagingHostBackendDiagnostics.log(
                    outcome: .unsupportedHostKind,
                    hostName: mapping.nativeHostName,
                    backend: StandardNativeMessagingHostBackend.backendIdentifier,
                    sourceKind: .nativeMessagingManifest
                )
                return .unsupportedHostKind(
                    hostName: mapping.nativeHostName,
                    manifest: nil,
                    sourceKind: .nativeMessagingManifest
                )
            }

            guard manifest.name == mapping.nativeHostName else {
                NativeMessagingHostBackendDiagnostics.log(
                    outcome: .unsupportedHostKind,
                    hostName: mapping.nativeHostName,
                    backend: StandardNativeMessagingHostBackend.backendIdentifier,
                    sourceKind: .nativeMessagingManifest
                )
                return .unsupportedHostKind(
                    hostName: mapping.nativeHostName,
                    manifest: manifest,
                    sourceKind: .nativeMessagingManifest
                )
            }

            if let type = manifest.type, type != "stdio" {
                NativeMessagingHostBackendDiagnostics.log(
                    outcome: .unsupportedHostKind,
                    hostName: mapping.nativeHostName,
                    backend: StandardNativeMessagingHostBackend.backendIdentifier,
                    sourceKind: .nativeMessagingManifest
                )
                return .unsupportedHostKind(
                    hostName: mapping.nativeHostName,
                    manifest: manifest,
                    sourceKind: .nativeMessagingManifest
                )
            }

            guard let path = manifest.path?.trimmingCharacters(in: .whitespacesAndNewlines),
                  path.isEmpty == false
            else {
                NativeMessagingHostBackendDiagnostics.log(
                    outcome: .hostExecutableMissing,
                    hostName: mapping.nativeHostName,
                    backend: StandardNativeMessagingHostBackend.backendIdentifier,
                    sourceKind: .nativeMessagingManifest
                )
                return .missingHostExecutable(
                    hostName: mapping.nativeHostName,
                    manifest: manifest,
                    sourceKind: .nativeMessagingManifest
                )
            }

            let executableURL = URL(
                fileURLWithPath: (path as NSString).expandingTildeInPath
            )
            return executableResolution(
                executableURL,
                mapping: mapping,
                manifest: manifest,
                sourceKind: .nativeMessagingManifest
            )
        }

        return nil
    }

    private func resolveFromApplicationBundles(
        mapping: StandardNativeMessagingHostMapping
    ) -> NativeMessagingHostResolutionResult? {
        var locatedApplicationBundle = false
        var permissionDenied = false
        let appURLs = configuredApplicationBundleURLs(mapping: mapping)

        for appURL in appURLs {
            locatedApplicationBundle = true
            for relativePath in mapping.embeddedHostExecutableRelativePaths {
                let executableURL = appURL.appendingRelativePath(relativePath)
                let result = executableResolution(
                    executableURL,
                    mapping: mapping,
                    manifest: nil,
                    sourceKind: .appBundleEmbeddedExecutable
                )
                switch result {
                case .resolved:
                    return result
                case .permissionDenied:
                    permissionDenied = true
                case .missingHostExecutable:
                    continue
                case .missingHostManifest, .unsupportedHostKind, .unknown:
                    continue
                }
            }
        }

        if permissionDenied {
            return .permissionDenied(
                hostName: mapping.nativeHostName,
                sourceKind: .appBundleEmbeddedExecutable
            )
        }

        if locatedApplicationBundle {
            NativeMessagingHostBackendDiagnostics.log(
                outcome: .hostExecutableMissing,
                hostName: mapping.nativeHostName,
                backend: StandardNativeMessagingHostBackend.backendIdentifier,
                sourceKind: .appBundleEmbeddedExecutable
            )
            return .missingHostExecutable(
                hostName: mapping.nativeHostName,
                manifest: nil,
                sourceKind: .appBundleEmbeddedExecutable
            )
        }

        return nil
    }

    private func executableResolution(
        _ executableURL: URL,
        mapping: StandardNativeMessagingHostMapping,
        manifest: NativeMessagingHostManifest?,
        sourceKind: NativeMessagingHostResolutionSourceKind
    ) -> NativeMessagingHostResolutionResult {
        if fileManager.isExecutableFile(atPath: executableURL.path) {
            NativeMessagingHostBackendDiagnostics.log(
                outcome: .hostExecutableFound,
                hostName: mapping.nativeHostName,
                backend: StandardNativeMessagingHostBackend.backendIdentifier,
                sourceKind: sourceKind
            )
            return .resolved(
                hostExecutable: executableURL,
                manifest: manifest,
                sourceKind: sourceKind
            )
        }

        if fileManager.fileExists(atPath: executableURL.path) {
            NativeMessagingHostBackendDiagnostics.log(
                outcome: .permissionDenied,
                hostName: mapping.nativeHostName,
                backend: StandardNativeMessagingHostBackend.backendIdentifier,
                sourceKind: sourceKind
            )
            return .permissionDenied(hostName: mapping.nativeHostName, sourceKind: sourceKind)
        }

        return .missingHostExecutable(
            hostName: mapping.nativeHostName,
            manifest: manifest,
            sourceKind: sourceKind
        )
    }

    private func nativeHostManifestURLs(mapping: StandardNativeMessagingHostMapping) -> [URL] {
        let baseURLs =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            + fileManager.urls(for: .applicationSupportDirectory, in: .localDomainMask)

        return baseURLs.flatMap { baseURL in
            Self.browserNativeHostDirectoryRelativePaths.map { relativeDirectory in
                baseURL
                    .appendingRelativePath(relativeDirectory)
                    .appendingPathComponent(mapping.manifestFileName, isDirectory: false)
            }
        }
    }

    private func configuredApplicationBundleURLs(
        mapping: StandardNativeMessagingHostMapping
    ) -> [URL] {
        var result: [URL] = []
        var seen = Set<String>()

        for bundleIdentifier in mapping.appBundleIdentifiers {
            guard let appURL = appBundleURLResolver(bundleIdentifier) else {
                continue
            }
            if seen.insert(appURL.path).inserted {
                result.append(appURL)
            }
        }

        for appURL in mapping.explicitApplicationBundleURLs {
            guard fileManager.fileExists(atPath: appURL.path) else { continue }
            if seen.insert(appURL.path).inserted {
                result.append(appURL)
            }
        }

        return result
    }

    private static let browserNativeHostDirectoryRelativePaths = [
        "Google/Chrome/NativeMessagingHosts",
        "Chromium/NativeMessagingHosts",
        "BraveSoftware/Brave-Browser/NativeMessagingHosts",
        "Microsoft Edge/NativeMessagingHosts",
        "Vivaldi/NativeMessagingHosts",
        "LibreWolf/NativeMessagingHosts",
        "Mozilla/NativeMessagingHosts",
    ]
}

private extension URL {
    func appendingRelativePath(_ relativePath: String) -> URL {
        URL(fileURLWithPath: (path as NSString).appendingPathComponent(relativePath))
    }
}

typealias NativeHostManifestResolver = NativeMessagingHostManifestResolver
