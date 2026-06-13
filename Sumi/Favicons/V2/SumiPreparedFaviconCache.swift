import AppKit
import Foundation

// NSCache is internally synchronized; the sidecar identity index is isolated to `queue`.
final class SumiPreparedFaviconCache: @unchecked Sendable {
    private struct EntryIdentity: Hashable {
        let partition: SumiFaviconPartition
        let blobID: String
        let revision: String
        let key: NSString
    }

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "SumiPreparedFaviconCache")
    private var identitiesByKey: [String: EntryIdentity] = [:]

    init(totalCostLimit: Int = SumiFaviconConstants.preparedMemoryBudgetBytes) {
        cache.countLimit = 512
        cache.totalCostLimit = totalCostLimit
    }

    func image(for identity: SumiPreparedFaviconIdentity) -> NSImage? {
        cache.object(forKey: keyString(for: identity) as NSString)
    }

    func setImage(_ image: NSImage, for identity: SumiPreparedFaviconIdentity) {
        let key = keyString(for: identity)
        let nsKey = key as NSString
        queue.sync {
            identitiesByKey[key] = EntryIdentity(
                partition: identity.partition,
                blobID: identity.blobID,
                revision: identity.revision,
                key: nsKey
            )
        }
        cache.setObject(
            image,
            forKey: nsKey,
            cost: max(1, image.sumiPreparedFaviconByteCost)
        )
    }

    func invalidate(
        partition: SumiFaviconPartition? = nil,
        blobID: String? = nil,
        revision: String? = nil
    ) {
        guard partition != nil || blobID != nil || revision != nil else {
            cache.removeAllObjects()
            queue.sync {
                identitiesByKey.removeAll(keepingCapacity: false)
            }
            return
        }

        let keysToRemove = queue.sync {
            identitiesByKey.values.filter { identity in
                if let partition, identity.partition != partition {
                    return false
                }
                if let blobID, identity.blobID != blobID {
                    return false
                }
                if let revision, identity.revision != revision {
                    return false
                }
                return true
            }
        }

        for entry in keysToRemove {
            cache.removeObject(forKey: entry.key)
        }

        queue.sync {
            for entry in keysToRemove {
                identitiesByKey[entry.key as String] = nil
            }
        }
    }

    private func keyString(for identity: SumiPreparedFaviconIdentity) -> String {
        [
            identity.partition.storageComponent,
            identity.blobID,
            identity.revision,
            identity.sourceURL.absoluteString.lowercased(),
            identity.request.context.rawValue,
            "\(Int(identity.request.pointSize.rounded(.up)))",
            "\(Int(identity.request.backingScale.rounded(.up)))",
            "\(identity.request.pixelSize)",
            "\(Int(identity.request.cornerRadius.rounded(.up)))",
            "\(identity.request.templateMode)",
            identity.request.appearanceName ?? "any",
        ].joined(separator: "|")
    }
}

private extension NSImage {
    var sumiPreparedFaviconByteCost: Int {
        let representationCost = representations
            .map { max(1, $0.pixelsWide) * max(1, $0.pixelsHigh) * 4 }
            .max() ?? 0
        if representationCost > 0 {
            return representationCost
        }
        return max(1, Int(size.width * size.height * 4))
    }
}
