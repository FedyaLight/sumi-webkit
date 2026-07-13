import Foundation

enum ExtensionContentScriptBindingPolicy {
    static func needsRebind(
        documentBinding: TabExtensionDocumentBindingSnapshot,
        currentContextBindingGeneration: UInt64?,
        controllerNeedsRuntimeRebuild: Bool
    ) -> Bool {
        let documentSequence = documentBinding.documentSequence
        guard documentSequence > 0 else { return false }
        guard let committedURL = documentBinding.committedMainDocumentURL,
              isInjectableCommittedURL(committedURL)
        else {
            return false
        }

        if documentBinding.openNotifiedContextReadiness == .missing {
            return true
        }

        if let openBindingGeneration = documentBinding.openNotifiedContextBindingGeneration,
           let currentContextBindingGeneration,
           openBindingGeneration != currentContextBindingGeneration {
            return true
        }

        if controllerNeedsRuntimeRebuild {
            return true
        }

        guard let openNotifiedDocumentSequence = documentBinding.openNotifiedDocumentSequence else {
            return true
        }

        return openNotifiedDocumentSequence != documentSequence - 1
    }

    static func isInjectableCommittedURL(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "http", "https", "file":
            return true
        default:
            return false
        }
    }
}
