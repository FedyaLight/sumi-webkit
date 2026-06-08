//
//  ChromeMV3WKScriptMessageHandlerRegistration.swift
//  Sumi
//
//  Idempotent MV3 WKScriptMessageHandler registration for popup/content-script
//  bridge handlers. Prevents duplicate-name crashes on the same
//  WKUserContentController.
//

import Foundation
import WebKit

enum ChromeMV3WKScriptMessageHandlerRegistrationCategory:
    String,
    Codable,
    Equatable,
    Sendable
{
    case contentScriptBridge
    case popupOptionsBridge
}

enum ChromeMV3WKScriptMessageHandlerRegistrationOutcome:
    String,
    Codable,
    Equatable,
    Sendable
{
    case added
    case alreadyRegistered
    case replaced
    case removed
    case skipped
}

#if DEBUG
struct ChromeMV3WKScriptMessageHandlerRegistrationDiagnostic:
    Codable,
    Equatable,
    Sendable
{
    var handlerNameCategory: String
    var userContentControllerIdentityHash: String
    var webViewConfigurationIdentityHash: String?
    var extensionIDHash: String?
    var registrationCategory: ChromeMV3WKScriptMessageHandlerRegistrationCategory
    var sourcePath: String
    var outcome: ChromeMV3WKScriptMessageHandlerRegistrationOutcome
}
#endif

@MainActor
enum ChromeMV3WKScriptMessageHandlerRegistration {
    private struct Record {
        weak var handlerObject: AnyObject?
        let handlerObjectID: ObjectIdentifier
        let category: ChromeMV3WKScriptMessageHandlerRegistrationCategory
        let extensionIDHash: String?
        let sourcePath: String
    }

    private struct Key: Hashable {
        let controllerID: ObjectIdentifier
        let handlerNameCategory: String
        let contentWorldName: String
    }

    private static var records: [Key: Record] = [:]

    #if DEBUG
    private static var diagnostics: [ChromeMV3WKScriptMessageHandlerRegistrationDiagnostic] = []
    private static let maxDiagnostics = 256
    #endif

    static func register(
        handler: some WKScriptMessageHandler & NSObject,
        name: String,
        contentWorld: WKContentWorld,
        userContentController: WKUserContentController,
        category: ChromeMV3WKScriptMessageHandlerRegistrationCategory,
        extensionIDHash: String?,
        sourcePath: String,
        webViewConfiguration: WKWebViewConfiguration? = nil
    ) -> ChromeMV3WKScriptMessageHandlerRegistrationOutcome {
        register(
            handlerObject: handler,
            name: name,
            contentWorld: contentWorld,
            userContentController: userContentController,
            category: category,
            extensionIDHash: extensionIDHash,
            sourcePath: sourcePath,
            webViewConfiguration: webViewConfiguration,
            install: { controller, world, handlerName in
                controller.add(
                    handler,
                    contentWorld: world,
                    name: handlerName
                )
            }
        )
    }

    static func register(
        handler: some WKScriptMessageHandlerWithReply & NSObject,
        name: String,
        contentWorld: WKContentWorld,
        userContentController: WKUserContentController,
        category: ChromeMV3WKScriptMessageHandlerRegistrationCategory,
        extensionIDHash: String?,
        sourcePath: String,
        webViewConfiguration: WKWebViewConfiguration? = nil
    ) -> ChromeMV3WKScriptMessageHandlerRegistrationOutcome {
        register(
            handlerObject: handler,
            name: name,
            contentWorld: contentWorld,
            userContentController: userContentController,
            category: category,
            extensionIDHash: extensionIDHash,
            sourcePath: sourcePath,
            webViewConfiguration: webViewConfiguration,
            install: { controller, world, handlerName in
                controller.addScriptMessageHandler(
                    handler,
                    contentWorld: world,
                    name: handlerName
                )
            }
        )
    }

    private static func register(
        handlerObject: AnyObject,
        name: String,
        contentWorld: WKContentWorld,
        userContentController: WKUserContentController,
        category: ChromeMV3WKScriptMessageHandlerRegistrationCategory,
        extensionIDHash: String?,
        sourcePath: String,
        webViewConfiguration: WKWebViewConfiguration?,
        install: (
            WKUserContentController,
            WKContentWorld,
            String
        ) -> Void
    ) -> ChromeMV3WKScriptMessageHandlerRegistrationOutcome {
        let key = makeKey(
            userContentController: userContentController,
            handlerName: name,
            contentWorld: contentWorld
        )
        let handlerID = ObjectIdentifier(handlerObject)
        if let existing = records[key],
           existing.handlerObjectID == handlerID,
           existing.handlerObject != nil
        {
            recordDiagnostic(
                handlerName: name,
                userContentController: userContentController,
                webViewConfiguration: webViewConfiguration,
                extensionIDHash: extensionIDHash,
                category: category,
                sourcePath: sourcePath,
                outcome: .alreadyRegistered
            )
            return .alreadyRegistered
        }

        let outcome: ChromeMV3WKScriptMessageHandlerRegistrationOutcome
        if records[key] != nil {
            removeRegisteredHandler(
                name: name,
                contentWorld: contentWorld,
                userContentController: userContentController,
                category: category,
                extensionIDHash: extensionIDHash,
                sourcePath: "\(sourcePath).replace",
                webViewConfiguration: webViewConfiguration,
                emitDiagnostic: false
            )
            outcome = .replaced
        } else {
            outcome = .added
        }

        userContentController.removeScriptMessageHandler(
            forName: name,
            contentWorld: contentWorld
        )
        install(userContentController, contentWorld, name)
        records[key] = Record(
            handlerObject: handlerObject,
            handlerObjectID: handlerID,
            category: category,
            extensionIDHash: extensionIDHash,
            sourcePath: sourcePath
        )
        recordDiagnostic(
            handlerName: name,
            userContentController: userContentController,
            webViewConfiguration: webViewConfiguration,
            extensionIDHash: extensionIDHash,
            category: category,
            sourcePath: sourcePath,
            outcome: outcome
        )
        return outcome
    }

    @discardableResult
    static func remove(
        name: String,
        contentWorld: WKContentWorld,
        userContentController: WKUserContentController,
        category: ChromeMV3WKScriptMessageHandlerRegistrationCategory,
        extensionIDHash: String?,
        sourcePath: String,
        webViewConfiguration: WKWebViewConfiguration? = nil
    ) -> ChromeMV3WKScriptMessageHandlerRegistrationOutcome {
        removeRegisteredHandler(
            name: name,
            contentWorld: contentWorld,
            userContentController: userContentController,
            category: category,
            extensionIDHash: extensionIDHash,
            sourcePath: sourcePath,
            webViewConfiguration: webViewConfiguration,
            emitDiagnostic: true
        )
    }

    #if DEBUG
    static var diagnosticsSnapshot:
        [ChromeMV3WKScriptMessageHandlerRegistrationDiagnostic]
    {
        diagnostics
    }

    static func resetDiagnosticsForTesting() {
        diagnostics.removeAll(keepingCapacity: true)
    }
    #endif

    private static func removeRegisteredHandler(
        name: String,
        contentWorld: WKContentWorld,
        userContentController: WKUserContentController,
        category: ChromeMV3WKScriptMessageHandlerRegistrationCategory,
        extensionIDHash: String?,
        sourcePath: String,
        webViewConfiguration: WKWebViewConfiguration?,
        emitDiagnostic: Bool
    ) -> ChromeMV3WKScriptMessageHandlerRegistrationOutcome {
        let key = makeKey(
            userContentController: userContentController,
            handlerName: name,
            contentWorld: contentWorld
        )
        let hadRecord = records[key] != nil
        records.removeValue(forKey: key)
        userContentController.removeScriptMessageHandler(
            forName: name,
            contentWorld: contentWorld
        )
        let outcome: ChromeMV3WKScriptMessageHandlerRegistrationOutcome =
            hadRecord ? .removed : .skipped
        if emitDiagnostic {
            recordDiagnostic(
                handlerName: name,
                userContentController: userContentController,
                webViewConfiguration: webViewConfiguration,
                extensionIDHash: extensionIDHash,
                category: category,
                sourcePath: sourcePath,
                outcome: outcome
            )
        }
        return outcome
    }

    private static func makeKey(
        userContentController: WKUserContentController,
        handlerName: String,
        contentWorld: WKContentWorld
    ) -> Key {
        Key(
            controllerID: ObjectIdentifier(userContentController),
            handlerNameCategory: handlerNameCategory(handlerName),
            contentWorldName: contentWorld.name ?? "page"
        )
    }

    private static func handlerNameCategory(_ handlerName: String) -> String {
        if handlerName.hasPrefix("sumiChromeMV3ContentScript_") {
            return "sumiChromeMV3ContentScript"
        }
        if handlerName == ChromeMV3PopupOptionsJSShimSource.bridgeMessageHandlerName {
            return "sumiChromeMV3PopupOptions"
        }
        return ChromeMV3CompatibilityPolicyLog.hashID(
            handlerName,
            fallback: "mv3Handler"
        )
    }

    private static func identityHash(_ object: AnyObject) -> String {
        "oid-\(String(ObjectIdentifier(object).hashValue.magnitude, radix: 16, uppercase: false))"
    }

    #if DEBUG
    private static func recordDiagnostic(
        handlerName: String,
        userContentController: WKUserContentController,
        webViewConfiguration: WKWebViewConfiguration?,
        extensionIDHash: String?,
        category: ChromeMV3WKScriptMessageHandlerRegistrationCategory,
        sourcePath: String,
        outcome: ChromeMV3WKScriptMessageHandlerRegistrationOutcome
    ) {
        let diagnostic = ChromeMV3WKScriptMessageHandlerRegistrationDiagnostic(
            handlerNameCategory: handlerNameCategory(handlerName),
            userContentControllerIdentityHash: identityHash(userContentController),
            webViewConfigurationIdentityHash: webViewConfiguration.map(identityHash),
            extensionIDHash: extensionIDHash,
            registrationCategory: category,
            sourcePath: sourcePath,
            outcome: outcome
        )
        diagnostics.append(diagnostic)
        if diagnostics.count > maxDiagnostics {
            diagnostics.removeFirst(diagnostics.count - maxDiagnostics)
        }
    }
    #endif
}
