import CryptoKit
import Foundation
import SumiDomain
import WebKit

@available(macOS 15.5, *)
@MainActor
final class InternalWebExtensionContributionOwner {
    private static let resourceSchemaVersion = "2"

    private struct LoadedContribution {
        let fingerprint: String
        let context: WKWebExtensionContext
    }

    private let controllerProvisioning: any ExtensionControllerProvisioning
    private let resourceBuilder: InternalURLCleaningExtensionResourceBuilder
    private var desiredByProfile: [UUID: SumiURLCleaningContribution] = [:]
    private var loadedByProfile: [UUID: LoadedContribution] = [:]
    private var revisionsByProfile: [UUID: UInt64] = [:]
    private var tasksByProfile: [UUID: Task<Void, Never>] = [:]

    init(
        controllerProvisioning: any ExtensionControllerProvisioning,
        resourceBuilder: InternalURLCleaningExtensionResourceBuilder = .init()
    ) {
        self.controllerProvisioning = controllerProvisioning
        self.resourceBuilder = resourceBuilder
    }

    func reconcile(
        _ contribution: SumiURLCleaningContribution?,
        profileID: UUID
    ) {
        let scopeID = profileID
        let revision = (revisionsByProfile[scopeID] ?? 0) &+ 1
        revisionsByProfile[scopeID] = revision
        tasksByProfile.removeValue(forKey: scopeID)?.cancel()

        guard let contribution else {
            desiredByProfile.removeValue(forKey: scopeID)
            unload(scopeID: scopeID)
            let fingerprints = activeFingerprints()
            Task {
                await resourceBuilder.removeResources(keeping: fingerprints)
            }
            return
        }
        desiredByProfile[scopeID] = contribution
        guard let controller = controllerProvisioning.controllerIfAdmitted(
            for: profileID,
            mutationLease: nil
        ) else {
            return
        }

        let fingerprint = Self.fingerprint(for: contribution)
        if loadedByProfile[scopeID]?.fingerprint == fingerprint {
            return
        }
        unload(scopeID: scopeID)
        tasksByProfile[scopeID] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if revisionsByProfile[scopeID] == revision {
                    tasksByProfile.removeValue(forKey: scopeID)
                }
            }
            do {
                let resourceURL = try await resourceBuilder.resources(
                    for: contribution,
                    fingerprint: fingerprint
                )
                try Task.checkCancellation()
                let webExtension = try await WKWebExtension(
                    resourceBaseURL: resourceURL
                )
                if let validationError = webExtension.errors.first {
                    throw validationError
                }
                try Task.checkCancellation()
                let context = WKWebExtensionContext(for: webExtension)
                Self.configure(
                    context,
                    webExtension: webExtension,
                    profileID: profileID,
                    fingerprint: fingerprint
                )
                try controller.load(context)
                guard revisionsByProfile[scopeID] == revision,
                      desiredByProfile[scopeID] == contribution
                else {
                    try? controller.unload(context)
                    return
                }
                let previous = loadedByProfile.updateValue(
                    LoadedContribution(
                        fingerprint: fingerprint,
                        context: context
                    ),
                    forKey: scopeID
                )
                if let previous, previous.context !== context {
                    try? controller.unload(previous.context)
                }
                await resourceBuilder.removeResources(
                    keeping: activeFingerprints()
                )
            } catch is CancellationError {
                await resourceBuilder.removeResources(
                    keeping: activeFingerprints()
                )
                return
            } catch {
                RuntimeDiagnostics.debug(category: "ContentBlocking") {
                    "Internal URL-cleaning extension failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func removeAll() {
        for task in tasksByProfile.values {
            task.cancel()
        }
        tasksByProfile.removeAll()
        desiredByProfile.removeAll()
        revisionsByProfile.removeAll()
        for scopeID in Array(loadedByProfile.keys) {
            unload(scopeID: scopeID)
        }
        Task {
            await resourceBuilder.removeResources(keeping: [])
        }
    }

    func waitUntilReady(profileID: UUID) async
        -> PageNavigationPrerequisiteResult {
        let scopeID = profileID
        guard let desired = desiredByProfile[scopeID] else { return .ready }
        let fingerprint = Self.fingerprint(for: desired)
        if loadedByProfile[scopeID]?.fingerprint == fingerprint {
            return .ready
        }
        if let task = tasksByProfile[scopeID] {
            await task.value
        }
        if Task.isCancelled { return .cancelled }
        return loadedByProfile[scopeID]?.fingerprint == fingerprint
            ? .ready
            : .degraded
    }

    #if DEBUG
        func drainTasksForTests() async {
            let tasks = Array(tasksByProfile.values)
            for task in tasks {
                await task.value
            }
        }

        func loadedContextForTests(profileID: UUID) -> WKWebExtensionContext? {
            loadedByProfile[profileID]?.context
        }
    #endif

    private func unload(scopeID: UUID) {
        guard let loaded = loadedByProfile.removeValue(forKey: scopeID),
              let controller = loaded.context.webExtensionController
        else {
            return
        }
        try? controller.unload(loaded.context)
    }

    private static func fingerprint(
        for contribution: SumiURLCleaningContribution
    ) -> String {
        let value = ([
            resourceSchemaVersion,
            contribution.generationID,
        ] + contribution.disabledDomains.sorted()).joined(separator: "\n")
        return SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func configure(
        _ context: WKWebExtensionContext,
        webExtension: WKWebExtension,
        profileID: UUID,
        fingerprint: String
    ) {
        let extensionID = "sumi.internal.url-cleaning.\(fingerprint.prefix(16))"
        ExtensionContextPreparation.configureIdentity(
            context,
            extensionID: extensionID,
            profileID: profileID,
            runtimeIdentifier: "\(profileID.uuidString).\(extensionID)"
        )
        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        let patterns = webExtension.requestedPermissionMatchPatterns
            .union(webExtension.allRequestedMatchPatterns)
        for pattern in patterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
        context.hasRequestedOptionalAccessToAllHosts = true
        context.hasAccessToPrivateData = true
        context.isInspectable = RuntimeDiagnostics.isDeveloperInspectionEnabled
    }

    private func activeFingerprints() -> Set<String> {
        Set(desiredByProfile.values.map(Self.fingerprint(for:)))
    }
}

actor InternalURLCleaningExtensionResourceBuilder {
    private static let ruleIDBase = 1_500_000
    private static let maximumRuleCount = 5_000

    private let fileManager: FileManager
    private let rootDirectory: URL

    init(
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let canonical = SumiApplicationSupportDirectory
                .cachesRootURL(fileManager: fileManager)
                .appendingPathComponent(
                    "InternalWebExtensions/URLCleaning",
                    isDirectory: true
                )
            let legacy = fileManager.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent(
                "Sumi/InternalWebExtensions/URLCleaning",
                isDirectory: true
            )
            self.rootDirectory = SumiApplicationSupportDirectory
                .migrateLegacyDirectoryIfNeeded(
                    from: legacy,
                    to: canonical,
                    fileManager: fileManager
                )
        }
    }

    func resources(
        for contribution: SumiURLCleaningContribution,
        fingerprint: String
    ) throws -> URL {
        let directory = rootDirectory.appendingPathComponent(
            fingerprint,
            isDirectory: true
        )
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let rulesURL = directory.appendingPathComponent("rules.json")
        if fileManager.fileExists(atPath: manifestURL.path),
           fileManager.fileExists(atPath: rulesURL.path) {
            return directory
        }

        let sourceData = try Data(
            contentsOf: contribution.rulesURL,
            options: [.mappedIfSafe]
        )
        guard var rules = try JSONSerialization.jsonObject(with: sourceData)
            as? [[String: Any]]
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var generated = Self.disabledSiteAllowRules(
            contribution.disabledDomains
        )
        let remaining = max(0, Self.maximumRuleCount - generated.count)
        rules = Array(rules.prefix(remaining))
        for index in rules.indices {
            rules[index]["id"] = Self.ruleIDBase + generated.count + index
        }
        generated.append(contentsOf: rules)

        let transaction = rootDirectory.appendingPathComponent(
            ".staging-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: transaction) }
        try fileManager.createDirectory(
            at: transaction,
            withIntermediateDirectories: true
        )
        let manifest = Self.manifest
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        ).write(
            to: transaction.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        try JSONSerialization.data(
            withJSONObject: generated,
            options: [.sortedKeys]
        ).write(
            to: transaction.appendingPathComponent("rules.json"),
            options: .atomic
        )
        try fileManager.createDirectory(
            at: directory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: directory.path) == false {
            try fileManager.moveItem(at: transaction, to: directory)
        }
        return directory
    }

    func removeResources(keeping fingerprints: Set<String>) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return
        }
        for entry in entries where fingerprints.contains(entry.lastPathComponent) == false {
            guard let values = try? entry.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ),
            values.isDirectory == true,
            values.isSymbolicLink != true
            else {
                continue
            }
            try? fileManager.removeItem(at: entry)
        }
    }

    private static var manifest: [String: Any] {
        [
            "manifest_version": 3,
            "name": "Sumi URL Cleaning",
            "description": "Removes tracking parameters from navigations.",
            "version": "1.0.0",
            "permissions": [
                "declarativeNetRequest",
                "declarativeNetRequestWithHostAccess",
            ],
            "host_permissions": ["<all_urls>"],
            "declarative_net_request": [
                "rule_resources": [[
                    "id": "sumi_url_cleaning",
                    "enabled": true,
                    "path": "rules.json",
                ]],
            ],
        ]
    }

    private static func disabledSiteAllowRules(
        _ domains: [String]
    ) -> [[String: Any]] {
        var rules: [[String: Any]] = []
        let normalizer = SumiProtectionSiteNormalizer()
        let normalizedDomains = Set(
            domains.compactMap(normalizer.normalizedHost(fromRawHost:))
        ).sorted()
        for domain in normalizedDomains where rules.count + 2 <= maximumRuleCount {
            rules.append([
                "id": ruleIDBase + rules.count,
                "priority": 20_000,
                "action": ["type": "allow"],
                "condition": [
                    "resourceTypes": ["main_frame", "sub_frame"],
                    "requestDomains": [domain],
                ],
            ])
            rules.append([
                "id": ruleIDBase + rules.count,
                "priority": 20_000,
                "action": ["type": "allow"],
                "condition": [
                    "resourceTypes": [
                        "main_frame", "sub_frame", "xmlhttprequest",
                    ],
                    "initiatorDomains": [domain],
                ],
            ])
        }
        return rules
    }
}
