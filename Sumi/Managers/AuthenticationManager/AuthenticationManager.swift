//
//  AuthenticationManager.swift
//  Sumi
//
//

import AppKit
import CryptoKit
import Foundation
import Security
import WebKit

@MainActor
struct AuthenticationManagerRuntime {
    var presentBasicAuthSheet: (BasicAuthSheetSession, Tab) -> Bool
    var presentCertificateTrustWarning: (CertificateTrustWarningSession, WKWebView?) -> Bool
    var dismissNativeModalPresentation: () -> Void
}

@MainActor
final class AuthenticationManager: NSObject {
    typealias CertificateTrustCompletion = (
        URLSession.AuthChallengeDisposition,
        URLCredential?
    ) -> Void

    private struct CertificateTrustPendingKey: Hashable {
        let tabID: UUID
        let host: String
        let certificateFingerprint: Data?
    }

    private struct CertificateTrustPendingChallenge {
        let trust: SecTrust
        let completion: CertificateTrustCompletion
    }

    private final class CertificateTrustPendingRequest {
        let key: CertificateTrustPendingKey
        var challenges: [CertificateTrustPendingChallenge] = []
        var session: CertificateTrustWarningSession?

        init(key: CertificateTrustPendingKey) {
            self.key = key
        }
    }

    private var runtime: AuthenticationManagerRuntime?
    private let credentialStore: BasicAuthCredentialStore
    private var approvedCertificateTrustKeys: Set<CertificateTrustPendingKey> = []
    private var pendingCertificateTrustRequests: [
        CertificateTrustPendingKey: CertificateTrustPendingRequest
    ] = [:]

    init(credentialStore: BasicAuthCredentialStore = BasicAuthCredentialStore()) {
        self.credentialStore = credentialStore
        super.init()
    }

    func attach(runtime: AuthenticationManagerRuntime) {
        self.runtime = runtime
    }

    func handleAuthenticationChallenge(
        _ challenge: URLAuthenticationChallenge,
        for tab: Tab,
        webView: WKWebView? = nil,
        mainFrameURL: URL? = nil,
        completionHandler: @escaping CertificateTrustCompletion
    ) -> Bool {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodDefault, NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest:
            let credentialKey = Self.credentialKey(for: challenge, tab: tab)

            if challenge.previousFailureCount == 0,
               let credentialKey,
               !credentialKey.isEphemeralProfile,
               let stored = credentialStore.credential(for: credentialKey) {
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
            guard let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return true
            }
            evaluateServerTrust(
                trust,
                challenge: challenge,
                tab: tab,
                webView: webView,
                mainFrameURL: mainFrameURL,
                completionHandler: completionHandler
            )
            return true
        case NSURLAuthenticationMethodClientCertificate:
            completionHandler(.performDefaultHandling, nil)
            return true
        default:
            return false
        }
    }

    private func evaluateServerTrust(
        _ trust: SecTrust,
        challenge: URLAuthenticationChallenge,
        tab: Tab,
        webView: WKWebView?,
        mainFrameURL: URL?,
        completionHandler: @escaping CertificateTrustCompletion
    ) {
        let status = SecTrustEvaluateAsyncWithError(
            trust,
            .main
        ) { [weak self, weak tab, weak webView] trust, isTrusted, _ in
            MainActor.assumeIsolated {
                guard let self, let tab else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                    return
                }
                self.handleEvaluatedServerTrust(
                    trust,
                    isTrusted: isTrusted,
                    challenge: challenge,
                    tab: tab,
                    webView: webView,
                    mainFrameURL: mainFrameURL,
                    completionHandler: completionHandler
                )
            }
        }
        if status != errSecSuccess {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func handleEvaluatedServerTrust(
        _ trust: SecTrust,
        isTrusted: Bool,
        challenge: URLAuthenticationChallenge,
        tab: Tab,
        webView: WKWebView?,
        mainFrameURL: URL?,
        completionHandler: @escaping CertificateTrustCompletion
    ) {
        if isTrusted {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        let host = challenge.protectionSpace.host.isEmpty
            ? (tab.url.host ?? "this site")
            : challenge.protectionSpace.host
        let normalizedHost = Self.normalizedHost(host)

        if let mainFrameHost = mainFrameURL?.host,
           normalizedHost != Self.normalizedHost(mainFrameHost) {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let pendingKey = CertificateTrustPendingKey(
            tabID: tab.id,
            host: normalizedHost,
            certificateFingerprint: Self.certificateFingerprint(for: trust)
        )

        if isCertificateTrustApproved(for: pendingKey) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        if let pending = pendingCertificateTrustRequests[pendingKey] {
            pending.challenges.append(
                CertificateTrustPendingChallenge(
                    trust: trust,
                    completion: completionHandler
                )
            )
            return
        }

        guard let runtime else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let pending = CertificateTrustPendingRequest(key: pendingKey)
        pending.challenges.append(
            CertificateTrustPendingChallenge(
                trust: trust,
                completion: completionHandler
            )
        )
        let session = CertificateTrustWarningSession(
            host: host,
            onVisitSite: { [weak self, weak pending] in
                guard let self, let pending else { return }
                self.completeCertificateTrustRequest(pending, allowing: true)
            },
            onClosePage: { [weak self, weak pending, weak tab] in
                guard let self, let pending else { return }
                self.completeCertificateTrustRequest(pending, allowing: false)
                tab?.closeTab()
            },
            onCancel: { [weak self, weak pending] in
                guard let self, let pending else { return }
                self.completeCertificateTrustRequest(pending, allowing: false)
            }
        )
        pending.session = session
        pendingCertificateTrustRequests[pendingKey] = pending

        if runtime.presentCertificateTrustWarning(session, webView) == false {
            session.cancel()
        }
    }

    private func isCertificateTrustApproved(
        for key: CertificateTrustPendingKey
    ) -> Bool {
        approvedCertificateTrustKeys.contains(key)
    }

    private func completeCertificateTrustRequest(
        _ pending: CertificateTrustPendingRequest,
        allowing: Bool
    ) {
        guard pendingCertificateTrustRequests[pending.key] === pending else { return }
        pendingCertificateTrustRequests.removeValue(forKey: pending.key)

        if allowing {
            approvedCertificateTrustKeys.insert(pending.key)
        }

        let disposition: URLSession.AuthChallengeDisposition = allowing
            ? .useCredential
            : .cancelAuthenticationChallenge
        for challenge in pending.challenges {
            let credential = allowing ? URLCredential(trust: challenge.trust) : nil
            challenge.completion(disposition, credential)
        }
    }

    private static func normalizedHost(_ host: String) -> String {
        var normalized = host.lowercased()
        while normalized.hasSuffix(".") {
            normalized.removeLast()
        }
        return normalized
    }

    private static func certificateFingerprint(for trust: SecTrust) -> Data? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = chain.first else {
            return nil
        }
        return Data(SHA256.hash(data: SecCertificateCopyData(certificate) as Data))
    }

    private func presentBasicCredentialPrompt(
        for challenge: URLAuthenticationChallenge,
        tab: Tab,
        completion: @escaping (URLCredential?) -> Void
    ) {
        guard let runtime else {
            completion(nil)
            return
        }

        let host = challenge.protectionSpace.host
        let credentialKey = Self.credentialKey(for: challenge, tab: tab)
        let displayHost: String
        if !host.isEmpty {
            displayHost = host
        } else if !tab.url.absoluteString.isEmpty {
            let url = tab.url
            displayHost = url.host ?? url.absoluteString
        } else {
            displayHost = "this site"
        }

        let canRememberCredential = credentialKey?.isEphemeralProfile == false
        let prefilledCredential = canRememberCredential
            ? credentialKey.flatMap { credentialStore.credential(for: $0) }
            : nil
        let model = BasicAuthDialogModel(
            host: displayHost,
            username: prefilledCredential?.username ?? "",
            password: prefilledCredential?.password ?? "",
            rememberCredential: prefilledCredential != nil,
            canRememberCredential: canRememberCredential,
            warningText: Self.warningText(for: challenge)
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

                if let credentialKey {
                    if remember, !credentialKey.isEphemeralProfile {
                        self.credentialStore.saveCredential(.init(username: username, password: password), for: credentialKey)
                    } else {
                        self.credentialStore.deleteCredential(for: credentialKey)
                    }
                }

                runtime.dismissNativeModalPresentation()
                finish(with: URLCredential(user: username, password: password, persistence: .forSession))
            },
            onCancel: {
                NSApp.mainWindow?.makeFirstResponder(nil)
                runtime.dismissNativeModalPresentation()
                finish(with: nil)
            }
        )

        if runtime.presentBasicAuthSheet(session, tab) == false {
            session.cancel()
        }
    }

    private static func warningText(for challenge: URLAuthenticationChallenge) -> String? {
        guard challenge.protectionSpace.protocol?.lowercased() == "http" else {
            return nil
        }
        return "Credentials will be sent over an unencrypted HTTP connection."
    }

    private static func credentialKey(
        for challenge: URLAuthenticationChallenge,
        tab: Tab
    ) -> BasicAuthCredentialKey? {
        let profile = tab.resolveProfile()
        return BasicAuthCredentialKey(
            protectionSpace: challenge.protectionSpace,
            profileId: profile?.id ?? tab.profileId,
            isEphemeralProfile: profile?.isEphemeral ?? tab.isEphemeral,
            websiteDataStoreIdentifier: profile?.dataStore.identifier
        )
    }
}
