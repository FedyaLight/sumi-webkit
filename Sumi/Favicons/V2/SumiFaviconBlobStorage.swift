import Foundation

/// Composition root for the three storage capabilities. It intentionally has
/// no forwarding methods and owns no mutable storage state itself.
struct SumiFaviconBlobStorage: Sendable {
    let reader: SumiFaviconBlobReader
    let writer: SumiFaviconBlobWriter
    let maintenance: SumiFaviconBlobMaintenance

    init(
        database: SumiDatabase,
        rootDirectory: URL,
        fileManager: FileManager = .default,
        persistCoalesceInterval: TimeInterval = 0.75
    ) {
        let index = SumiFaviconBlobIndex()
        let transaction = SumiFaviconBlobTransaction(
            cache: SumiFaviconBlobCache(),
            database: database,
            diskStorage: SumiFaviconBlobDiskStorage(
                rootDirectory: rootDirectory,
                fileManager: fileManager
            ),
            codec: SumiFaviconMetadataCodec(),
            persistCoalesceInterval: persistCoalesceInterval
        )
        reader = SumiFaviconBlobReader(transaction: transaction, index: index)
        writer = SumiFaviconBlobWriter(transaction: transaction, index: index)
        maintenance = SumiFaviconBlobMaintenance(transaction: transaction, index: index)
    }
}
