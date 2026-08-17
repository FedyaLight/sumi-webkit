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

    func advancedArtifactURL(
        generationId: String,
        relativePath: String
    ) throws -> URL {
        guard relativePath.isEmpty == false,
              relativePath.hasPrefix("/") == false,
              relativePath.contains("\\") == false,
              relativePath.contains("\0") == false,
              relativePath.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy({ $0.isEmpty == false && $0 != "." && $0 != ".." })
        else {
            throw AdblockUpdateDiagnostics(
                summary: "Invalid advanced-blocking artifact path: \(relativePath)"
            )
        }
        let generation = try generationDirectory(generationId)
            .standardizedFileURL
        let candidate = generation.appendingPathComponent(relativePath)
            .standardizedFileURL
        guard candidate.path.hasPrefix(generation.path + "/") else {
            throw AdblockUpdateDiagnostics(
                summary: "Advanced-blocking artifact escaped its generation: \(relativePath)"
            )
        }
        return candidate
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
