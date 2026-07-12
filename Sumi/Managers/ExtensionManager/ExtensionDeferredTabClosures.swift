import Foundation

/// Retains exact close receipts whose physical Tab has already left runtime
/// collections. Receipt identity prevents a same-UUID replacement from being
/// mistaken for the removed adapter.
@available(macOS 15.5, *)
@MainActor
final class ExtensionDeferredTabClosures {
    private var identities: Set<ExtensionNormalTabCloseReceipt.Identity> = []
    private var receipts: [ExtensionNormalTabCloseReceipt] = []

    func deferClose(_ receipt: ExtensionNormalTabCloseReceipt) {
        guard identities.insert(receipt.identity).inserted else { return }
        receipts.append(receipt)
    }

    func takeAll() -> [ExtensionNormalTabCloseReceipt] {
        let deferred = receipts
        receipts.removeAll(keepingCapacity: false)
        identities.removeAll(keepingCapacity: false)
        return deferred
    }
}
