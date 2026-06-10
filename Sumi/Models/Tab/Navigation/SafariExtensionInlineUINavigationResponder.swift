//
//  SafariExtensionInlineUINavigationResponder.swift
//  Sumi
//
//  Observes extension-scheme subframe resource loads for inline overlay diagnostics.
//  Never logs credentials, full URLs, or page DOM contents.
//

import Foundation
import WebKit

@MainActor
final class SafariExtensionInlineUINavigationResponder:
    SumiNavigationResponseResponding,
    SumiNavigationCompletionResponding {
    private static let extensionResourceSchemes: Set<String> = [
        "webkit-extension",
        "safari-web-extension",
    ]

    private weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
    }

    func decidePolicy(for navigationResponse: SumiNavigationResponse) async -> SumiNavigationResponsePolicy? {
        let url = navigationResponse.url
        guard Self.extensionResourceSchemes.contains(url.scheme?.lowercased() ?? "") else {
            return .next
        }

        SafariExtensionAutofillFillDiagnostics.recordExtensionResourceNavigation(
            url: url,
            isMainFrame: navigationResponse.isForMainFrame,
            mimeType: navigationResponse.mimeType,
            phase: .committed,
            extensionId: nil
        )
        if navigationResponse.isForMainFrame == false {
            let frameNote = "subframeResponse frameId=\(frameIdentifier(isMainFrame: navigationResponse.isForMainFrame))"
            SafariExtensionAutofillFillDiagnostics.recordInlineUIRenderAttempted(
                extensionId: nil,
                reason: frameNote
            )
        }
        return .next
    }

    func navigationDidFail(_ error: WKError, context: SumiNavigationContext?) {
        guard let url = context?.url,
              Self.extensionResourceSchemes.contains(url.scheme?.lowercased() ?? "")
        else {
            return
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            SafariExtensionAutofillFillDiagnostics.recordExtensionResourceNavigation(
                url: url,
                isMainFrame: context?.isMainFrame == true,
                mimeType: nil,
                phase: .cancelled,
                extensionId: nil
            )
            return
        }

        SafariExtensionAutofillFillDiagnostics.recordExtensionResourceNavigation(
            url: url,
            isMainFrame: context?.isMainFrame == true,
            mimeType: nil,
            phase: .failed,
            extensionId: nil
        )
    }

    private func frameIdentifier(isMainFrame: Bool) -> String {
        isMainFrame ? "main" : "sub"
    }
}
