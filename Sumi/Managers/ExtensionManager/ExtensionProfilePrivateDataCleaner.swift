import Foundation

enum ExtensionProfilePrivateDataCleanupError: Error, Equatable {
    case unreadablePayload(String)
    case persistenceVerificationFailed(String)
}

/// Removes profile-scoped extension private data without loading WebExtension runtime.
@MainActor
final class ExtensionProfilePrivateDataCleaner {
    private static let siteAccessStorageKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.siteAccess.v1"
    private static let permissionDecisionsStorageKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.permissionDecisions.v1"
    private let preferences: UserDefaults
    private let deleteControllerStorage: @MainActor (UUID) throws -> Void
    private let deleteProtonPassState: @MainActor (UUID) throws -> Void

    init(
        preferences: UserDefaults,
        deleteControllerStorage: @escaping @MainActor (UUID) throws -> Void = {
            profileID in
            try WebExtensionStorageCleanupStore(
                controllerStorageId: ExtensionControllerProvisioningOwner
                    .persistentControllerIdentifier(for: profileID),
                planner: WebExtensionStorageCleanupPlanner()
            ).deleteControllerStorageDirectory()
        },
        deleteProtonPassState: @escaping @MainActor (UUID) throws -> Void = {
            profileID in
            try KeychainProtonPassSafariCompanionStore()
                .deleteProfileData(profileID: profileID)
        }
    ) {
        self.preferences = preferences
        self.deleteControllerStorage = deleteControllerStorage
        self.deleteProtonPassState = deleteProtonPassState
    }

    func deleteProfileData(profileID: UUID) throws {
        let profileKey = profileID.uuidString.lowercased()
        try deleteSiteAccessPolicies(profileKey: profileKey)
        try deletePermissionDecisions(profileKey: profileKey)
        try deleteProfileArrayMap(
            storageKey: ExtensionToolbarPinningOwner
                .pinnedToolbarExtensionIDsStorageKey,
            profileKey: ExtensionToolbarPinningOwner
                .pinnedToolbarProfileKey(for: profileID),
            globalProfileKey: ExtensionToolbarPinningOwner
                .pinnedToolbarProfileKey(for: nil)
        )
        try deleteProfileArrayMap(
            storageKey: ExtensionHubOrderingOwner.unpinnedOrderStorageKey,
            profileKey: ExtensionHubOrderingOwner.profileKey(for: profileID),
            globalProfileKey: ExtensionHubOrderingOwner.profileKey(for: nil)
        )
        try deleteControllerStorage(profileID)
        try deleteProtonPassState(profileID)
    }

    private func deleteSiteAccessPolicies(profileKey: String) throws {
        let storageKey = Self.siteAccessStorageKey
        guard let data = preferences.data(forKey: storageKey) else { return }
        var records = try jsonDictionary(data, storageKey: storageKey)
        guard records.keys.allSatisfy({ $0.contains("|") }) else {
            throw ExtensionProfilePrivateDataCleanupError
                .unreadablePayload(storageKey)
        }
        records = records.filter { key, _ in
            key.hasPrefix("\(profileKey)|") == false
        }
        try persist(records, storageKey: storageKey)
    }

    private func deletePermissionDecisions(profileKey: String) throws {
        let storageKey = Self.permissionDecisionsStorageKey
        guard let data = preferences.data(forKey: storageKey) else { return }
        var records = try jsonDictionary(data, storageKey: storageKey)
        let typedRecords = try records.mapValues { value -> (record: [String: Any], profileKey: String) in
            guard let record = value as? [String: Any],
                  let storedProfileKey = record["profileId"] as? String else {
                throw ExtensionProfilePrivateDataCleanupError
                    .unreadablePayload(storageKey)
            }
            return (record, storedProfileKey)
        }
        records = typedRecords
            .filter { $0.value.profileKey != profileKey }
            .mapValues(\.record)
        try persist(records, storageKey: storageKey)
    }

    private func jsonDictionary(
        _ data: Data,
        storageKey: String
    ) throws -> [String: Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ExtensionProfilePrivateDataCleanupError
                .unreadablePayload(storageKey)
        }
        guard let records = object as? [String: Any] else {
            throw ExtensionProfilePrivateDataCleanupError
                .unreadablePayload(storageKey)
        }
        return records
    }

    private func persist(
        _ records: [String: Any],
        storageKey: String
    ) throws {
        let data: Data
        do {
            data = try JSONSerialization.data(
                withJSONObject: records,
                options: [.sortedKeys]
            )
        } catch {
            throw ExtensionProfilePrivateDataCleanupError
                .unreadablePayload(storageKey)
        }
        preferences.set(data, forKey: storageKey)
        guard preferences.data(forKey: storageKey) == data else {
            throw ExtensionProfilePrivateDataCleanupError
                .persistenceVerificationFailed(storageKey)
        }
    }

    private func deleteProfileArrayMap(
        storageKey: String,
        profileKey: String,
        globalProfileKey: String
    ) throws {
        guard let existingData = preferences.data(forKey: storageKey) else {
            return
        }
        let records: [String: [String]]
        do {
            records = try JSONDecoder().decode(
                [String: [String]].self,
                from: existingData
            )
        } catch {
            throw ExtensionProfilePrivateDataCleanupError
                .unreadablePayload(storageKey)
        }
        guard records.keys.allSatisfy({
            Self.isCanonicalProfileMapKey(
                $0,
                globalProfileKey: globalProfileKey
            )
        }) else {
            throw ExtensionProfilePrivateDataCleanupError
                .unreadablePayload(storageKey)
        }

        var retainedRecords = records
        guard retainedRecords.removeValue(forKey: profileKey) != nil else {
            return
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(retainedRecords)
        } catch {
            throw ExtensionProfilePrivateDataCleanupError
                .unreadablePayload(storageKey)
        }
        preferences.set(data, forKey: storageKey)
        guard preferences.data(forKey: storageKey) == data else {
            throw ExtensionProfilePrivateDataCleanupError
                .persistenceVerificationFailed(storageKey)
        }
    }

    private static func isCanonicalProfileMapKey(
        _ key: String,
        globalProfileKey: String
    ) -> Bool {
        if key == globalProfileKey { return true }
        guard let profileID = UUID(uuidString: key) else { return false }
        return profileID.uuidString.lowercased() == key
    }
}
