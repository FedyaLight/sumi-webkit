import Foundation
import OSLog

/// Owns the on-disk staging area for bulk import payloads.
///
/// Payloads are written as newline-delimited JSON and streamed in both
/// directions, so a hundred thousand history visits never exist as an array in
/// memory. Staging lives under Application Support rather than the system
/// temporary directory for two reasons: the OS reaps temporary directories
/// while a long import is still running, and recovery on the next launch has to
/// be able to find and delete whatever a crashed import left behind.
struct SumiImportBulkStagingStore {
    private static let log = Logger.sumi(category: "ImportStaging")
    private static let manifestFileName = "manifest.json"

    var rootDirectory: URL

    init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? Self.defaultRootDirectory()
    }

    static func defaultRootDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent(SumiAppIdentity.runtimeBundleIdentifier, isDirectory: true)
            .appendingPathComponent("ImportStaging", isDirectory: true)
    }

    func directory(for stagingID: UUID) -> URL {
        rootDirectory.appendingPathComponent(stagingID.uuidString, isDirectory: true)
    }

    func makeStagingDirectory(for stagingID: UUID) throws -> URL {
        let url = directory(for: stagingID)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Records

    /// Appends `records` as NDJSON, one JSON object per line.
    @discardableResult
    func write<Record: Encodable>(
        _ records: some Sequence<Record>,
        to fileURL: URL
    ) throws -> (count: Int, bytes: Int) {
        try writeStream(to: fileURL) { emit in
            for record in records {
                try emit(record)
            }
        }
    }

    /// Writes records as they are produced, keeping the source query and the
    /// NDJSON encoder streaming end-to-end.
    @discardableResult
    func writeStream<Record: Encodable>(
        to fileURL: URL,
        produce: ((_ record: Record) throws -> Void) throws -> Void
    ) throws -> (count: Int, bytes: Int) {
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: fileURL.path) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? handle.close() }

        let encoder = JSONEncoder()
        var count = 0
        var bytes = 0
        var buffer = Data()
        try produce { record in
            var line = try encoder.encode(record)
            line.append(0x0A)
            buffer.append(line)
            count += 1
            bytes += line.count
            // Flushed in blocks so a large export does not accumulate in memory
            // and a crash leaves a prefix of whole lines rather than a shard.
            if buffer.count >= 512 * 1024 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if buffer.isEmpty == false {
            try handle.write(contentsOf: buffer)
        }
        return (count, bytes)
    }

    /// Streams `fileURL` as chunks of decoded records, produced on a background
    /// task so a hundred-thousand-line file never decodes on the main thread.
    ///
    /// The consumer is asynchronous — it writes to SQLite and WebKit — so a
    /// stream is the right shape here: a synchronous callback would have to
    /// block a thread waiting on the installer, and blocking the main actor
    /// while awaiting main-actor work deadlocks.
    func chunkStream<Record: Decodable & Sendable>(
        _ type: Record.Type,
        from fileURL: URL,
        chunkSize: Int = 500
    ) -> AsyncThrowingStream<[Record], Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    try read(type, from: fileURL, chunkSize: chunkSize) { chunk in
                        try Task.checkCancellation()
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streams `fileURL`, handing each decoded record to `body`. A malformed
    /// line is skipped rather than failing the file: a truncated staging file
    /// should cost its last record, not the whole import.
    func read<Record: Decodable>(
        _ type: Record.Type,
        from fileURL: URL,
        chunkSize: Int = 500,
        chunk: ([Record]) throws -> Void
    ) throws {
        guard let handle = FileHandle(forReadingAtPath: fileURL.path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        defer { try? handle.close() }

        let decoder = JSONDecoder()
        var pending = Data()
        var batch: [Record] = []
        batch.reserveCapacity(chunkSize)

        func consume(line: Data) {
            guard line.isEmpty == false else { return }
            guard let record = try? decoder.decode(Record.self, from: line) else {
                Self.log.error("Skipped an unreadable staged record in \(fileURL.lastPathComponent, privacy: .public)")
                return
            }
            batch.append(record)
        }

        while let block = try handle.read(upToCount: 1024 * 1024), block.isEmpty == false {
            pending.append(block)
            var lineStart = pending.startIndex
            while let newline = pending[lineStart...].firstIndex(of: 0x0A) {
                consume(line: pending[lineStart..<newline])
                lineStart = pending.index(after: newline)
                if batch.count >= chunkSize {
                    try chunk(batch)
                    batch.removeAll(keepingCapacity: true)
                }
            }
            if lineStart != pending.startIndex {
                pending.removeSubrange(pending.startIndex..<lineStart)
            }
        }
        consume(line: pending)
        if batch.isEmpty == false {
            try chunk(batch)
        }
    }

    // MARK: - Manifest

    func writeManifest(_ manifest: SumiImportBulkStagingManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(
            to: directory(for: manifest.stagingID).appendingPathComponent(Self.manifestFileName),
            options: .atomic
        )
    }

    func loadManifest(for stagingID: UUID) throws -> SumiImportBulkStagingManifest {
        let url = directory(for: stagingID).appendingPathComponent(Self.manifestFileName)
        let manifest = try JSONDecoder().decode(
            SumiImportBulkStagingManifest.self,
            from: Data(contentsOf: url)
        )
        guard manifest.version == SumiImportBulkStagingManifest.currentVersion else {
            throw SumiImportExportError.unsupportedFile(
                "Staged import data uses unsupported version \(manifest.version)."
            )
        }
        return manifest
    }

    /// Verifies every selected payload before the structural transaction
    /// commits. This keeps missing or abandoned staging files from turning a
    /// deterministic preview error into a partial import.
    func validate(
        _ manifest: SumiImportBulkStagingManifest,
        kinds: Set<SumiImportBulkKind>
    ) throws {
        guard try loadManifest(for: manifest.stagingID) == manifest else {
            throw SumiImportExportError.importFailed(
                "Staged browsing data no longer matches its import preview."
            )
        }
        let directory = directory(for: manifest.stagingID)
        for entry in manifest.entries where kinds.contains(entry.kind) {
            var isDirectory: ObjCBool = false
            let recordURL = directory.appendingPathComponent(entry.fileName)
            guard FileManager.default.fileExists(
                atPath: recordURL.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue == false else {
                throw SumiImportExportError.importFailed(
                    "Staged \(entry.kind.title.lowercased()) data is no longer available."
                )
            }
            if let blobDirectoryName = entry.blobDirectoryName {
                let blobURL = directory.appendingPathComponent(blobDirectoryName)
                guard FileManager.default.fileExists(
                    atPath: blobURL.path,
                    isDirectory: &isDirectory
                ), isDirectory.boolValue else {
                    throw SumiImportExportError.importFailed(
                        "Staged site icon data is no longer available."
                    )
                }
            }
        }
    }

    // MARK: - Lifetime

    func discard(_ stagingID: UUID) {
        try? FileManager.default.removeItem(at: directory(for: stagingID))
    }

    /// Deletes staging directories left behind by a crashed or abandoned
    /// import. `keeping` is whatever the journal still refers to.
    func sweepOrphans(keeping live: Set<UUID> = []) {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in children {
            guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
            guard live.contains(id) == false else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
