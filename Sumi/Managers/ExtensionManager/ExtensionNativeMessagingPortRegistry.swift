import Foundation

/// Ledger of live native-messaging port sessions keyed by physical port.
/// Each registration holds a weak witness of the exact port object plus a
/// monotonic claim token, so a stale unregister (late finalizer, reused
/// `ObjectIdentifier` address, replaced session) can never remove a newer
/// registration for the same key.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNativeMessagingPortRegistry {
    private struct Entry {
        let claimToken: UInt64
        weak var portWitness: AnyObject?
        let handler: NativeMessagingHandler
        let extensionId: String
        let profileId: UUID?
    }

    private var entriesByPortKey: [ObjectIdentifier: Entry] = [:]
    private var nextClaimToken: UInt64 = 1

    var count: Int {
        entriesByPortKey.count
    }

    var extensionIDs: [String] {
        entriesByPortKey.values.map(\.extensionId)
    }

    func registeredHandler(for port: AnyObject) -> NativeMessagingHandler? {
        guard let entry = entriesByPortKey[ObjectIdentifier(port)],
              entry.portWitness === port
        else {
            return nil
        }
        return entry.handler
    }

    /// Claims an unregistered physical port for one session and returns the
    /// claim token that alone authorizes the matching unregister mutation.
    /// A live physical port is never rebound to a second session: doing so
    /// would let either session disconnect or overwrite handlers owned by the
    /// other one.
    func register(
        handler: NativeMessagingHandler,
        port: AnyObject,
        extensionId: String,
        profileId: UUID?
    ) -> UInt64? {
        let portKey = ObjectIdentifier(port)
        if let existing = entriesByPortKey[portKey],
           existing.portWitness === port {
            return nil
        }

        precondition(nextClaimToken < UInt64.max, "Native messaging claim token exhausted")
        let claimToken = nextClaimToken
        nextClaimToken += 1
        entriesByPortKey[portKey] = Entry(
            claimToken: claimToken,
            portWitness: port,
            handler: handler,
            extensionId: extensionId,
            profileId: profileId
        )
        return claimToken
    }

    /// Removes the registration only when the claim token, the session and
    /// the entry still match exactly. A stale finalizer for a superseded or
    /// address-reused port fails closed as a no-op.
    func unregister(
        handler: NativeMessagingHandler,
        port: AnyObject,
        claimToken: UInt64
    ) {
        let portKey = ObjectIdentifier(port)
        guard let entry = entriesByPortKey[portKey],
              entry.claimToken == claimToken,
              entry.portWitness === port,
              entry.handler === handler
        else {
            return
        }
        entriesByPortKey.removeValue(forKey: portKey)
    }

    func disconnectAll() {
        guard entriesByPortKey.isEmpty == false else {
            return
        }

        let handlers = entriesByPortKey.values.map(\.handler)
        entriesByPortKey.removeAll()
        handlers.forEach { $0.disconnect() }
    }

    func disconnect(extensionId: String, profileId: UUID? = nil) {
        let staleKeys = entriesByPortKey.compactMap { key, entry -> ObjectIdentifier? in
            guard entry.extensionId == extensionId else { return nil }
            if let profileId, entry.profileId != profileId {
                return nil
            }
            return key
        }

        for key in staleKeys {
            guard let entry = entriesByPortKey.removeValue(forKey: key) else {
                continue
            }
            entry.handler.disconnect()
        }
    }
}
