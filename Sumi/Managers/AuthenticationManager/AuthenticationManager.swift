//
//  AuthenticationManager.swift
//  Sumi
//
//

import AppKit
import Foundation
import WebKit

@MainActor
final class AuthenticationManager: NSObject {
    private weak var browserManager: BrowserManager?
    private let credentialStore = BasicAuthCredentialStore()

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func handleAuthenticationChallenge(
        _ challenge: URLAuthenticationChallenge,
        for tab: Tab,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) -> Bool {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodDefault, NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest:
            let host = challenge.protectionSpace.host

            if !host.isEmpty,
               challenge.previousFailureCount == 0,
               let stored = credentialStore.credential(for: host) {
                completionHandler(.useCredential, stored.asURLCredential)
                return true
            }

            presentBasicCredentialPrompt(for: challenge, tab: tab) { credential in
                if let credential {
                    completionHandler(.useCredential, credential)
                } else {
                    completionHandler(.performDefaultHandling, nil)
                }
            }
            return true
        case NSURLAuthenticationMethodServerTrust:
            if let trust = challenge.protectionSpace.serverTrust {
                var error: CFError?
                if SecTrustEvaluateWithError(trust, &error) {
                    completionHandler(.useCredential, URLCredential(trust: trust))
                } else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                }
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
            return true
        case NSURLAuthenticationMethodClientCertificate:
            completionHandler(.performDefaultHandling, nil)
            return true
        default:
            return false
        }
    }

    private func presentBasicCredentialPrompt(
        for challenge: URLAuthenticationChallenge,
        tab: Tab,
        completion: @escaping (URLCredential?) -> Void
    ) {
        guard let manager = browserManager else {
            completion(nil)
            return
        }

        let host = challenge.protectionSpace.host
        let displayHost: String
        if !host.isEmpty {
            displayHost = host
        } else if let realm = challenge.protectionSpace.realm, !realm.isEmpty {
            displayHost = realm
        } else if !tab.url.absoluteString.isEmpty {
            let url = tab.url
            displayHost = url.host ?? url.absoluteString
        } else {
            displayHost = "this site"
        }

        let prefilledCredential = !host.isEmpty ? credentialStore.credential(for: host) : nil
        let model = BasicAuthDialogModel(
            host: displayHost,
            username: prefilledCredential?.username ?? "",
            password: prefilledCredential?.password ?? "",
            rememberCredential: prefilledCredential != nil
        )

        var didComplete = false
        func finish(with credential: URLCredential?) {
            guard didComplete == false else { return }
            didComplete = true
            completion(credential)
        }

        let session = BasicAuthSheetSession(
            model: model,
            onSubmit: { [weak self] username, password, remember in
                guard let self else { return }
                NSApp.mainWindow?.makeFirstResponder(nil)

                if !host.isEmpty {
                    if remember {
                        self.credentialStore.saveCredential(.init(username: username, password: password), for: host)
                    } else {
                        self.credentialStore.deleteCredential(for: host)
                    }
                }

                manager.dismissNativeModalPresentation()
                finish(with: URLCredential(user: username, password: password, persistence: .forSession))
            },
            onCancel: {
                NSApp.mainWindow?.makeFirstResponder(nil)
                manager.dismissNativeModalPresentation()
                finish(with: nil)
            }
        )

        if manager.presentBasicAuthSheet(session, in: manager.windowState(containing: tab)) == false {
            session.cancel()
        }
    }
}
