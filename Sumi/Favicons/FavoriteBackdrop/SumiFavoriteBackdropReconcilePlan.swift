import CryptoKit
import Foundation

struct SumiFavoriteBackdropKey: Hashable, Sendable {
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
enum SumiFavoriteBackdropReconcilePlan {
    struct Result: Equatable {
        let toBake: Set<SumiFavoriteBackdropKey>
        let toDelete: Set<SumiFavoriteBackdropKey.StoredKey>
    }

    static func entries(
        for pins: [ShortcutPin]
    ) -> [SumiFavoriteBackdropKey: URL] {
        pins.reduce(into: [:]) { result, pin in
            guard pin.role == .favorite,
                  pin.iconAsset == nil,
                  pin.glyphText == nil,
                  pin.chromeTemplateSystemImageName == nil,
                  let key = SumiFavoriteBackdropKey(
                    documentURL: pin.launchURL,
                    partition: .regular()
                  )
            else { return }
            if result[key] == nil {
                result[key] = pin.launchURL
            }
        }
    }

    static func compute(
        current: Set<SumiFavoriteBackdropKey>,
        existing: Set<SumiFavoriteBackdropKey.StoredKey>
    ) -> Result {
        let currentStored = Set(current.map(\.storedKey))
        return Result(
            toBake: current.filter { !existing.contains($0.storedKey) },
            toDelete: existing.subtracting(currentStored)
        )
    }
}
