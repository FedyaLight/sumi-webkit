import Foundation

/// Retains exact close receipts whose physical Tab has already left runtime
/// collections. Receipt identity prevents a same-UUID replacement from being
/// mistaken for the removed adapter.
@available(macOS 15.5, *)
@MainActor
final class ExtensionDeferredTabClosures {
    private var receipts: [ExtensionNormalTabCloseReceipt] = []

    func deferClose(_ receipt: ExtensionNormalTabCloseReceipt) {
        receipts.append(receipt)
    }

    func takeAll() -> [ExtensionNormalTabCloseReceipt] {
        let deferred = receipts
        receipts.removeAll(keepingCapacity: false)
        return deferred
    }
}
