import AppKit
import Foundation

// NSCache is internally synchronized; the sidecar identity index is isolated to `queue`.
final class SumiPreparedFaviconCache: @unchecked Sendable {
    private static let countLimit = 512

    private struct EntryIdentity: Hashable {
        let partition: SumiFaviconPartition
        let blobID: String
        let revision: String
        let key: NSString
    }

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "SumiPreparedFaviconCache")
    private var identitiesByKey: [String: EntryIdentity] = [:]
    private var identityKeysByInsertionOrder: [String] = []

    init(totalCostLimit: Int = SumiFaviconConstants.preparedMemoryBudgetBytes) {
        cache.countLimit = Self.countLimit
        cache.totalCostLimit = totalCostLimit
    }

    func image(for identity: SumiPreparedFaviconIdentity) -> NSImage? {
        cache.object(forKey: keyString(for: identity) as NSString)
    }

    func setImage(_ image: NSImage, for identity: SumiPreparedFaviconIdentity) {
        let key = keyString(for: identity)
        let nsKey = key as NSString
        let cost = max(1, image.sumiPreparedFaviconByteCost)
        queue.sync {
            if identitiesByKey[key] != nil {
                identityKeysByInsertionOrder.removeAll { $0 == key }
            }
            identitiesByKey[key] = EntryIdentity(
                partition: identity.partition,
                blobID: identity.blobID,
                revision: identity.revision,
                key: nsKey
            )
            identityKeysByInsertionOrder.append(key)
            trimToCountLimitLocked()
            cache.setObject(image, forKey: nsKey, cost: cost)
        }
    }

    func invalidate(
        partition: SumiFaviconPartition? = nil,
        blobID: String? = nil,
        revision: String? = nil
    ) {
        guard partition != nil || blobID != nil || revision != nil else {
            queue.sync {
                cache.removeAllObjects()
                identitiesByKey.removeAll(keepingCapacity: false)
                identityKeysByInsertionOrder.removeAll(keepingCapacity: false)
            }
            return
        }

        queue.sync {
            let entriesToRemove = identitiesByKey.values.filter { identity in
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
            guard !entriesToRemove.isEmpty else { return }

            let keysToRemove = Set(entriesToRemove.map { $0.key as String })
            for entry in entriesToRemove {
                cache.removeObject(forKey: entry.key)
                identitiesByKey[entry.key as String] = nil
            }
            identityKeysByInsertionOrder.removeAll { keysToRemove.contains($0) }
        }
    }

    private func trimToCountLimitLocked() {
        let overflowCount = identityKeysByInsertionOrder.count - Self.countLimit
        guard overflowCount > 0 else { return }

        let keysToRemove = Array(identityKeysByInsertionOrder.prefix(overflowCount))
        identityKeysByInsertionOrder.removeFirst(overflowCount)
        for key in keysToRemove {
            guard let entry = identitiesByKey.removeValue(forKey: key) else {
                continue
            }
            cache.removeObject(forKey: entry.key)
        }
    }

    private func keyString(for identity: SumiPreparedFaviconIdentity) -> String {
        let pointSize = Int(identity.request.pointSize.rounded(.up))
        let backingScale = Int(identity.request.backingScale.rounded(.up))
        let cornerRadius = Int(identity.request.cornerRadius.rounded(.up))
        var key = identity.partition.storageComponent
        key += "|\(identity.blobID)"
        key += "|\(identity.revision)"
        key += "|\(identity.sourceURL.absoluteString.lowercased())"
        key += "|\(identity.request.context.rawValue)"
        key += "|\(pointSize)"
        key += "|\(backingScale)"
        key += "|\(identity.request.pixelSize)"
        key += "|\(cornerRadius)"
        key += "|\(identity.request.templateMode)"
        key += "|\(identity.request.appearanceName ?? "any")"
        return key
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
