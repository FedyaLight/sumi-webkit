import Foundation

/// Filesystem transaction used only after a structured SQLite corruption error.
/// The published quarantine is immutable; recovery always works from its copy.
enum SumiStartupStoreRecovery {
    enum RecoveryOperation: Equatable {
        case createQuarantineRoot
        case synchronizeQuarantineRootParent
        case createStagingTree
        case copyFamilyFile(String)
        case synchronizeFamilyFile(String)
        case synchronizePreservedDirectory
        case writeManifest
        case synchronizeManifest
        case synchronizeStagingDirectory
        case publishIncident
        case synchronizeQuarantineRoot
        case writeTransitionMarker(TransitionMarker.Phase)
        case synchronizeTransitionMarker(TransitionMarker.Phase)
        case publishTransitionMarker(TransitionMarker.Phase)
        case synchronizeTransitionParent(TransitionMarker.Phase)
        case removeActiveFamilyFile(TransitionMarker.Phase, String)
        case synchronizeActiveDirectoryAfterRemoval(TransitionMarker.Phase)
        case copyRestoredFamilyFile(String)
        case synchronizeRestoredFamilyFile(String)
        case synchronizeRestoredDirectory
        case removeTransitionMarker(TransitionMarker.Phase)
        case synchronizeTransitionCompletionDirectory(TransitionMarker.Phase)
    }

    typealias RecoveryOperationRunner = (
        RecoveryOperation,
        () throws -> Void
    ) throws -> Void

    struct Quarantine {
        let directoryURL: URL
        let preservedStoreURL: URL
    }

    struct Manifest: Codable, Equatable {
        struct FileRecord: Codable, Equatable {
            let name: String
            let byteCount: Int64
            let sha256: String
        }

        struct ErrorRecord: Codable, Equatable {
            let domain: String
            let code: Int
            let description: String
        }

        let formatVersion: Int
        let incidentID: UUID
        let createdAt: Date
        let reason: String
        let storeFileName: String
        let files: [FileRecord]
        let errors: [ErrorRecord]
    }

    struct TransitionMarker: Codable, Equatable {
        enum Phase: String, Codable {
            case restoringPreservedFamily
            case preparingFreshStore
        }

        let formatVersion: Int
        let phase: Phase
        let storeFileName: String
        let quarantineDirectoryPath: String
    }

    enum RecoveryError: Error {
        case missingPrimaryStore(URL)
        case invalidQuarantine(URL)
        case invalidTransitionMarker(URL)
    }

    static let manifestFileName = "manifest.json"
    static let preservedDirectoryName = "original"
    static let transitionMarkerFileName = ".sumi-startup-store-transition.json"

    static let familySuffixes = ["", "-wal", "-shm", "-journal"]

    static func restorePreservedFamily(
        from quarantine: Quarantine,
        to storeURL: URL,
        perform: RecoveryOperationRunner = { _, operation in try operation() }
    ) throws {
        try beginPreservedFamilyRestore(
            from: quarantine,
            to: storeURL,
            perform: perform
        )
        _ = try resumeInterruptedTransition(at: storeURL, perform: perform)
    }

    static func prepareFreshStore(
        at storeURL: URL,
        preserving quarantine: Quarantine,
        perform: RecoveryOperationRunner = { _, operation in try operation() }
    ) throws {
        try beginFreshStorePreparation(
            at: storeURL,
            preserving: quarantine,
            perform: perform
        )
        _ = try resumeInterruptedTransition(at: storeURL, perform: perform)
    }

    static func beginPreservedFamilyRestore(
        from quarantine: Quarantine,
        to storeURL: URL,
        perform: RecoveryOperationRunner = { _, operation in try operation() }
    ) throws {
        let fileManager = FileManager.default
        try validateQuarantine(
            quarantine,
            storeFileName: storeURL.lastPathComponent,
            fileManager: fileManager
        )

        try publishTransition(
            phase: .restoringPreservedFamily,
            quarantine: quarantine,
            storeURL: storeURL,
            fileManager: fileManager,
            perform: perform
        )
    }

    static func beginFreshStorePreparation(
        at storeURL: URL,
        preserving quarantine: Quarantine,
        perform: RecoveryOperationRunner = { _, operation in try operation() }
    ) throws {
        let fileManager = FileManager.default
        try validateQuarantine(
            quarantine,
            storeFileName: storeURL.lastPathComponent,
            fileManager: fileManager
        )
        try publishTransition(
            phase: .preparingFreshStore,
            quarantine: quarantine,
            storeURL: storeURL,
            fileManager: fileManager,
            perform: perform
        )
    }

    @discardableResult
    static func resumeInterruptedTransition(
        at storeURL: URL,
        perform: RecoveryOperationRunner = { _, operation in try operation() }
    ) throws -> Bool {
        let fileManager = FileManager.default
        let markerURL = transitionMarkerURL(for: storeURL)
        guard fileManager.fileExists(atPath: markerURL.path) else { return false }

        let marker = try JSONDecoder().decode(
            TransitionMarker.self,
            from: Data(contentsOf: markerURL)
        )
        guard marker.formatVersion == 1, marker.storeFileName == storeURL.lastPathComponent else {
            throw RecoveryError.invalidTransitionMarker(markerURL)
        }

        let quarantine = Quarantine(
            directoryURL: URL(fileURLWithPath: marker.quarantineDirectoryPath, isDirectory: true),
            preservedStoreURL: URL(fileURLWithPath: marker.quarantineDirectoryPath, isDirectory: true)
                .appendingPathComponent(preservedDirectoryName, isDirectory: true)
                .appendingPathComponent(storeURL.lastPathComponent, isDirectory: false)
        )
        try validateQuarantine(
            quarantine,
            storeFileName: storeURL.lastPathComponent,
            fileManager: fileManager
        )

        switch marker.phase {
        case .restoringPreservedFamily:
            try replaceActiveFamily(
                with: quarantine.preservedStoreURL,
                at: storeURL,
                fileManager: fileManager,
                perform: perform
            )

        case .preparingFreshStore:
            try removeActiveFamily(
                at: storeURL,
                fileManager: fileManager,
                phase: marker.phase,
                perform: perform
            )
        }

        try perform(.removeTransitionMarker(marker.phase)) {
            try fileManager.removeItem(at: markerURL)
        }
        try perform(.synchronizeTransitionCompletionDirectory(marker.phase)) {
            try SumiStartupStoreIO.synchronizeDirectory(
                at: storeURL.deletingLastPathComponent()
            )
        }
        return true
    }

    private static func replaceActiveFamily(
        with preservedStoreURL: URL,
        at storeURL: URL,
        fileManager: FileManager,
        perform: RecoveryOperationRunner
    ) throws {
        guard fileManager.fileExists(atPath: preservedStoreURL.path) else {
            throw RecoveryError.missingPrimaryStore(preservedStoreURL)
        }

        try removeActiveFamily(
            at: storeURL,
            fileManager: fileManager,
            phase: .restoringPreservedFamily,
            perform: perform
        )
        for suffix in familySuffixes {
            let sourceURL = familyURL(base: preservedStoreURL, suffix: suffix)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }

            let destinationURL = familyURL(base: storeURL, suffix: suffix)
            try perform(.copyRestoredFamilyFile(destinationURL.lastPathComponent)) {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
            try perform(.synchronizeRestoredFamilyFile(destinationURL.lastPathComponent)) {
                try SumiStartupStoreIO.synchronizeFile(at: destinationURL)
            }
        }
        try perform(.synchronizeRestoredDirectory) {
            try SumiStartupStoreIO.synchronizeDirectory(
                at: storeURL.deletingLastPathComponent()
            )
        }
    }

    private static func publishTransition(
        phase: TransitionMarker.Phase,
        quarantine: Quarantine,
        storeURL: URL,
        fileManager: FileManager,
        perform: RecoveryOperationRunner
    ) throws {
        let markerURL = transitionMarkerURL(for: storeURL)
        let stagingURL = markerURL.deletingLastPathComponent().appendingPathComponent(
            ".\(markerURL.lastPathComponent).staging-\(UUID().uuidString)",
            isDirectory: false
        )
        let marker = TransitionMarker(
            formatVersion: 1,
            phase: phase,
            storeFileName: storeURL.lastPathComponent,
            quarantineDirectoryPath: quarantine.directoryURL.path
        )

        defer { SumiStartupStoreIO.removeUnpublishedStagingArtifact(at: stagingURL) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try perform(.writeTransitionMarker(phase)) {
            try encoder.encode(marker).write(to: stagingURL, options: .withoutOverwriting)
        }
        try perform(.synchronizeTransitionMarker(phase)) {
            try SumiStartupStoreIO.synchronizeFile(at: stagingURL)
        }
        try perform(.publishTransitionMarker(phase)) {
            try SumiStartupStoreIO.atomicRename(from: stagingURL, to: markerURL)
        }
        try perform(.synchronizeTransitionParent(phase)) {
            try SumiStartupStoreIO.synchronizeDirectory(
                at: markerURL.deletingLastPathComponent()
            )
        }
    }

    private static func validateQuarantine(
        _ quarantine: Quarantine,
        storeFileName: String,
        fileManager: FileManager
    ) throws {
        let canonicalPreservedStoreURL = quarantine.directoryURL
            .appendingPathComponent(preservedDirectoryName, isDirectory: true)
            .appendingPathComponent(storeFileName, isDirectory: false)
            .standardizedFileURL
        guard quarantine.preservedStoreURL.standardizedFileURL == canonicalPreservedStoreURL else {
            throw RecoveryError.invalidQuarantine(quarantine.directoryURL)
        }

        let manifestURL = quarantine.directoryURL.appendingPathComponent(
            manifestFileName,
            isDirectory: false
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            Manifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let validFileNames = Set(familySuffixes.map { storeFileName + $0 })
        let manifestFileNames = manifest.files.map(\.name)
        guard manifest.formatVersion == 2,
              manifest.storeFileName == storeFileName,
              manifestFileNames.contains(storeFileName),
              Set(manifestFileNames).count == manifestFileNames.count,
              manifestFileNames.allSatisfy(validFileNames.contains)
        else {
            throw RecoveryError.invalidQuarantine(quarantine.directoryURL)
        }

        try validatePreservedFiles(
            manifest.files,
            in: quarantine.preservedStoreURL.deletingLastPathComponent(),
            quarantineURL: quarantine.directoryURL,
            fileManager: fileManager
        )
    }

    static func validatePreservedFiles(
        _ records: [Manifest.FileRecord],
        in preservedDirectoryURL: URL,
        quarantineURL: URL,
        fileManager: FileManager
    ) throws {
        for record in records {
            let fileURL = preservedDirectoryURL.appendingPathComponent(
                record.name,
                isDirectory: false
            )
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            guard (attributes[.size] as? NSNumber)?.int64Value == record.byteCount,
                  try SumiStartupStoreIO.sha256Digest(at: fileURL) == record.sha256
            else {
                throw RecoveryError.invalidQuarantine(quarantineURL)
            }
        }
    }

    private static func removeActiveFamily(
        at storeURL: URL,
        fileManager: FileManager,
        phase: TransitionMarker.Phase,
        perform: RecoveryOperationRunner
    ) throws {
        for suffix in familySuffixes.reversed() {
            let fileURL = familyURL(base: storeURL, suffix: suffix)
            guard fileManager.fileExists(atPath: fileURL.path) else { continue }
            try perform(.removeActiveFamilyFile(phase, fileURL.lastPathComponent)) {
                try fileManager.removeItem(at: fileURL)
            }
        }
        try perform(.synchronizeActiveDirectoryAfterRemoval(phase)) {
            try SumiStartupStoreIO.synchronizeDirectory(
                at: storeURL.deletingLastPathComponent()
            )
        }
    }

    static func familyURL(base: URL, suffix: String) -> URL {
        guard !suffix.isEmpty else { return base }
        return URL(fileURLWithPath: base.path + suffix, isDirectory: false)
    }

    private static func transitionMarkerURL(for storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appendingPathComponent(
            transitionMarkerFileName,
            isDirectory: false
        )
    }
}
