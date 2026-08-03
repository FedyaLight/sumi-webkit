import Foundation
import Security
import XCTest

@testable import Sumi

@MainActor
final class AuthenticationManagerTests: XCTestCase {
    func testUntrustedServerTrustWaitsForUserAndUsesTrustAfterConfirmation() async throws {
        let manager = AuthenticationManager(
            credentialStore: BasicAuthCredentialStore(
                service: "com.sumi.authentication.tests.\(UUID().uuidString)"
            )
        )
        let tab = Tab(url: URL(string: "https://untrusted.example")!)
        let warningPresented = expectation(description: "Certificate warning presented")
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
                    warningPresented.fulfill()
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
        await fulfillment(of: [warningPresented], timeout: 1)
        XCTAssertNil(result.0)
        XCTAssertEqual(capturedSession?.host, "untrusted.example")

        capturedSession?.visitSite()

        XCTAssertEqual(result.0, .useCredential)
        XCTAssertNotNil(result.1)
    }

    func testUntrustedServerTrustCancelsWhenUserClosesWarning() async throws {
        let manager = AuthenticationManager(
            credentialStore: BasicAuthCredentialStore(
                service: "com.sumi.authentication.tests.\(UUID().uuidString)"
            )
        )
        let tab = Tab(url: URL(string: "https://untrusted.example")!)
        let warningPresented = expectation(description: "Certificate warning presented")
        var capturedSession: CertificateTrustWarningSession?
        var result: URLSession.AuthChallengeDisposition?
        manager.attach(
            runtime: AuthenticationManagerRuntime(
                presentBasicAuthSheet: { _, _ in false },
                presentCertificateTrustWarning: { session, _ in
                    capturedSession = session
                    warningPresented.fulfill()
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

        await fulfillment(of: [warningPresented], timeout: 1)
        capturedSession?.closePage()

        XCTAssertEqual(result, .cancelAuthenticationChallenge)
    }

    func testClosingCertificateWarningClosesTab() async throws {
        let manager = AuthenticationManager(
            credentialStore: BasicAuthCredentialStore(
                service: "com.sumi.authentication.tests.\(UUID().uuidString)"
            )
        )
        let tab = Tab(url: URL(string: "https://untrusted.example")!)
        let warningPresented = expectation(description: "Certificate warning presented")
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
                    warningPresented.fulfill()
                    return true
                },
                dismissNativeModalPresentation: {}
            )
        )

        _ = manager.handleAuthenticationChallenge(
            try makeUntrustedServerTrustChallenge(),
            for: tab
        ) { _, _ in }

        await fulfillment(of: [warningPresented], timeout: 1)
        capturedSession?.closePage()

        XCTAssertEqual(removedTabID, tab.id)
    }

    func testCertificateTrustApprovalDoesNotCoverAnotherHost() async throws {
        let manager = AuthenticationManager(
            credentialStore: BasicAuthCredentialStore(
                service: "com.sumi.authentication.tests.\(UUID().uuidString)"
            )
        )
        let tab = Tab(url: URL(string: "https://untrusted.com")!)
        let firstWarningPresented = expectation(description: "First certificate warning presented")
        let secondWarningPresented = expectation(description: "Second certificate warning presented")
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
                    if presentedCount == 1 {
                        firstWarningPresented.fulfill()
                    } else {
                        secondWarningPresented.fulfill()
                    }
                    return true
                },
                dismissNativeModalPresentation: {}
            )
        )

        _ = manager.handleAuthenticationChallenge(
            try makeUntrustedServerTrustChallenge(host: "untrusted.com"),
            for: tab,
            mainFrameURL: URL(string: "https://untrusted.com")!
        ) { disposition, _ in
            firstResult = disposition
        }
        await fulfillment(of: [firstWarningPresented], timeout: 1)
        capturedSession?.visitSite()

        _ = manager.handleAuthenticationChallenge(
            try makeUntrustedServerTrustChallenge(host: "cdn.untrusted.com"),
            for: tab,
            mainFrameURL: URL(string: "https://cdn.untrusted.com")!
        ) { disposition, _ in
            secondResult = disposition
        }
        await fulfillment(of: [secondWarningPresented], timeout: 1)

        XCTAssertEqual(presentedCount, 2)
        XCTAssertEqual(firstResult, .useCredential)
        XCTAssertNil(secondResult)
    }

    func testUntrustedSubresourceTrustCancelsWithoutPresentingWarning() async throws {
        let manager = AuthenticationManager(
            credentialStore: BasicAuthCredentialStore(
                service: "com.sumi.authentication.tests.\(UUID().uuidString)"
            )
        )
        let tab = Tab(url: URL(string: "https://trusted.example")!)
        let challengeCompleted = expectation(description: "Subresource challenge completed")
        var presentedCount = 0
        var result: URLSession.AuthChallengeDisposition?
        manager.attach(
            runtime: AuthenticationManagerRuntime(
                presentBasicAuthSheet: { _, _ in false },
                presentCertificateTrustWarning: { _, _ in
                    presentedCount += 1
                    return true
                },
                dismissNativeModalPresentation: {}
            )
        )

        let handled = manager.handleAuthenticationChallenge(
            try makeUntrustedServerTrustChallenge(host: "cdn.untrusted.example"),
            for: tab,
            mainFrameURL: URL(string: "https://trusted.example/page")!
        ) { disposition, _ in
            result = disposition
            challengeCompleted.fulfill()
        }

        XCTAssertTrue(handled)
        await fulfillment(of: [challengeCompleted], timeout: 1)
        XCTAssertEqual(result, .cancelAuthenticationChallenge)
        XCTAssertEqual(presentedCount, 0)
    }

    func testPendingCertificateTrustChallengesShareOneWarning() async throws {
        let manager = AuthenticationManager(
            credentialStore: BasicAuthCredentialStore(
                service: "com.sumi.authentication.tests.\(UUID().uuidString)"
            )
        )
        let tab = Tab(url: URL(string: "https://untrusted.example")!)
        let warningPresented = expectation(description: "Certificate warning presented")
        let firstChallengeCompleted = expectation(description: "First challenge completed")
        let secondChallengeCompleted = expectation(description: "Second challenge completed")
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
                    warningPresented.fulfill()
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
            firstChallengeCompleted.fulfill()
        }
        _ = manager.handleAuthenticationChallenge(
            try makeUntrustedServerTrustChallenge(),
            for: tab
        ) { disposition, _ in
            secondResult = disposition
            secondChallengeCompleted.fulfill()
        }

        await fulfillment(of: [warningPresented], timeout: 1)
        XCTAssertEqual(presentedCount, 1)
        XCTAssertNil(firstResult)
        XCTAssertNil(secondResult)

        capturedSession?.visitSite()
        await fulfillment(
            of: [firstChallengeCompleted, secondChallengeCompleted],
            timeout: 1
        )

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
