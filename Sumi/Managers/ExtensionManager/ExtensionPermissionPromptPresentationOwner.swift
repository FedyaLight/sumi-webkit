import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionPermissionPromptPresentationOwner {
    private typealias PromptDecision = ExtensionManager.ExtensionPermissionPromptDecision
    private typealias PromptDecisionOperation = @MainActor () -> PromptDecision
    private typealias PromptQueueOperation = @MainActor () -> Void

    private var promptQueue: [PromptQueueOperation] = []
    private var isPresentingPrompt = false
    private var promptWaitersByKey:
        [String: [CheckedContinuation<PromptDecision, Never>]] = [:]

    func promptForDecision(
        extensionContext: WKWebExtensionContext,
        targets: [String],
        reason: String,
        dedupeKey: String,
        extensionIdentifier: String?
    ) async -> ExtensionManager.ExtensionPermissionPromptDecision {
        await enqueuePrompt(key: dedupeKey) {
            Self.presentPrompt(
                extensionContext: extensionContext,
                targets: targets,
                reason: reason,
                extensionIdentifier: extensionIdentifier
            )
        }
    }

    private func enqueuePrompt(
        key: String,
        _ operation: @escaping PromptDecisionOperation
    ) async -> PromptDecision {
        await withCheckedContinuation { continuation in
            if promptWaitersByKey[key] != nil {
                promptWaitersByKey[key]?.append(continuation)
                return
            }
            promptWaitersByKey[key] = [continuation]
            promptQueue.append {
                let decision = operation()
                let waiters = self.promptWaitersByKey.removeValue(forKey: key) ?? []
                for waiter in waiters {
                    waiter.resume(returning: decision)
                }
            }
            drainPromptQueueIfNeeded()
        }
    }

    private func drainPromptQueueIfNeeded() {
        guard isPresentingPrompt == false else { return }
        guard promptQueue.isEmpty == false else { return }

        isPresentingPrompt = true
        let operation = promptQueue.removeFirst()
        Task { @MainActor in
            operation()
            self.isPresentingPrompt = false
            self.drainPromptQueueIfNeeded()
        }
    }

    private static func presentPrompt(
        extensionContext: WKWebExtensionContext,
        targets: [String],
        reason: String,
        extensionIdentifier: String?
    ) -> PromptDecision {
        let summarizedTargets = summarizedPermissionTargets(targets)
        let targetSummary = summarizedTargets.joined(separator: ", ")
        let extensionName = extensionDisplayName(for: extensionContext)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText =
            "Extension \"\(extensionName)\" requests permission to access \(targetSummary)."
        alert.informativeText =
            "This extension can read and alter webpages on the requested site."
        alert.addButton(withTitle: "Allow for 1 Day")
        alert.addButton(withTitle: "Always Allow")
        alert.addButton(withTitle: "Deny")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        let decision: PromptDecision
        switch response {
        case .alertFirstButtonReturn:
            decision = .allow(expirationDate: Date(timeIntervalSinceNow: 24 * 60 * 60))
        case .alertSecondButtonReturn:
            decision = .allow(expirationDate: nil)
        default:
            decision = .deny
        }

        RuntimeDiagnostics.debug(category: "SafariExtensionPermissions") {
            let granted: Bool
            let expiration: String
            switch decision {
            case .allow(let expirationDate):
                granted = true
                expiration = expirationDate == nil ? "never" : "temporary"
            case .deny:
                granted = false
                expiration = "nil"
            }
            return """
            prompt result reason=\(reason) ext=\(extensionIdentifier ?? "unknown") \
            targetCount=\(targets.count) granted=\(granted) expiration=\(expiration)
            """
        }

        return decision
    }

    private static func extensionDisplayName(
        for extensionContext: WKWebExtensionContext
    ) -> String {
        extensionContext.webExtension.displayName
            ?? extensionContext.webExtension.displayShortName
            ?? "This extension"
    }

    private nonisolated static func summarizedPermissionTargets(
        _ targets: [String]
    ) -> [String] {
        let uniqueTargets = Array(Set(targets)).sorted()
        guard uniqueTargets.count > 4 else { return uniqueTargets }
        return Array(uniqueTargets.prefix(4)) + ["and \(uniqueTargets.count - 4) more"]
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func promptForExtensionPermissionDecision(
        extensionContext: WKWebExtensionContext,
        targets: [String],
        reason: String,
        dedupeKey: String? = nil
    ) async -> ExtensionPermissionPromptDecision {
        #if DEBUG
            if let permissionPromptDecision = testHooks.permissionPromptDecision {
                return permissionPromptDecision(extensionContext, targets, reason)
            }
        #endif

        return await extensionPermissionPromptPresentationOwner.promptForDecision(
            extensionContext: extensionContext,
            targets: targets,
            reason: reason,
            dedupeKey: dedupeKey ?? permissionPromptDedupeKey(
                extensionContext: extensionContext,
                targets: targets
            ),
            extensionIdentifier: extensionID(for: extensionContext)
        )
    }
}
