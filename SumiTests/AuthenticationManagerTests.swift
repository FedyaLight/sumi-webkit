import Foundation
import Security
import XCTest

@testable import Sumi

@MainActor
final class AuthenticationManagerTests: XCTestCase {
    func testUntrustedServerTrustWaitsForUserAndUsesTrustAfterConfirmation() throws {
        let manager = AuthenticationManager(
            credentialStore: BasicAuthCredentialStore(
                service: "com.sumi.authentication.tests.\(UUID().uuidString)"
            )
        )
        let tab = Tab(url: URL(string: "https://untrusted.example")!)
        var capturedSession: CertificateTrustWarningSession?
        var result: (URLSession.AuthChallengeDisposition?, URLCredential?) = (nil, nil)
        manager.attach(
            runtime: AuthenticationManagerRuntime(
                presentBasicAuthSheet: { _, _ in
                    XCTFail("Basic Auth sheet should not be used for server trust")
                    return false
                },
                presentCertificateTrustWarning: { session, _ in
                    capturedSession = session
                    return true
                },
                dismissNativeModalPresentation: {}
            )
        )

        let handled = manager.handleAuthenticationChallenge(
            try makeUntrustedServerTrustChallenge(),
            for: tab
        ) { disposition, credential in
            result = (disposition, credential)
        }

        XCTAssertTrue(handled)
        XCTAssertNil(result.0)
        XCTAssertEqual(capturedSession?.host, "untrusted.example")

        capturedSession?.visitSite()

        XCTAssertEqual(result.0, .useCredential)
        XCTAssertNotNil(result.1)
    }

    func testUntrustedServerTrustCancelsWhenUserClosesWarning() throws {
        let manager = AuthenticationManager(
            credentialStore: BasicAuthCredentialStore(
                service: "com.sumi.authentication.tests.\(UUID().uuidString)"
            )
        )
        let tab = Tab(url: URL(string: "https://untrusted.example")!)
        var capturedSession: CertificateTrustWarningSession?
        var result: URLSession.AuthChallengeDisposition?
        manager.attach(
            runtime: AuthenticationManagerRuntime(
                presentBasicAuthSheet: { _, _ in false },
                presentCertificateTrustWarning: { session, _ in
                    capturedSession = session
                    return true
                },
                dismissNativeModalPresentation: {}
            )
        )

        _ = manager.handleAuthenticationChallenge(
            try makeUntrustedServerTrustChallenge(),
            for: tab
        ) { disposition, _ in
            result = disposition
        }

        capturedSession?.closePage()

        XCTAssertEqual(result, .cancelAuthenticationChallenge)
    }

    func testClosingCertificateWarningClosesTab() throws {
        let manager = AuthenticationManager(
            credentialStore: BasicAuthCredentialStore(
                service: "com.sumi.authentication.tests.\(UUID().uuidString)"
            )
        )
        let tab = Tab(url: URL(string: "https://untrusted.example")!)
        var capturedSession: CertificateTrustWarningSession?
        var removedTabID: UUID?
        tab.navigationRuntime.closeLifecycleRuntime = TabCloseLifecycleRuntime(
            cleanupZoomForTab: { _ in },
            updateTabVisibility: {},
            removeTab: { removedTabID = $0 }
        )
        manager.attach(
            runtime: AuthenticationManagerRuntime(
                presentBasicAuthSheet: { _, _ in false },
                presentCertificateTrustWarning: { session, _ in
                    capturedSession = session
                    return true
                },
                dismissNativeModalPresentation: {}
            )
        )

        _ = manager.handleAuthenticationChallenge(
            try makeUntrustedServerTrustChallenge(),
            for: tab
        ) { _, _ in }

        capturedSession?.closePage()

        XCTAssertEqual(removedTabID, tab.id)
    }

    func testCertificateTrustApprovalCoversSubdomainsOfTheSameRegistrableDomain() throws {
        let manager = AuthenticationManager(
            credentialStore: BasicAuthCredentialStore(
                service: "com.sumi.authentication.tests.\(UUID().uuidString)"
            )
        )
        let tab = Tab(url: URL(string: "https://untrusted.com")!)
        var capturedSession: CertificateTrustWarningSession?
        var presentedCount = 0
        var firstResult: URLSession.AuthChallengeDisposition?
        var secondResult: URLSession.AuthChallengeDisposition?
        manager.attach(
            runtime: AuthenticationManagerRuntime(
                presentBasicAuthSheet: { _, _ in false },
                presentCertificateTrustWarning: { session, _ in
                    presentedCount += 1
                    capturedSession = session
                    return true
                },
                dismissNativeModalPresentation: {}
            )
        )

        _ = manager.handleAuthenticationChallenge(
            try makeUntrustedServerTrustChallenge(host: "untrusted.com"),
            for: tab
        ) { disposition, _ in
            firstResult = disposition
        }
        capturedSession?.visitSite()

        _ = manager.handleAuthenticationChallenge(
            try makeUntrustedServerTrustChallenge(host: "cdn.untrusted.com"),
            for: tab
        ) { disposition, _ in
            secondResult = disposition
        }

        XCTAssertEqual(presentedCount, 1)
        XCTAssertEqual(firstResult, .useCredential)
        XCTAssertEqual(secondResult, .useCredential)
    }

    func testPendingCertificateTrustChallengesShareOneWarning() throws {
        let manager = AuthenticationManager(
            credentialStore: BasicAuthCredentialStore(
                service: "com.sumi.authentication.tests.\(UUID().uuidString)"
            )
        )
        let tab = Tab(url: URL(string: "https://untrusted.example")!)
        var capturedSession: CertificateTrustWarningSession?
        var presentedCount = 0
        var firstResult: URLSession.AuthChallengeDisposition?
        var secondResult: URLSession.AuthChallengeDisposition?
        manager.attach(
            runtime: AuthenticationManagerRuntime(
                presentBasicAuthSheet: { _, _ in false },
                presentCertificateTrustWarning: { session, _ in
                    presentedCount += 1
                    capturedSession = session
                    return true
                },
                dismissNativeModalPresentation: {}
            )
        )

        _ = manager.handleAuthenticationChallenge(
            try makeUntrustedServerTrustChallenge(),
            for: tab
        ) { disposition, _ in
            firstResult = disposition
        }
        _ = manager.handleAuthenticationChallenge(
            try makeUntrustedServerTrustChallenge(),
            for: tab
        ) { disposition, _ in
            secondResult = disposition
        }

        XCTAssertEqual(presentedCount, 1)
        XCTAssertNil(firstResult)
        XCTAssertNil(secondResult)

        capturedSession?.visitSite()

        XCTAssertEqual(firstResult, .useCredential)
        XCTAssertEqual(secondResult, .useCredential)
    }

    func testCertificateTrustSessionIgnoresSecondDecision() {
        var decisions: [String] = []
        let session = CertificateTrustWarningSession(
            host: "untrusted.example",
            onVisitSite: { decisions.append("visit") },
            onClosePage: { decisions.append("close") },
            onCancel: { decisions.append("cancel") }
        )

        session.visitSite()
        session.closePage()

        XCTAssertEqual(decisions, ["visit"])
    }

    private func makeUntrustedServerTrustChallenge(
        host: String = "untrusted.example"
    ) throws -> URLAuthenticationChallenge {
        let certificateData = try XCTUnwrap(
            Data(
                base64Encoded: """
                MIICtDCCAZwCCQCnsWzM5HpEhTANBgkqhkiG9w0BAQsFADAcMRowGAYDVQQDDBF1bnRydXN0ZWQuZXhhbXBsZTAeFw0yNjA3MzExOTE0MTJaFw0zNjA3MjgxOTE0MTJaMBwxGjAYBgNVBAMMEXVudHJ1c3RlZC5leGFtcGxlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA8Ynlmen9+Sgb9OwehkBiIYqeOR6iafROMUeP7YgYuNQk6hjop+/oyMWwey5b1eg0f64KelRSnRT0+TtCsaVh5a9wdVKsu1uTFqTdopRyO8jAwtjZhGF6jTu2UfKS7TonWfj+EHWcz+ZKufHfIxjC9sm11/7R2zk2IOdRFl5vQ/sp4wontCGaiBme416bdNH+LBt7Iy+k6El90OfiS7hGYfblJMGsI6rXZxP8wSjVChcWGUo53wVR4uW1Ls3hPH29xj8aS3oL0aRsco4ZhZTr5eVSIoR1UhdwnC67HDwDjLQEu/N/rbCzI6oKd+dlXoBhK0VJ1XbFVs9EZ2pszhWaSwIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQAznlx1/OzpcZ0T8paJ4VGO2Y8B66Injj3QSIRCzwdVFqMHmGGwEgHe+nDreOj7sBzWQn+MGph+fHop19GJRp4zeqoOdxEWwos69/V1UgKMIYexy8st23fS/9VBg0OtuTT9X19csrf8r/Y17xTzeZmgJRsM0FWpkxfa4e08rqhflwPjUcA/wpqycCjw9l4Yh135O01+zAq9tYVRntHo9lkjluygOxW8B/eg7+NrllflPMXf9GwmIIvkZlpq1m2eswW3ZBJDga71nLyfU69E4IRngS0B1SNY+9SJs9vet0ISEJlY0uV6fMkdEZQA42fJky5XHrOUjv7mNBb7QnnuThp8
                """,
                options: .ignoreUnknownCharacters
            )
        )
        let certificate = try XCTUnwrap(
            SecCertificateCreateWithData(nil, certificateData as CFData)
        )
        let policy = SecPolicyCreateSSL(true, host as CFString)
        var trust: SecTrust?
        XCTAssertEqual(SecTrustCreateWithCertificates(certificate, policy, &trust), errSecSuccess)
        return URLAuthenticationChallenge(
            protectionSpace: TestServerTrustProtectionSpace(
                host: host,
                trust: try XCTUnwrap(trust)
            ),
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: AuthenticationChallengeSender()
        )
    }
}

private final class TestServerTrustProtectionSpace: URLProtectionSpace, @unchecked Sendable {
    private let testTrust: SecTrust

    init(host: String, trust: SecTrust) {
        testTrust = trust
        super.init(
            host: host,
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
    }

    required init?(coder: NSCoder) {
        fatalError("TestServerTrustProtectionSpace does not support decoding")
    }

    override var serverTrust: SecTrust? {
        testTrust
    }
}

private final class AuthenticationChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}

    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}

    func cancel(_ challenge: URLAuthenticationChallenge) {}

    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
}
