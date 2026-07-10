import Foundation

struct AdblockGenerationPaths: Sendable {
    let rootDirectory: URL

    var activeManifestURL: URL {
        rootDirectory.appendingPathComponent("active-generation.json")
    }

    var generatedRoot: URL {
        rootDirectory.appendingPathComponent("Generated", isDirectory: true)
    }

    var stagingRoot: URL {
        rootDirectory.appendingPathComponent("Staging", isDirectory: true)
    }

    func generationDirectory(_ generationId: String) throws -> URL {
        try Self.validatePathComponent(generationId, kind: "generation")
        return generatedRoot.appendingPathComponent(generationId, isDirectory: true)
    }

    func shardURL(
        generationId: String,
        shardId: String
    ) throws -> URL {
        try Self.validatePathComponent(shardId, kind: "shard")
        return try generationDirectory(generationId)
            .appendingPathComponent("\(shardId).json")
    }

    static func validatePathComponent(_ value: String, kind: String) throws {
        guard !value.isEmpty,
              value != ".",
              value != "..",
              !value.contains("/"),
              !value.contains("\\"),
              !value.contains("\0")
        else {
            throw AdblockUpdateDiagnostics(summary: "Invalid Adblock \(kind) identifier: \(value)")
        }
    }
}
