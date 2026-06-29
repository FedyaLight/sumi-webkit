import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionNativeMessagingPortRegistry {
    var nativeMessagePortHandlers: [ObjectIdentifier: NativeMessagingHandler] = [:]
    var nativeMessagePortExtensionIDs: [ObjectIdentifier: String] = [:]
    var nativeMessagePortProfileIDs: [ObjectIdentifier: UUID] = [:]

    var count: Int {
        nativeMessagePortHandlers.count
    }

    var extensionIDs: [String] {
        Array(nativeMessagePortExtensionIDs.values)
    }

    func register(
        handler: NativeMessagingHandler,
        portKey: ObjectIdentifier,
        extensionId: String?,
        profileId: UUID?
    ) {
        nativeMessagePortHandlers[portKey] = handler
        if let extensionId {
            nativeMessagePortExtensionIDs[portKey] = extensionId
        }
        if let profileId {
            nativeMessagePortProfileIDs[portKey] = profileId
        }
    }

    func unregister(handler: NativeMessagingHandler, portKey: ObjectIdentifier) {
        if let current = nativeMessagePortHandlers[portKey],
           current !== handler {
            return
        }
        remove(portKey)
    }

    func disconnectAll() {
        guard nativeMessagePortHandlers.isEmpty == false else {
            return
        }

        nativeMessagePortHandlers.values.forEach { $0.disconnect() }
        nativeMessagePortHandlers.removeAll()
        nativeMessagePortExtensionIDs.removeAll()
        nativeMessagePortProfileIDs.removeAll()
    }

    func disconnect(extensionId: String, profileId: UUID? = nil) {
        let handlerIDs = nativeMessagePortExtensionIDs.compactMap { entry -> ObjectIdentifier? in
            guard entry.value == extensionId else { return nil }
            if let profileId, nativeMessagePortProfileIDs[entry.key] != profileId {
                return nil
            }
            return entry.key
        }

        for handlerID in handlerIDs {
            nativeMessagePortHandlers[handlerID]?.disconnect()
            remove(handlerID)
        }
    }

    private func remove(_ portKey: ObjectIdentifier) {
        nativeMessagePortHandlers.removeValue(forKey: portKey)
        nativeMessagePortExtensionIDs.removeValue(forKey: portKey)
        nativeMessagePortProfileIDs.removeValue(forKey: portKey)
    }
}
