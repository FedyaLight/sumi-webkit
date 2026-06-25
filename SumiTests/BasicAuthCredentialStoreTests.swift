import Foundation
import XCTest

@testable import Sumi

@MainActor
final class BasicAuthCredentialStoreTests: XCTestCase {
    func testCredentialKeyIncludesProtectionSpaceProfileAndPrivateBoundary() throws {
        let profileId = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        let dataStoreId = try XCTUnwrap(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"))
        let base = try XCTUnwrap(makeKey(profileId: profileId, dataStoreId: dataStoreId))

        XCTAssertEqual(base.account, try XCTUnwrap(makeKey(profileId: profileId, dataStoreId: dataStoreId)).account)

        let variants: [(String, BasicAuthCredentialKey)] = [
            ("scheme", try XCTUnwrap(makeKey(protocolName: "http", profileId: profileId, dataStoreId: dataStoreId))),
            ("host", try XCTUnwrap(makeKey(host: "other.example", profileId: profileId, dataStoreId: dataStoreId))),
            ("port", try XCTUnwrap(makeKey(port: 8443, profileId: profileId, dataStoreId: dataStoreId))),
            ("realm", try XCTUnwrap(makeKey(realm: "realm-b", profileId: profileId, dataStoreId: dataStoreId))),
            ("method", try XCTUnwrap(makeKey(method: NSURLAuthenticationMethodHTTPDigest, profileId: profileId, dataStoreId: dataStoreId))),
            ("profile", try XCTUnwrap(makeKey(profileId: try XCTUnwrap(UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")), dataStoreId: dataStoreId))),
            ("private", try XCTUnwrap(makeKey(profileId: profileId, isEphemeral: true, dataStoreId: dataStoreId))),
            ("data store", try XCTUnwrap(makeKey(profileId: profileId, dataStoreId: try XCTUnwrap(UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")))))
        ]

        for (name, variant) in variants {
            XCTAssertNotEqual(base.account, variant.account, "Expected key to include \(name)")
        }
    }

    func testStoredCredentialIsScopedToExactProtectionSpace() throws {
        let store = BasicAuthCredentialStore(service: "com.sumi.basicAuth.tests.\(UUID().uuidString)")
        let profileId = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        let dataStoreId = try XCTUnwrap(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"))
        let allowedKey = try XCTUnwrap(makeKey(profileId: profileId, dataStoreId: dataStoreId))
        let otherRealmKey = try XCTUnwrap(makeKey(realm: "realm-b", profileId: profileId, dataStoreId: dataStoreId))
        defer {
            _ = store.deleteCredential(for: allowedKey)
            _ = store.deleteCredential(for: otherRealmKey)
        }

        XCTAssertTrue(store.saveCredential(.init(username: "alice", password: "secret"), for: allowedKey))

        XCTAssertEqual(store.credential(for: allowedKey)?.username, "alice")
        XCTAssertEqual(store.credential(for: allowedKey)?.password, "secret")
        XCTAssertNil(store.credential(for: otherRealmKey))
    }

    func testDeleteCredentialsCanClearOnlyOneProfilePartition() throws {
        let store = BasicAuthCredentialStore(service: "com.sumi.basicAuth.tests.\(UUID().uuidString)")
        let profileId = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        let otherProfileId = try XCTUnwrap(UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc"))
        let dataStoreId = try XCTUnwrap(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"))
        let key = try XCTUnwrap(makeKey(profileId: profileId, dataStoreId: dataStoreId))
        let otherProfileKey = try XCTUnwrap(makeKey(profileId: otherProfileId, dataStoreId: dataStoreId))
        defer {
            _ = store.deleteCredential(for: key)
            _ = store.deleteCredential(for: otherProfileKey)
        }

        XCTAssertTrue(store.saveCredential(.init(username: "alice", password: "secret"), for: key))
        XCTAssertTrue(store.saveCredential(.init(username: "bob", password: "other"), for: otherProfileKey))

        XCTAssertTrue(store.deleteCredentials(profilePartitionId: profileId, isEphemeralProfile: false))

        XCTAssertNil(store.credential(for: key))
        XCTAssertEqual(store.credential(for: otherProfileKey)?.username, "bob")
    }

    func testDeleteCredentialsCanClearEphemeralEntriesAcrossProfiles() throws {
        let store = BasicAuthCredentialStore(service: "com.sumi.basicAuth.tests.\(UUID().uuidString)")
        let profileId = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        let privateProfileId = try XCTUnwrap(UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd"))
        let dataStoreId = try XCTUnwrap(UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"))
        let regularKey = try XCTUnwrap(makeKey(profileId: profileId, dataStoreId: dataStoreId))
        let privateKey = try XCTUnwrap(makeKey(profileId: privateProfileId, isEphemeral: true, dataStoreId: dataStoreId))
        defer {
            _ = store.deleteCredential(for: regularKey)
            _ = store.deleteCredential(for: privateKey)
        }

        XCTAssertTrue(store.saveCredential(.init(username: "alice", password: "secret"), for: regularKey))
        XCTAssertTrue(store.saveCredential(.init(username: "private", password: "secret"), for: privateKey))

        XCTAssertTrue(store.deleteCredentials(profilePartitionId: nil, isEphemeralProfile: true))

        XCTAssertEqual(store.credential(for: regularKey)?.username, "alice")
        XCTAssertNil(store.credential(for: privateKey))
    }

    func testAuthenticationManagerDoesNotAutoReplayAcrossRealm() throws {
        let store = BasicAuthCredentialStore(service: "com.sumi.basicAuth.tests.\(UUID().uuidString)")
        let manager = AuthenticationManager(credentialStore: store)
        let profileId = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"))
        let tab = Tab(url: URL(string: "https://auth.example")!)
        tab.profileId = profileId
        let allowedKey = try XCTUnwrap(makeKey(profileId: profileId, dataStoreId: nil))
        defer {
            _ = store.deleteCredential(for: allowedKey)
        }

        XCTAssertTrue(store.saveCredential(.init(username: "alice", password: "secret"), for: allowedKey))

        let matchingResult = handle(makeChallenge(realm: "realm-a"), manager: manager, tab: tab)
        XCTAssertTrue(matchingResult.handled)
        XCTAssertEqual(matchingResult.disposition, .useCredential)
        XCTAssertEqual(matchingResult.credential?.user, "alice")
        XCTAssertEqual(matchingResult.credential?.password, "secret")

        let crossRealmResult = handle(makeChallenge(realm: "realm-b"), manager: manager, tab: tab)
        XCTAssertTrue(crossRealmResult.handled)
        XCTAssertEqual(crossRealmResult.disposition, .performDefaultHandling)
        XCTAssertNil(crossRealmResult.credential)
    }

    private func handle(
        _ challenge: URLAuthenticationChallenge,
        manager: AuthenticationManager,
        tab: Tab
    ) -> (handled: Bool, disposition: URLSession.AuthChallengeDisposition?, credential: URLCredential?) {
        var result: (URLSession.AuthChallengeDisposition?, URLCredential?) = (nil, nil)
        let handled = manager.handleAuthenticationChallenge(challenge, for: tab) { disposition, credential in
            result = (disposition, credential)
        }
        return (handled, result.0, result.1)
    }

    private func makeKey(
        protocolName: String = "https",
        host: String = "auth.example",
        port: Int = 443,
        realm: String = "realm-a",
        method: String = NSURLAuthenticationMethodHTTPBasic,
        profileId: UUID,
        isEphemeral: Bool = false,
        dataStoreId: UUID?
    ) -> BasicAuthCredentialKey? {
        BasicAuthCredentialKey(
            protectionSpace: URLProtectionSpace(
                host: host,
                port: port,
                protocol: protocolName,
                realm: realm,
                authenticationMethod: method
            ),
            profileId: profileId,
            isEphemeralProfile: isEphemeral,
            websiteDataStoreIdentifier: dataStoreId
        )
    }

    private func makeChallenge(realm: String) -> URLAuthenticationChallenge {
        URLAuthenticationChallenge(
            protectionSpace: URLProtectionSpace(
                host: "auth.example",
                port: 443,
                protocol: "https",
                realm: realm,
                authenticationMethod: NSURLAuthenticationMethodHTTPBasic
            ),
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: BasicAuthCredentialStoreChallengeSender()
        )
    }
}

private final class BasicAuthCredentialStoreChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {
        _ = credential
        _ = challenge
    }

    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {
        _ = challenge
    }

    func cancel(_ challenge: URLAuthenticationChallenge) {
        _ = challenge
    }

    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {
        _ = challenge
    }

    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {
        _ = challenge
    }
}
