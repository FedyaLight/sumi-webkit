//
//  ChromeMV3LivePopupProductPathTrace.swift
//  Sumi
//
//  DEBUG-only sanitized live popup product-path trace for URL-hub action clicks.
//

import Foundation

#if DEBUG

enum ChromeMV3LivePopupProductPathKind: String, Codable, Equatable, Sendable {
    case testHarnessDirectOpen
    case urlHubActionClick
    case nativeWebKitFallback
    case developerPreviewManagerAction
}

enum ChromeMV3LivePopupFailureClassifier: String, Codable, Equatable, Sendable {
    case controlledPopupNotSelected
    case popupHostNotPresented
    case popupHostDismissedImmediately
    case popupWebViewDeallocated
    case popupWebViewDetached
    case popupURLNotLoaded
    case generatedRootResourceHandlerMissing
    case requiredResourceLoadFailure
    case bridgeNotInstalled
    case popupScriptsNotExecuted
    case popupDOMNeverVisible
    case popupDOMVisibleThenBlank
    case popupViewReplacedBySumiUI
    case runtimeGateMismatch
    case debugFlagForcesWrongPath
    case selectedTabBindingMissing
    case productPathDiffersFromTestHarness
    case extensionLocalAppState
    case extensionLocalRenderState
    case nativeMessagingRequired
    case unknown
}

struct ChromeMV3LivePopupDOMCheckpoint: Codable, Equatable, Sendable {
    var visibleTextLengthBucket: String
    var controlCountBucket: String
    var bodyChildCount: Int
    var navigationCommitted: Bool
}

struct ChromeMV3LivePopupProductPathTrace: Codable, Equatable, Sendable {
    var productPath: ChromeMV3LivePopupProductPathKind
    var expectedPopupPath: String
    var actualPopupPath: String
    var extensionIDHash: String
    var profileIDHash: String
    var loadingMode: String
    var forceNativeActionPopup: Bool
    var forceControlledCompatibilityActionPopupOff: Bool
    var compatibilityPolicyState: String
    var compatibilityPolicyReason: String
    var selectedTabBound: Bool
    var anchorKind: String
    var anchorViewAvailable: Bool
    var anchorInWindow: Bool
    var popupHostCreated: Bool
    var popoverPresented: Bool
    var popoverShown: Bool
    var presentationAttempts: Int
    var presentationSkipReason: String?
    var webViewCreated: Bool
    var webViewAttachedToHost: Bool
    var webViewDeallocated: Bool
    var urlLoadCommitted: Bool
    var generatedRootHandlerActive: Bool
    var bridgeInstalled: Bool
    var scriptsExecuted: Bool
    var firstDOMCheckpoint: ChromeMV3LivePopupDOMCheckpoint?
    var finalDOMCheckpoint: ChromeMV3LivePopupDOMCheckpoint?
    var dismissReason: String?
    var nativeHostLaunched: Bool
    var resourceLoadBlockerCategory: String?
    var extensionClassifier: String?
    var failureClassifier: ChromeMV3LivePopupFailureClassifier
    var lifecycleEventCategories: [String]
    var diagnostics: [String]

    var compactSanitizedLogLines: [String] {
        [
            "path=\(productPath.rawValue)",
            "expectedPopupPath=\(expectedPopupPath)",
            "actualPopupPath=\(actualPopupPath)",
            "extensionIDHash=\(extensionIDHash)",
            "profileIDHash=\(profileIDHash)",
            "loadingMode=\(loadingMode)",
            "policy=\(compatibilityPolicyState)",
            "policyReason=\(compatibilityPolicyReason)",
            "forceNative=\(forceNativeActionPopup)",
            "forceControlledOff=\(forceControlledCompatibilityActionPopupOff)",
            "selectedTabBound=\(selectedTabBound)",
            "anchorKind=\(anchorKind)",
            "anchorView=\(anchorViewAvailable)",
            "anchorInWindow=\(anchorInWindow)",
            "hostCreated=\(popupHostCreated)",
            "popoverPresented=\(popoverPresented)",
            "popoverShown=\(popoverShown)",
            "presentationAttempts=\(presentationAttempts)",
            "presentationSkip=\(presentationSkipReason ?? "none")",
            "webViewCreated=\(webViewCreated)",
            "webViewAttached=\(webViewAttachedToHost)",
            "webViewDeallocated=\(webViewDeallocated)",
            "urlLoaded=\(urlLoadCommitted)",
            "generatedRootHandler=\(generatedRootHandlerActive)",
            "bridgeInstalled=\(bridgeInstalled)",
            "scriptsExecuted=\(scriptsExecuted)",
            "firstDOMTextBucket=\(firstDOMCheckpoint?.visibleTextLengthBucket ?? "none")",
            "firstDOMControlsBucket=\(firstDOMCheckpoint?.controlCountBucket ?? "none")",
            "finalDOMTextBucket=\(finalDOMCheckpoint?.visibleTextLengthBucket ?? "none")",
            "finalDOMControlsBucket=\(finalDOMCheckpoint?.controlCountBucket ?? "none")",
            "dismissReason=\(dismissReason ?? "none")",
            "nativeHostLaunched=\(nativeHostLaunched)",
            "resourceBlocker=\(resourceLoadBlockerCategory ?? "none")",
            "extensionClassifier=\(extensionClassifier ?? "none")",
            "failureClassifier=\(failureClassifier.rawValue)",
            "lifecycle=\(lifecycleEventCategories.joined(separator: ","))",
        ]
    }
}

enum ChromeMV3LivePopupProductPathTraceBuilder {
    static let domProbeScript = """
    (() => {
      const text = document.body && document.body.innerText
        ? document.body.innerText.trim()
        : "";
      const controls = document.querySelectorAll(
        'button,input,a[href],select,textarea'
      ).length;
      return JSON.stringify({
        visibleTextLength: text.length,
        controlCount: controls,
        bodyChildCount: document.body ? document.body.childElementCount : 0,
        navigationCommitted: document.readyState === "complete"
          || document.readyState === "interactive"
      });
    })();
    """

    static func textLengthBucket(_ length: Int) -> String {
        switch length {
        case 0:
            return "0"
        case 1 ... 20:
            return "1-20"
        case 21 ... 100:
            return "21-100"
        case 101 ... 500:
            return "101-500"
        default:
            return "500+"
        }
    }

    static func controlCountBucket(_ count: Int) -> String {
        switch count {
        case 0:
            return "0"
        case 1 ... 3:
            return "1-3"
        case 4 ... 10:
            return "4-10"
        default:
            return "10+"
        }
    }

    static func domCheckpoint(from object: [String: Any]) -> ChromeMV3LivePopupDOMCheckpoint {
        let visibleTextLength = object["visibleTextLength"] as? Int ?? 0
        let controlCount = object["controlCount"] as? Int ?? 0
        return ChromeMV3LivePopupDOMCheckpoint(
            visibleTextLengthBucket: textLengthBucket(visibleTextLength),
            controlCountBucket: controlCountBucket(controlCount),
            bodyChildCount: object["bodyChildCount"] as? Int ?? 0,
            navigationCommitted: object["navigationCommitted"] as? Bool ?? false
        )
    }

    static func classify(_ trace: ChromeMV3LivePopupProductPathTrace) -> ChromeMV3LivePopupFailureClassifier {
        if trace.forceNativeActionPopup || trace.forceControlledCompatibilityActionPopupOff {
            return .debugFlagForcesWrongPath
        }
        if trace.expectedPopupPath == ChromeMV3CompatibilityActionPopupPath
            .controlledCompatibilityActionPopup.rawValue,
            trace.actualPopupPath != trace.expectedPopupPath
        {
            if trace.actualPopupPath == "blocked" {
                return .runtimeGateMismatch
            }
            return .controlledPopupNotSelected
        }
        if trace.popupHostCreated == false {
            if trace.resourceLoadBlockerCategory == "generatedRootResourceMissing" {
                return .generatedRootResourceHandlerMissing
            }
            if trace.resourceLoadBlockerCategory != nil {
                return .requiredResourceLoadFailure
            }
            return .popupHostNotPresented
        }
        if trace.webViewCreated && trace.popoverPresented == false {
            if trace.scriptsExecuted
                || trace.firstDOMCheckpoint != nil
                || trace.bridgeInstalled
            {
                return .productPathDiffersFromTestHarness
            }
            return .popupHostNotPresented
        }
        if trace.popoverShown && trace.popoverPresented == false {
            return .popupHostDismissedImmediately
        }
        if trace.webViewDeallocated {
            return .popupWebViewDeallocated
        }
        if trace.webViewCreated && trace.webViewAttachedToHost == false {
            return .popupWebViewDetached
        }
        if trace.urlLoadCommitted == false {
            return .popupURLNotLoaded
        }
        if trace.generatedRootHandlerActive == false,
           trace.loadingMode.contains("diagnostic")
        {
            return .generatedRootResourceHandlerMissing
        }
        if trace.resourceLoadBlockerCategory != nil {
            return .requiredResourceLoadFailure
        }
        if trace.bridgeInstalled == false {
            return .bridgeNotInstalled
        }
        if trace.scriptsExecuted == false {
            return .popupScriptsNotExecuted
        }
        if let first = trace.firstDOMCheckpoint,
           let final = trace.finalDOMCheckpoint
        {
            let firstVisible = first.visibleTextLengthBucket != "0"
            let finalVisible = final.visibleTextLengthBucket != "0"
            if firstVisible && finalVisible == false {
                return .popupDOMVisibleThenBlank
            }
            if firstVisible == false && finalVisible == false {
                if trace.extensionClassifier == "extensionLocalAppState" {
                    return .extensionLocalAppState
                }
                if trace.extensionClassifier == "extensionLocalRenderState" {
                    return .extensionLocalRenderState
                }
                return .popupDOMNeverVisible
            }
        }
        if trace.selectedTabBound == false {
            return .selectedTabBindingMissing
        }
        if trace.extensionClassifier == "extensionLocalAppState" {
            return .extensionLocalAppState
        }
        if trace.extensionClassifier == "extensionLocalRenderState" {
            return .extensionLocalRenderState
        }
        if trace.nativeHostLaunched {
            return .nativeMessagingRequired
        }
        return .unknown
    }
}

#endif
