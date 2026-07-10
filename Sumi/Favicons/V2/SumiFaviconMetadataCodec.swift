import Foundation

struct SumiFaviconMetadataCodec {
    enum DecodingError: Error, Equatable {
        case unsupportedSchemaVersion(Int)
    }

    func decode(_ data: Data) throws -> SumiFaviconBlobMetadata {
        let metadata = try decoder.decode(SumiFaviconBlobMetadata.self, from: data)
        guard metadata.schemaVersion == SumiFaviconBlobMetadata.currentSchemaVersion else {
            throw DecodingError.unsupportedSchemaVersion(metadata.schemaVersion)
        }
        return metadata
    }

    func encode(_ metadata: SumiFaviconBlobMetadata) throws -> Data {
        try encoder.encode(metadata)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
