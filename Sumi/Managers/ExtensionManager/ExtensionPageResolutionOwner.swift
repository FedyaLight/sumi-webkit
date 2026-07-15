import Foundation
import WebKit

/// Resolves which installed extension owns a page or context.
@available(macOS 15.5, *)
@MainActor
final class ExtensionPageResolutionOwner {
    private weak var manager: ExtensionManager?

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    func ownerExtensionID(
        extensionContext: WKWebExtensionContext? = nil,
        openerTab: Tab? = nil,
        extensionOwnedSourceURL: URL? = nil,
        explicitExtensionID: String? = nil
    ) -> String? {
        guard let manager else { return nil }
        var profileID = openerTab?.profileId
            ?? openerTab?.resolveProfile()?.id
        var candidates: [String] = []

        func admitContext(_ context: WKWebExtensionContext) -> Bool {
            guard let identity = manager.profileRuntime
                .exactContextIdentity(for: context),
                  profileID.map({ $0 == identity.profileId }) ?? true,
                  manager.profileRuntime.contexts(for: identity.profileId)[
                      identity.extensionId
                  ] === context,
                  manager.installedExtensionCollection.records.contains(
                      where: {
                          $0.id == identity.extensionId && $0.isEnabled
                      }
                  )
            else {
                return false
            }
            profileID = identity.profileId
            candidates.append(identity.extensionId)
            return true
        }

        if let extensionContext, admitContext(extensionContext) == false {
            return nil
        }
        if let override = openerTab?.webExtensionContextOverride,
           admitContext(override) == false {
            return nil
        }
        if profileID == nil {
            profileID = manager.runtime.currentProfile()?.id
        }

        func admitExtensionID(_ extensionID: String) -> Bool {
            guard extensionID.isEmpty == false,
                  let profileID,
                  manager.installedExtensionCollection.records.contains(
                      where: { $0.id == extensionID && $0.isEnabled }
                  ),
                  let context = manager.profileRuntime.contexts(
                      for: profileID
                  )[extensionID],
                  manager.profileRuntime.exactContextIdentity(for: context)
                    .map({
                        $0.extensionId == extensionID
                            && $0.profileId == profileID
                    }) == true
            else {
                return false
            }
            candidates.append(extensionID)
            return true
        }

        if let explicitExtensionID,
           admitExtensionID(explicitExtensionID) == false {
            return nil
        }

        func admitExtensionOwnedURL(_ url: URL) -> Bool {
            guard let profileID else { return false }
            let matches = manager.profileRuntime.contexts(for: profileID)
                .filter { _, context in
                    Self.isURL(url, ownedBy: context.baseURL)
                }
            guard matches.count == 1,
                  let match = matches.first,
                  admitContext(match.value),
                  candidates.last == match.key
            else {
                return false
            }
            return true
        }

        for url in [extensionOwnedSourceURL, openerTab?.url].compactMap({ $0 })
        where ExtensionURLIdentity.isOwned(url) {
            guard admitExtensionOwnedURL(url) else {
                return nil
            }
        }

        guard let owner = candidates.first,
              candidates.dropFirst().allSatisfy({ $0 == owner })
        else {
            return nil
        }
        return owner
    }

    private static func isURL(_ url: URL, ownedBy baseURL: URL) -> Bool {
        guard url.scheme?.lowercased() == baseURL.scheme?.lowercased(),
              url.host?.lowercased() == baseURL.host?.lowercased(),
              url.port == baseURL.port,
              url.user == baseURL.user,
              url.password == baseURL.password
        else {
            return false
        }

        let basePath = baseURL.standardized.path
        guard basePath.isEmpty == false, basePath != "/" else { return true }
        let requestedPath = url.standardized.path
        return requestedPath == basePath
            || requestedPath.hasPrefix(basePath + "/")
    }
}

// MARK: - ExtensionManager facade

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func extensionID(
        for extensionContext: WKWebExtensionContext
    ) -> String? {
        profileRuntime.extensionId(for: extensionContext)
    }

    func ownerExtensionID(
        extensionContext: WKWebExtensionContext? = nil,
        openerTab: Tab? = nil,
        extensionOwnedSourceURL: URL? = nil,
        explicitExtensionID: String? = nil
    ) -> String? {
        pageResolutionOwner.ownerExtensionID(
            extensionContext: extensionContext,
            openerTab: openerTab,
            extensionOwnedSourceURL: extensionOwnedSourceURL,
            explicitExtensionID: explicitExtensionID
        )
    }
}
