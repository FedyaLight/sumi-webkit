import CryptoKit
import Foundation

struct SumiEssentialBackdropKey: Hashable, Sendable {
    struct StoredKey: Hashable, Sendable {
        let partitionComponent: String
        let fileName: String
    }

    let referenceKey: String
    let partition: SumiFaviconPartition

    init?(documentURL: URL, partition: SumiFaviconPartition) {
        guard !partition.isPrivate,
              let referenceKey = SumiFaviconLookupKey.referenceKey(for: documentURL)
        else { return nil }
        self.referenceKey = referenceKey
        self.partition = partition
    }

    var storedKey: StoredKey {
        let digest = SHA256.hash(data: Data(referenceKey.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return StoredKey(
            partitionComponent: partition.storageComponent,
            fileName: "\(hex).png"
        )
    }

    var cacheIdentifier: NSString {
        "\(partition.storageComponent)|\(referenceKey)" as NSString
    }
}

@MainActor
enum SumiEssentialBackdropReconcilePlan {
    struct Result: Equatable {
        let toBake: Set<SumiEssentialBackdropKey>
        let toDelete: Set<SumiEssentialBackdropKey.StoredKey>
    }

    static func entries(
        for pins: [ShortcutPin]
    ) -> [SumiEssentialBackdropKey: URL] {
        pins.reduce(into: [:]) { result, pin in
            guard pin.role == .essential,
                  pin.iconAsset == nil,
                  pin.glyphText == nil,
                  pin.chromeTemplateSystemImageName == nil,
                  let key = SumiEssentialBackdropKey(
                    documentURL: pin.launchURL,
                    partition: .regular(
                        pin.executionProfileId ?? pin.profileId
                    )
                  )
            else { return }
            if result[key] == nil {
                result[key] = pin.launchURL
            }
        }
    }

    static func compute(
        current: Set<SumiEssentialBackdropKey>,
        existing: Set<SumiEssentialBackdropKey.StoredKey>
    ) -> Result {
        let currentStored = Set(current.map(\.storedKey))
        return Result(
            toBake: current.filter { !existing.contains($0.storedKey) },
            toDelete: existing.subtracting(currentStored)
        )
    }
}
