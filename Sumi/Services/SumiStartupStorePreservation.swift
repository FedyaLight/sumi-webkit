import Foundation

extension SumiStartupStoreRecovery {
    static func quarantine(
        storeURL: URL,
        quarantineRootURL: URL,
        failure: Error,
        perform: RecoveryOperationRunner = { _, operation in try operation() }
    ) throws -> Quarantine {
        let fileManager = FileManager.default
        let incidentID = UUID()
        guard fileManager.fileExists(atPath: storeURL.path) else {
            throw RecoveryError.missingPrimaryStore(storeURL)
        }

        try perform(.createQuarantineRoot) {
            try fileManager.createDirectory(
                at: quarantineRootURL,
                withIntermediateDirectories: true
            )
        }
        try perform(.synchronizeQuarantineRootParent) {
            try SumiStartupStoreIO.synchronizeDirectory(
                at: quarantineRootURL.deletingLastPathComponent()
            )
        }

        let stagingURL = quarantineRootURL.appendingPathComponent(
            ".staging-\(incidentID.uuidString)",
            isDirectory: true
        )
        let quarantineURL = quarantineRootURL.appendingPathComponent(
            "incident-\(incidentID.uuidString)",
            isDirectory: true
        )
        let preservedDirectoryURL = stagingURL.appendingPathComponent(
            preservedDirectoryName,
            isDirectory: true
        )
        var didPublish = false

        defer {
            if !didPublish {
                SumiStartupStoreIO.removeUnpublishedStagingArtifact(at: stagingURL)
            }
        }

        try perform(.createStagingTree) {
            try fileManager.createDirectory(
                at: preservedDirectoryURL,
                withIntermediateDirectories: true
            )
        }
        let sourceFamily = try preserveFamily(
            at: storeURL,
            in: preservedDirectoryURL,
            fileManager: fileManager,
            perform: perform
        )
        let manifest = try makeManifest(
            sourceFamily: sourceFamily,
            storeURL: storeURL,
            failure: failure,
            incidentID: incidentID,
            fileManager: fileManager
        )
        try validatePreservedFiles(
            manifest.files,
            in: preservedDirectoryURL,
            quarantineURL: stagingURL,
            fileManager: fileManager
        )
        try publishManifestAndIncident(
            manifest,
            stagingURL: stagingURL,
            quarantineURL: quarantineURL,
            quarantineRootURL: quarantineRootURL,
            perform: perform
        )
        didPublish = true

        return Quarantine(
            directoryURL: quarantineURL,
            preservedStoreURL: quarantineURL
                .appendingPathComponent(preservedDirectoryName, isDirectory: true)
                .appendingPathComponent(storeURL.lastPathComponent, isDirectory: false)
        )
    }

    private static func preserveFamily(
        at storeURL: URL,
        in preservedDirectoryURL: URL,
        fileManager: FileManager,
        perform: RecoveryOperationRunner
    ) throws -> [URL] {
        let sourceFamily = familySuffixes
            .map { familyURL(base: storeURL, suffix: $0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
        for sourceURL in sourceFamily {
            let destinationURL = preservedDirectoryURL.appendingPathComponent(
                sourceURL.lastPathComponent,
                isDirectory: false
            )
            try perform(.copyFamilyFile(sourceURL.lastPathComponent)) {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
            try perform(.synchronizeFamilyFile(sourceURL.lastPathComponent)) {
                try SumiStartupStoreIO.synchronizeFile(at: destinationURL)
            }
        }
        try perform(.synchronizePreservedDirectory) {
            try SumiStartupStoreIO.synchronizeDirectory(at: preservedDirectoryURL)
        }
        return sourceFamily
    }

    private static func makeManifest(
        sourceFamily: [URL],
        storeURL: URL,
        failure: Error,
        incidentID: UUID,
        fileManager: FileManager
    ) throws -> Manifest {
        let files = try sourceFamily.map { fileURL in
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            return Manifest.FileRecord(
                name: fileURL.lastPathComponent,
                byteCount: byteCount,
                sha256: try SumiStartupStoreIO.sha256Digest(at: fileURL)
            )
        }

        return Manifest(
            formatVersion: 2,
            incidentID: incidentID,
            createdAt: Date(),
            reason: "sqliteCorruption",
            storeFileName: storeURL.lastPathComponent,
            files: files,
            errors: errorRecords(for: failure)
        )
    }

    private static func publishManifestAndIncident(
        _ manifest: Manifest,
        stagingURL: URL,
        quarantineURL: URL,
        quarantineRootURL: URL,
        perform: RecoveryOperationRunner
    ) throws {
        let manifestURL = stagingURL.appendingPathComponent(
            manifestFileName,
            isDirectory: false
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try perform(.writeManifest) {
            try encoder.encode(manifest).write(to: manifestURL, options: .withoutOverwriting)
        }
        try perform(.synchronizeManifest) {
            try SumiStartupStoreIO.synchronizeFile(at: manifestURL)
        }
        try perform(.synchronizeStagingDirectory) {
            try SumiStartupStoreIO.synchronizeDirectory(at: stagingURL)
        }
        try perform(.publishIncident) {
            try SumiStartupStoreIO.atomicRename(from: stagingURL, to: quarantineURL)
        }
        try perform(.synchronizeQuarantineRoot) {
            try SumiStartupStoreIO.synchronizeDirectory(at: quarantineRootURL)
        }
    }

    private static func errorRecords(for failure: Error) -> [Manifest.ErrorRecord] {
        var records: [Manifest.ErrorRecord] = []
        var visited = Set<ObjectIdentifier>()

        func append(_ error: Error) {
            let ns = error as NSError
            let identity = ObjectIdentifier(ns)
            guard visited.insert(identity).inserted else { return }
            records.append(
                Manifest.ErrorRecord(
                    domain: ns.domain,
                    code: ns.code,
                    description: ns.localizedDescription
                )
            )

            for key in [
                NSUnderlyingErrorKey,
                NSMultipleUnderlyingErrorsKey,
                "NSDetailedErrors",
            ] {
                guard let value = ns.userInfo[key] else { continue }
                if let nested = value as? Error {
                    append(nested)
                } else if let nested = value as? [Any] {
                    for value in nested {
                        if let nestedError = value as? Error {
                            append(nestedError)
                        }
                    }
                }
            }
        }

        append(failure)
        return records
    }
}
