//
//  SumiProfileCookieInstallationService.swift
//  Sumi
//

import Foundation
import WebKit

/// What an install changed, so it can be undone.
struct SumiCookieInstallationReceipt: Sendable {
    var installedIdentities: Set<String> = []
    /// Values that were present before the import overwrote them, so a rollback
    /// restores the user's own session rather than merely deleting.
    var replaced: [HTTPCookie] = []
}

/// Writes cookies into a profile's website data store.
///
/// This is the only constructive counterpart to `SumiWebsiteDataCleanupService`,
/// which stays the single owner of destructive website-data mutation — this
/// type composes it for rollback rather than deleting cookies itself.
///
/// Merge never overwrites a cookie that already exists: the user may already be
/// signed in to a site in Sumi, and replacing that session with an older one
/// imported from another browser would sign them out of the newer one.
@MainActor
final class SumiProfileCookieInstallationService {
    private let dataStoreProvider: @MainActor (UUID) -> WKWebsiteDataStore?

    init(dataStoreProvider: @escaping @MainActor (UUID) -> WKWebsiteDataStore?) {
        self.dataStoreProvider = dataStoreProvider
    }

    func install(
        _ cookies: [SumiStagedCookie],
        profileId: UUID,
        overwriteExisting: Bool
    ) async -> SumiCookieInstallationReceipt {
        guard let store = dataStoreProvider(profileId) else { return SumiCookieInstallationReceipt() }
        let cookieStore = store.httpCookieStore

        let existing = await cookieStore.allCookies()
        let existingByIdentity = Dictionary(
            existing.map { (Self.identity(of: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var receipt = SumiCookieInstallationReceipt()
        for staged in cookies {
            let identity = staged.identity
            if let current = existingByIdentity[identity] {
                guard overwriteExisting else { continue }
                receipt.replaced.append(current)
            }
            guard let cookie = Self.makeCookie(staged) else { continue }
            await cookieStore.setCookie(cookie)
            receipt.installedIdentities.insert(identity)
        }
        return receipt
    }

    /// Removes the cookies this import created and restores any it replaced.
    func rollback(_ receipt: SumiCookieInstallationReceipt, profileId: UUID) async {
        guard let store = dataStoreProvider(profileId) else { return }
        let cookieStore = store.httpCookieStore

        let restoredIdentities = Set(receipt.replaced.map(Self.identity(of:)))
        for cookie in await cookieStore.allCookies()
        where receipt.installedIdentities.contains(Self.identity(of: cookie))
            && restoredIdentities.contains(Self.identity(of: cookie)) == false {
            await cookieStore.deleteCookie(cookie)
        }
        for cookie in receipt.replaced {
            await cookieStore.setCookie(cookie)
        }
    }

    static func identity(of cookie: HTTPCookie) -> String {
        "\(cookie.name)\u{1}\(cookie.domain)\u{1}\(cookie.path)"
    }

    static func makeCookie(_ staged: SumiStagedCookie) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: staged.name,
            .value: staged.value,
            .domain: staged.domain,
            .path: staged.path.isEmpty ? "/" : staged.path,
        ]
        if let expiresAt = staged.expiresAt {
            // An already-expired cookie is dead weight; WebKit would drop it.
            guard expiresAt > Date() else { return nil }
            properties[.expires] = expiresAt
        }
        if staged.isSecure { properties[.secure] = "TRUE" }
        if staged.isHTTPOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        return HTTPCookie(properties: properties)
    }
}
