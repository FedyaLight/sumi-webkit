//
//  ChromeMV3StorageBroker.swift
//  Sumi
//
//  Deterministic Chrome MV3 storage model and host-backed broker foundation.
//  This file models future chrome.storage behavior only; it does not expose
//  APIs to JavaScript, create contexts, register listeners, dispatch events,
//  wake service workers, launch native messaging, or attach WebViews.
//

import CryptoKit
import Foundation

enum ChromeMV3StorageAreaKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case local
    case managed
    case session
    case sync

    static func < (
        lhs: ChromeMV3StorageAreaKind,
        rhs: ChromeMV3StorageAreaKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var chromeAreaName: String { rawValue }
}

enum ChromeMV3StoragePersistencePolicy:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case deferredSyncLocalOnlyDecision
    case memoryOnlyExtensionSession
    case profilePersistentLocal
    case unsupportedManagedPolicy
}

enum ChromeMV3StorageAreaAvailabilityStatus:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case brokerModelAvailable
    case deferredLocalOnlyDecision
    case unsupportedManagedPolicy
}

enum ChromeMV3StorageContentScriptAccessDefault:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case exposedByDefault
    case notExposedByDefault
    case unsupported
}

enum ChromeMV3StorageSyncSupportPolicy:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case deferredLocalOnlyFutureEmulation
}

struct ChromeMV3StorageSyncPolicy:
    Codable,
    Equatable,
    Sendable
{
    var status: ChromeMV3StorageSyncSupportPolicy
    var runtimeImplementedNow: Bool
    var brokerModelOperationsAvailable: Bool
    var reason: String
    var compatibilityRisk: String
    var passwordManagerImpact: String
    var futureUserFacingPolicyNeeded: Bool
    var diagnostics: [String]

    static let conservativeV1 = ChromeMV3StorageSyncPolicy(
        status: .deferredLocalOnlyFutureEmulation,
        runtimeImplementedNow: false,
        brokerModelOperationsAvailable: false,
        reason:
            "Sumi has no Chrome account sync contract for extension data; storage.sync is recorded as a deferred local-only future-emulation decision.",
        compatibilityRisk:
            "Extensions that expect cross-browser synchronization may behave differently if Sumi later maps sync to local-only storage.",
        passwordManagerImpact:
            "Password-manager fixtures must not assume synced vault, unlock, or fill state; they remain blocked until a product policy is chosen.",
        futureUserFacingPolicyNeeded: true,
        diagnostics: [
            "No sync support is claimed.",
            "No local-only sync emulation is active.",
            "No browser account sync integration is created.",
        ]
    )
}

enum ChromeMV3StorageOperationKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case clear
    case exportSnapshot
    case get
    case getAll
    case getBytesInUse
    case importSnapshot
    case remove
    case set

    static func < (
        lhs: ChromeMV3StorageOperationKind,
        rhs: ChromeMV3StorageOperationKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3StorageErrorCode:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case invalidValue
    case maxItemsExceeded
    case quotaBytesExceeded
    case quotaBytesPerItemExceeded
    case readOnlyOrUnsupportedArea
    case snapshotNamespaceMismatch
    case storageRuntimeNotImplemented

    static func < (
        lhs: ChromeMV3StorageErrorCode,
        rhs: ChromeMV3StorageErrorCode
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3StorageErrorDiagnostic:
    Codable,
    Equatable,
    Sendable
{
    var code: ChromeMV3StorageErrorCode
    var area: ChromeMV3StorageAreaKind
    var key: String?
    var message: String
    var wouldSetRuntimeLastError: Bool
    var wouldRejectPromise: Bool
    var runtimeImplementedNow: Bool
}

struct ChromeMV3StorageValueValidationDiagnostic:
    Codable,
    Equatable,
    Sendable
{
    var path: String
    var code: ChromeMV3StorageErrorCode
    var message: String
}

indirect enum ChromeMV3StorageValue:
    Codable,
    Equatable,
    Sendable
{
    case array([ChromeMV3StorageValue])
    case bool(Bool)
    case null
    case number(Double)
    case object([String: ChromeMV3StorageValue])
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([ChromeMV3StorageValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode(
            [String: ChromeMV3StorageValue].self
        ) {
            self = .object(value)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription:
                "Chrome MV3 storage values must be JSON-compatible."
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .array(let values):
            try container.encode(values)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .number(let value):
            guard value.isFinite else {
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription:
                            "Chrome MV3 storage numbers must be finite."
                    )
                )
            }
            try container.encode(value)
        case .object(let object):
            try container.encode(object)
        case .string(let value):
            try container.encode(value)
        }
    }

    var validationDiagnostics: [ChromeMV3StorageValueValidationDiagnostic] {
        validationDiagnostics(path: "$", depth: 0)
    }

    var isJSONCompatible: Bool {
        validationDiagnostics.isEmpty
    }

    func canonicalJSONString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? ""
    }

    fileprivate var deterministicByteCount: Int {
        (try? canonicalJSONString().utf8.count) ?? 0
    }

    private func validationDiagnostics(
        path: String,
        depth: Int
    ) -> [ChromeMV3StorageValueValidationDiagnostic] {
        guard depth <= 64 else {
            return [
                ChromeMV3StorageValueValidationDiagnostic(
                    path: path,
                    code: .invalidValue,
                    message:
                        "Chrome MV3 storage value nesting exceeds the modeled depth limit."
                ),
            ]
        }

        switch self {
        case .array(let values):
            return values.enumerated().flatMap { index, value in
                value.validationDiagnostics(
                    path: "\(path)[\(index)]",
                    depth: depth + 1
                )
            }
        case .number(let value):
            guard value.isFinite else {
                return [
                    ChromeMV3StorageValueValidationDiagnostic(
                        path: path,
                        code: .invalidValue,
                        message:
                            "Chrome MV3 storage numbers must be finite JSON numbers."
                    ),
                ]
            }
            return []
        case .object(let object):
            return object.keys.sorted().flatMap { key in
                object[key]?.validationDiagnostics(
                    path: "\(path).\(key)",
                    depth: depth + 1
                ) ?? []
            }
        case .bool, .null, .string:
            return []
        }
    }
}

struct ChromeMV3StorageItemByteUsage:
    Codable,
    Equatable,
    Sendable
{
    var key: String
    var bytes: Int
}

struct ChromeMV3StorageQuotaPolicy:
    Codable,
    Equatable,
    Sendable
{
    var area: ChromeMV3StorageAreaKind
    var quotaBytes: Int?
    var quotaBytesPerItem: Int?
    var maxItems: Int?
    var unlimitedStoragePermissionCanBypass: Bool
    var calculationMode: String
    var diagnostics: [String]

    static func policy(
        for area: ChromeMV3StorageAreaKind,
        unlimitedStoragePermissionPresent: Bool = false
    ) -> ChromeMV3StorageQuotaPolicy {
        switch area {
        case .local:
            return ChromeMV3StorageQuotaPolicy(
                area: area,
                quotaBytes: unlimitedStoragePermissionPresent
                    ? nil
                    : 10_485_760,
                quotaBytesPerItem: nil,
                maxItems: nil,
                unlimitedStoragePermissionCanBypass: true,
                calculationMode:
                    "Deterministic UTF-8 count of key plus canonical JSON value; this is a host-model quota diagnostic.",
                diagnostics: [
                    "Chrome documents storage.local QUOTA_BYTES as 10 MB unless unlimitedStorage applies.",
                    "Runtime lastError and Promise rejection are modeled but not emitted.",
                ]
            )
        case .session:
            return ChromeMV3StorageQuotaPolicy(
                area: area,
                quotaBytes: 10_485_760,
                quotaBytesPerItem: nil,
                maxItems: nil,
                unlimitedStoragePermissionCanBypass: false,
                calculationMode:
                    "Deterministic UTF-8 count of key plus canonical JSON value for in-memory session diagnostics.",
                diagnostics: [
                    "Chrome documents storage.session QUOTA_BYTES as 10 MB.",
                    "Session storage is modeled in memory and is not persisted to host files.",
                ]
            )
        case .sync:
            return ChromeMV3StorageQuotaPolicy(
                area: area,
                quotaBytes: 102_400,
                quotaBytesPerItem: 8_192,
                maxItems: 512,
                unlimitedStoragePermissionCanBypass: false,
                calculationMode:
                    "Quota constants are recorded for diagnostics only because storage.sync is deferred.",
                diagnostics: [
                    "Chrome documents storage.sync QUOTA_BYTES, QUOTA_BYTES_PER_ITEM, and MAX_ITEMS.",
                    "No sync or local-only emulation is active in this prompt.",
                ]
            )
        case .managed:
            return ChromeMV3StorageQuotaPolicy(
                area: area,
                quotaBytes: nil,
                quotaBytesPerItem: nil,
                maxItems: nil,
                unlimitedStoragePermissionCanBypass: false,
                calculationMode:
                    "Managed storage is unsupported in Sumi's current Chrome MV3 model.",
                diagnostics: [
                    "storage.managed is a read-only enterprise policy area in Chrome.",
                    "Sumi does not implement managed extension policy storage.",
                ]
            )
        }
    }
}

struct ChromeMV3StorageQuotaEvaluation:
    Codable,
    Equatable,
    Sendable
{
    var area: ChromeMV3StorageAreaKind
    var totalBytes: Int
    var quotaBytes: Int?
    var quotaBytesPerItem: Int?
    var maxItems: Int?
    var itemByteUsage: [ChromeMV3StorageItemByteUsage]
    var withinQuota: Bool
    var errorDiagnostics: [ChromeMV3StorageErrorDiagnostic]
}

struct ChromeMV3StorageAreaRecord:
    Codable,
    Equatable,
    Sendable
{
    var area: ChromeMV3StorageAreaKind
    var extensionID: String
    var profileID: String
    var recordID: String
    var profileIsolated: Bool
    var persistencePolicy: ChromeMV3StoragePersistencePolicy
    var availabilityStatus: ChromeMV3StorageAreaAvailabilityStatus
    var contentScriptAccessDefault:
        ChromeMV3StorageContentScriptAccessDefault
    var quotaPolicy: ChromeMV3StorageQuotaPolicy
    var readAllowedByModel: Bool
    var writeAllowedByModel: Bool
    var runtimeImplementedNow: Bool
    var diagnostics: [String]

    static func make(
        area: ChromeMV3StorageAreaKind,
        extensionID: String,
        profileID: String,
        unlimitedStoragePermissionPresent: Bool = false
    ) -> ChromeMV3StorageAreaRecord {
        let extensionID = extensionID.isEmpty
            ? "unknown-extension"
            : extensionID
        let profileID = profileID.isEmpty ? "unknown-profile" : profileID
        let quota = ChromeMV3StorageQuotaPolicy.policy(
            for: area,
            unlimitedStoragePermissionPresent: unlimitedStoragePermissionPresent
        )
        let recordID = ChromeMV3StorageStableID.make(
            prefix: "storage-area",
            components: [profileID, extensionID, area.rawValue]
        )

        switch area {
        case .local:
            return ChromeMV3StorageAreaRecord(
                area: area,
                extensionID: extensionID,
                profileID: profileID,
                recordID: recordID,
                profileIsolated: true,
                persistencePolicy: .profilePersistentLocal,
                availabilityStatus: .brokerModelAvailable,
                contentScriptAccessDefault: .exposedByDefault,
                quotaPolicy: quota,
                readAllowedByModel: true,
                writeAllowedByModel: true,
                runtimeImplementedNow: false,
                diagnostics: [
                    "storage.local is modeled through a deterministic host-backed broker.",
                    "Model operations are not exposed to JavaScript.",
                    "Values persist in explicit host-backed test roots only when a broker is constructed with a root URL.",
                ]
            )
        case .session:
            return ChromeMV3StorageAreaRecord(
                area: area,
                extensionID: extensionID,
                profileID: profileID,
                recordID: recordID,
                profileIsolated: true,
                persistencePolicy: .memoryOnlyExtensionSession,
                availabilityStatus: .brokerModelAvailable,
                contentScriptAccessDefault: .notExposedByDefault,
                quotaPolicy: quota,
                readAllowedByModel: true,
                writeAllowedByModel: true,
                runtimeImplementedNow: false,
                diagnostics: [
                    "storage.session is modeled as memory-only extension session state.",
                    "Session values survive modeled service-worker unload/reload because no worker exists here.",
                    "Session values clear on profile session cleanup, extension disable, extension reload, update, or browser restart policy inputs.",
                ]
            )
        case .sync:
            return ChromeMV3StorageAreaRecord(
                area: area,
                extensionID: extensionID,
                profileID: profileID,
                recordID: recordID,
                profileIsolated: true,
                persistencePolicy: .deferredSyncLocalOnlyDecision,
                availabilityStatus: .deferredLocalOnlyDecision,
                contentScriptAccessDefault: .exposedByDefault,
                quotaPolicy: quota,
                readAllowedByModel: false,
                writeAllowedByModel: false,
                runtimeImplementedNow: false,
                diagnostics: [
                    "storage.sync is deferred as a conservative local-only future-emulation decision.",
                    "No sync support is claimed.",
                    "Broker operations are blocked for sync until product policy is chosen.",
                ]
            )
        case .managed:
            return ChromeMV3StorageAreaRecord(
                area: area,
                extensionID: extensionID,
                profileID: profileID,
                recordID: recordID,
                profileIsolated: true,
                persistencePolicy: .unsupportedManagedPolicy,
                availabilityStatus: .unsupportedManagedPolicy,
                contentScriptAccessDefault: .unsupported,
                quotaPolicy: quota,
                readAllowedByModel: false,
                writeAllowedByModel: false,
                runtimeImplementedNow: false,
                diagnostics: [
                    "storage.managed is unsupported in Sumi's current Chrome MV3 foundation.",
                    "No enterprise policy storage provider is modeled.",
                ]
            )
        }
    }
}

struct ChromeMV3StorageNamespace:
    Codable,
    Equatable,
    Sendable
{
    var profileID: String
    var extensionID: String
    var area: ChromeMV3StorageAreaKind
    var namespaceID: String

    init(
        profileID: String,
        extensionID: String,
        area: ChromeMV3StorageAreaKind
    ) {
        self.profileID = profileID.isEmpty ? "unknown-profile" : profileID
        self.extensionID = extensionID.isEmpty
            ? "unknown-extension"
            : extensionID
        self.area = area
        self.namespaceID = ChromeMV3StorageStableID.make(
            prefix: "storage-namespace",
            components: [self.profileID, self.extensionID, area.rawValue]
        )
    }

    var relativePathComponents: [String] {
        [
            Self.safePathComponent(profileID),
            Self.safePathComponent(extensionID),
            area.rawValue,
        ]
    }

    private static func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_.")
        )
        return value.unicodeScalars.map { scalar in
            allowed.contains(scalar)
                ? String(Character(scalar))
                : String(format: "%%%02X", scalar.value)
        }.joined()
    }
}

struct ChromeMV3StorageSnapshotSummary:
    Codable,
    Equatable,
    Sendable
{
    var namespaceID: String
    var profileID: String
    var extensionID: String
    var area: ChromeMV3StorageAreaKind
    var keyCount: Int
    var totalBytes: Int
    var keys: [String]
}

struct ChromeMV3StorageSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var namespace: ChromeMV3StorageNamespace
    var values: [String: ChromeMV3StorageValue]
    var summary: ChromeMV3StorageSnapshotSummary

    init(
        namespace: ChromeMV3StorageNamespace,
        values: [String: ChromeMV3StorageValue] = [:]
    ) {
        let normalized = Self.normalized(values)
        self.schemaVersion = 1
        self.namespace = namespace
        self.values = normalized
        self.summary = ChromeMV3StorageSnapshotSummary(
            namespaceID: namespace.namespaceID,
            profileID: namespace.profileID,
            extensionID: namespace.extensionID,
            area: namespace.area,
            keyCount: normalized.count,
            totalBytes:
                ChromeMV3StorageByteCounter.totalBytes(values: normalized),
            keys: normalized.keys.sorted()
        )
    }

    private static func normalized(
        _ values: [String: ChromeMV3StorageValue]
    ) -> [String: ChromeMV3StorageValue] {
        Dictionary(uniqueKeysWithValues: values.keys.sorted().map {
            ($0, values[$0] ?? .null)
        })
    }
}

struct ChromeMV3StorageChangeRecord:
    Codable,
    Equatable,
    Sendable
{
    var key: String
    var oldValue: ChromeMV3StorageValue?
    var newValue: ChromeMV3StorageValue?
}

struct ChromeMV3StorageOnChangedEventPayload:
    Codable,
    Equatable,
    Sendable
{
    var areaName: String
    var changedKeys: [String]
    var changes: [ChromeMV3StorageChangeRecord]
    var extensionID: String
    var profileID: String
    var wouldDispatchNow: Bool
    var listenerRegistrationRequired: Bool
    var serviceWorkerWakeRequired: Bool
    var blockers: [String]
}

struct ChromeMV3StorageChangeSet:
    Codable,
    Equatable,
    Sendable
{
    var namespace: ChromeMV3StorageNamespace
    var changes: [ChromeMV3StorageChangeRecord]
    var changedKeys: [String]
    var futureOnChangedPayload: ChromeMV3StorageOnChangedEventPayload

    static func make(
        namespace: ChromeMV3StorageNamespace,
        oldValues: [String: ChromeMV3StorageValue],
        newValues: [String: ChromeMV3StorageValue]
    ) -> ChromeMV3StorageChangeSet {
        let keys = Array(Set(oldValues.keys).union(newValues.keys)).sorted()
        let changes = keys.compactMap { key -> ChromeMV3StorageChangeRecord? in
            let oldValue = oldValues[key]
            let newValue = newValues[key]
            guard oldValue != newValue else { return nil }
            return ChromeMV3StorageChangeRecord(
                key: key,
                oldValue: oldValue,
                newValue: newValue
            )
        }
        return ChromeMV3StorageChangeSet(
            namespace: namespace,
            changes: changes,
            changedKeys: changes.map(\.key),
            futureOnChangedPayload:
                ChromeMV3StorageOnChangedEventPayload(
                    areaName: namespace.area.chromeAreaName,
                    changedKeys: changes.map(\.key),
                    changes: changes,
                    extensionID: namespace.extensionID,
                    profileID: namespace.profileID,
                    wouldDispatchNow: false,
                    listenerRegistrationRequired: true,
                    serviceWorkerWakeRequired: true,
                    blockers: [
                        "storage.onChanged listener registration is not implemented.",
                        "storage.onChanged event dispatch is not implemented.",
                        "Future service-worker wake may be required for registered storage listeners, but wake is blocked now.",
                    ]
                )
        )
    }

    static func empty(
        namespace: ChromeMV3StorageNamespace
    ) -> ChromeMV3StorageChangeSet {
        make(namespace: namespace, oldValues: [:], newValues: [:])
    }
}

struct ChromeMV3StorageOperationResult:
    Codable,
    Equatable,
    Sendable
{
    var operation: ChromeMV3StorageOperationKind
    var namespace: ChromeMV3StorageNamespace
    var areaRecord: ChromeMV3StorageAreaRecord
    var succeeded: Bool
    var brokerModelOperationsAvailable: Bool
    var returnedValues: [String: ChromeMV3StorageValue]
    var bytesInUse: Int?
    var quotaEvaluation: ChromeMV3StorageQuotaEvaluation
    var changeSet: ChromeMV3StorageChangeSet
    var errorDiagnostics: [ChromeMV3StorageErrorDiagnostic]
    var runtimeImplementedNow: Bool
    var canReadStorageNow: Bool
    var canWriteStorageNow: Bool
    var canDispatchStorageChangeEventNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

enum ChromeMV3StorageBrokerPersistenceMode:
    Equatable,
    Sendable
{
    case hostBacked(rootURL: URL)
    case inMemory
}

struct ChromeMV3StorageBroker:
    Equatable,
    Sendable
{
    var namespace: ChromeMV3StorageNamespace
    var areaRecord: ChromeMV3StorageAreaRecord
    var persistenceMode: ChromeMV3StorageBrokerPersistenceMode
    private(set) var snapshot: ChromeMV3StorageSnapshot

    init(
        namespace: ChromeMV3StorageNamespace,
        persistenceMode: ChromeMV3StorageBrokerPersistenceMode = .inMemory,
        initialValues: [String: ChromeMV3StorageValue] = [:],
        unlimitedStoragePermissionPresent: Bool = false
    ) {
        self.namespace = namespace
        self.areaRecord = ChromeMV3StorageAreaRecord.make(
            area: namespace.area,
            extensionID: namespace.extensionID,
            profileID: namespace.profileID,
            unlimitedStoragePermissionPresent:
                unlimitedStoragePermissionPresent
        )
        self.persistenceMode = persistenceMode
        self.snapshot = ChromeMV3StorageSnapshot(
            namespace: namespace,
            values: initialValues
        )
    }

    @discardableResult
    mutating func loadHostSnapshotIfPresent(
        fileManager: FileManager = .default
    ) throws -> Bool {
        guard let url = snapshotURL else { return false }
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let data = try Data(contentsOf: url)
        let loaded = try JSONDecoder().decode(
            ChromeMV3StorageSnapshot.self,
            from: data
        )
        guard loaded.namespace == namespace else {
            throw ChromeMV3StorageBrokerFailure.snapshotNamespaceMismatch
        }
        snapshot = ChromeMV3StorageSnapshot(
            namespace: namespace,
            values: loaded.values
        )
        return true
    }

    mutating func get(
        keys: [String]
    ) -> ChromeMV3StorageOperationResult {
        guard areaRecord.readAllowedByModel else {
            return blockedResult(operation: .get)
        }
        let selectedKeys = Array(Set(keys)).sorted()
        let values = Dictionary(uniqueKeysWithValues: selectedKeys.compactMap {
            key in
            snapshot.values[key].map { (key, $0) }
        })
        return result(
            operation: .get,
            succeeded: true,
            returnedValues: values,
            bytesInUse: nil,
            oldValues: snapshot.values,
            newValues: snapshot.values,
            errors: []
        )
    }

    mutating func getAll() -> ChromeMV3StorageOperationResult {
        guard areaRecord.readAllowedByModel else {
            return blockedResult(operation: .getAll)
        }
        return result(
            operation: .getAll,
            succeeded: true,
            returnedValues: snapshot.values,
            bytesInUse: nil,
            oldValues: snapshot.values,
            newValues: snapshot.values,
            errors: []
        )
    }

    mutating func set(
        _ values: [String: ChromeMV3StorageValue],
        fileManager: FileManager = .default
    ) -> ChromeMV3StorageOperationResult {
        guard areaRecord.writeAllowedByModel else {
            return blockedResult(operation: .set)
        }

        let validationErrors = storageValueErrors(values)
        guard validationErrors.isEmpty else {
            return result(
                operation: .set,
                succeeded: false,
                returnedValues: [:],
                bytesInUse: nil,
                oldValues: snapshot.values,
                newValues: snapshot.values,
                errors: validationErrors
            )
        }

        let oldValues = snapshot.values
        var newValues = oldValues
        for key in values.keys.sorted() {
            newValues[key] = values[key]
        }
        let quota = evaluateQuota(values: newValues)
        guard quota.withinQuota else {
            return result(
                operation: .set,
                succeeded: false,
                returnedValues: [:],
                bytesInUse: nil,
                oldValues: oldValues,
                newValues: oldValues,
                quotaEvaluation: quota,
                errors: quota.errorDiagnostics
            )
        }

        snapshot = ChromeMV3StorageSnapshot(
            namespace: namespace,
            values: newValues
        )
        do {
            try persistIfNeeded(fileManager: fileManager)
        } catch {
            snapshot = ChromeMV3StorageSnapshot(
                namespace: namespace,
                values: oldValues
            )
            return result(
                operation: .set,
                succeeded: false,
                returnedValues: [:],
                bytesInUse: nil,
                oldValues: oldValues,
                newValues: oldValues,
                errors: [
                    errorDiagnostic(
                        code: .storageRuntimeNotImplemented,
                        key: nil,
                        message:
                            "Host-backed storage snapshot could not be written: \(error.localizedDescription)"
                    ),
                ]
            )
        }

        return result(
            operation: .set,
            succeeded: true,
            returnedValues: [:],
            bytesInUse: nil,
            oldValues: oldValues,
            newValues: newValues,
            quotaEvaluation: quota,
            errors: []
        )
    }

    mutating func remove(
        keys: [String],
        fileManager: FileManager = .default
    ) -> ChromeMV3StorageOperationResult {
        guard areaRecord.writeAllowedByModel else {
            return blockedResult(operation: .remove)
        }
        let oldValues = snapshot.values
        var newValues = oldValues
        for key in Array(Set(keys)).sorted() {
            newValues.removeValue(forKey: key)
        }
        snapshot = ChromeMV3StorageSnapshot(
            namespace: namespace,
            values: newValues
        )
        do {
            try persistIfNeeded(fileManager: fileManager)
        } catch {
            snapshot = ChromeMV3StorageSnapshot(
                namespace: namespace,
                values: oldValues
            )
            return result(
                operation: .remove,
                succeeded: false,
                returnedValues: [:],
                bytesInUse: nil,
                oldValues: oldValues,
                newValues: oldValues,
                errors: [
                    errorDiagnostic(
                        code: .storageRuntimeNotImplemented,
                        key: nil,
                        message:
                            "Host-backed storage snapshot could not be written: \(error.localizedDescription)"
                    ),
                ]
            )
        }
        return result(
            operation: .remove,
            succeeded: true,
            returnedValues: [:],
            bytesInUse: nil,
            oldValues: oldValues,
            newValues: newValues,
            errors: []
        )
    }

    mutating func clear(
        fileManager: FileManager = .default
    ) -> ChromeMV3StorageOperationResult {
        guard areaRecord.writeAllowedByModel else {
            return blockedResult(operation: .clear)
        }
        let oldValues = snapshot.values
        snapshot = ChromeMV3StorageSnapshot(namespace: namespace)
        do {
            try persistIfNeeded(fileManager: fileManager)
        } catch {
            snapshot = ChromeMV3StorageSnapshot(
                namespace: namespace,
                values: oldValues
            )
            return result(
                operation: .clear,
                succeeded: false,
                returnedValues: [:],
                bytesInUse: nil,
                oldValues: oldValues,
                newValues: oldValues,
                errors: [
                    errorDiagnostic(
                        code: .storageRuntimeNotImplemented,
                        key: nil,
                        message:
                            "Host-backed storage snapshot could not be written: \(error.localizedDescription)"
                    ),
                ]
            )
        }
        return result(
            operation: .clear,
            succeeded: true,
            returnedValues: [:],
            bytesInUse: nil,
            oldValues: oldValues,
            newValues: [:],
            errors: []
        )
    }

    mutating func getBytesInUse(
        keys: [String]? = nil
    ) -> ChromeMV3StorageOperationResult {
        guard areaRecord.readAllowedByModel else {
            return blockedResult(operation: .getBytesInUse)
        }
        let bytes = ChromeMV3StorageByteCounter.totalBytes(
            values: selectedValues(keys: keys)
        )
        return result(
            operation: .getBytesInUse,
            succeeded: true,
            returnedValues: [:],
            bytesInUse: bytes,
            oldValues: snapshot.values,
            newValues: snapshot.values,
            errors: []
        )
    }

    func exportSnapshot() -> ChromeMV3StorageSnapshot {
        snapshot
    }

    mutating func importSnapshot(
        _ importedSnapshot: ChromeMV3StorageSnapshot,
        fileManager: FileManager = .default
    ) -> ChromeMV3StorageOperationResult {
        guard importedSnapshot.namespace == namespace else {
            let error = errorDiagnostic(
                code: .snapshotNamespaceMismatch,
                key: nil,
                message:
                    "Imported storage snapshot namespace does not match the broker namespace."
            )
            return result(
                operation: .importSnapshot,
                succeeded: false,
                returnedValues: [:],
                bytesInUse: nil,
                oldValues: snapshot.values,
                newValues: snapshot.values,
                errors: [error]
            )
        }
        guard areaRecord.writeAllowedByModel else {
            return blockedResult(operation: .importSnapshot)
        }
        let oldValues = snapshot.values
        let newValues = importedSnapshot.values
        let quota = evaluateQuota(values: newValues)
        guard quota.withinQuota else {
            return result(
                operation: .importSnapshot,
                succeeded: false,
                returnedValues: [:],
                bytesInUse: nil,
                oldValues: oldValues,
                newValues: oldValues,
                quotaEvaluation: quota,
                errors: quota.errorDiagnostics
            )
        }
        snapshot = ChromeMV3StorageSnapshot(
            namespace: namespace,
            values: newValues
        )
        do {
            try persistIfNeeded(fileManager: fileManager)
        } catch {
            snapshot = ChromeMV3StorageSnapshot(
                namespace: namespace,
                values: oldValues
            )
            return result(
                operation: .importSnapshot,
                succeeded: false,
                returnedValues: [:],
                bytesInUse: nil,
                oldValues: oldValues,
                newValues: oldValues,
                errors: [
                    errorDiagnostic(
                        code: .storageRuntimeNotImplemented,
                        key: nil,
                        message:
                            "Host-backed storage snapshot could not be written: \(error.localizedDescription)"
                    ),
                ]
            )
        }
        return result(
            operation: .importSnapshot,
            succeeded: true,
            returnedValues: [:],
            bytesInUse: nil,
            oldValues: oldValues,
            newValues: newValues,
            quotaEvaluation: quota,
            errors: []
        )
    }

    var snapshotURL: URL? {
        guard case .hostBacked(let rootURL) = persistenceMode,
              namespace.area == .local
        else { return nil }
        return namespace.relativePathComponents.reduce(
            rootURL.standardizedFileURL
        ) { url, component in
            url.appendingPathComponent(component, isDirectory: true)
        }.appendingPathComponent("storage-snapshot.json")
    }

    private func selectedValues(
        keys: [String]?
    ) -> [String: ChromeMV3StorageValue] {
        guard let keys else { return snapshot.values }
        return Dictionary(uniqueKeysWithValues: Array(Set(keys)).sorted()
            .compactMap { key in
                snapshot.values[key].map { (key, $0) }
            })
    }

    private func storageValueErrors(
        _ values: [String: ChromeMV3StorageValue]
    ) -> [ChromeMV3StorageErrorDiagnostic] {
        values.keys.sorted().flatMap { key in
            (values[key]?.validationDiagnostics ?? []).map { diagnostic in
                errorDiagnostic(
                    code: diagnostic.code,
                    key: key,
                    message: diagnostic.message
                )
            }
        }
    }

    private func evaluateQuota(
        values: [String: ChromeMV3StorageValue]
    ) -> ChromeMV3StorageQuotaEvaluation {
        ChromeMV3StorageByteCounter.evaluate(
            values: values,
            policy: areaRecord.quotaPolicy
        )
    }

    private func persistIfNeeded(fileManager: FileManager) throws {
        guard let url = snapshotURL else { return }
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ChromeMV3DeterministicJSON.write(snapshot, to: url)
    }

    private func blockedResult(
        operation: ChromeMV3StorageOperationKind
    ) -> ChromeMV3StorageOperationResult {
        let message =
            "\(namespace.area.chromeAreaName) storage is not available for modeled \(operation.rawValue) operations."
        let error = errorDiagnostic(
            code: .readOnlyOrUnsupportedArea,
            key: nil,
            message: message
        )
        return result(
            operation: operation,
            succeeded: false,
            returnedValues: [:],
            bytesInUse: nil,
            oldValues: snapshot.values,
            newValues: snapshot.values,
            errors: [error]
        )
    }

    private func result(
        operation: ChromeMV3StorageOperationKind,
        succeeded: Bool,
        returnedValues: [String: ChromeMV3StorageValue],
        bytesInUse: Int?,
        oldValues: [String: ChromeMV3StorageValue],
        newValues: [String: ChromeMV3StorageValue],
        quotaEvaluation: ChromeMV3StorageQuotaEvaluation? = nil,
        errors: [ChromeMV3StorageErrorDiagnostic]
    ) -> ChromeMV3StorageOperationResult {
        let quotaEvaluation = quotaEvaluation ?? evaluateQuota(
            values: snapshot.values
        )
        let changeSet = ChromeMV3StorageChangeSet.make(
            namespace: namespace,
            oldValues: oldValues,
            newValues: newValues
        )
        return ChromeMV3StorageOperationResult(
            operation: operation,
            namespace: namespace,
            areaRecord: areaRecord,
            succeeded: succeeded,
            brokerModelOperationsAvailable:
                areaRecord.readAllowedByModel || areaRecord.writeAllowedByModel,
            returnedValues: Dictionary(
                uniqueKeysWithValues: returnedValues.keys.sorted().map {
                    ($0, returnedValues[$0] ?? .null)
                }
            ),
            bytesInUse: bytesInUse,
            quotaEvaluation: quotaEvaluation,
            changeSet: changeSet,
            errorDiagnostics: errors.sorted {
                if $0.code != $1.code {
                    return $0.code < $1.code
                }
                return ($0.key ?? "") < ($1.key ?? "")
            },
            runtimeImplementedNow: false,
            canReadStorageNow: false,
            canWriteStorageNow: false,
            canDispatchStorageChangeEventNow: false,
            canWakeServiceWorkerNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            diagnostics: [
                "Broker model operation evaluated deterministically.",
                "chrome.storage JavaScript API exposure remains blocked.",
                "storage.onChanged event dispatch remains blocked.",
                "Service-worker wake remains blocked.",
                "Context loading remains blocked.",
                "runtimeLoadable remains false.",
            ]
        )
    }

    private func errorDiagnostic(
        code: ChromeMV3StorageErrorCode,
        key: String?,
        message: String
    ) -> ChromeMV3StorageErrorDiagnostic {
        ChromeMV3StorageErrorDiagnostic(
            code: code,
            area: namespace.area,
            key: key,
            message: message,
            wouldSetRuntimeLastError: true,
            wouldRejectPromise: true,
            runtimeImplementedNow: false
        )
    }
}

enum ChromeMV3StorageBrokerFailure: Error, Equatable {
    case snapshotNamespaceMismatch
}

struct ChromeMV3StorageOperationContractCoverage:
    Codable,
    Equatable,
    Sendable
{
    var area: ChromeMV3StorageAreaKind
    var operation: ChromeMV3StorageOperationKind
    var modeled: Bool
    var brokerModelOperationsAvailable: Bool
    var readAllowedByModel: Bool
    var writeAllowedByModel: Bool
    var runtimeImplementedNow: Bool
    var canReadStorageNow: Bool
    var canWriteStorageNow: Bool
    var canDispatchStorageChangeEventNow: Bool
    var canWakeServiceWorkerNow: Bool
    var diagnostics: [String]
}

struct ChromeMV3StorageSessionPolicySummary:
    Codable,
    Equatable,
    Sendable
{
    var persistencePolicy: ChromeMV3StoragePersistencePolicy
    var workerUnloadReloadExpectation: String
    var profileSessionCleanupPolicy: String
    var extensionDisableCleanupPolicy: String
    var accessLevelDefault: ChromeMV3StorageContentScriptAccessDefault
    var runtimeImplementedNow: Bool
    var diagnostics: [String]
}

struct ChromeMV3StorageBrokerNamespaceSummary:
    Codable,
    Equatable,
    Sendable
{
    var profileID: String
    var extensionID: String
    var namespaceIDs: [String]
    var areas: [ChromeMV3StorageAreaKind]
    var profileIsolated: Bool
    var activeRuntimeHandleOpened: Bool
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerStorageReadinessSummary:
    Codable,
    Equatable,
    Sendable
{
    var storagePermissionDetected: Bool
    var storageLocalModelAvailable: Bool
    var storageSessionPolicyAvailable: Bool
    var storageSyncPolicy: ChromeMV3StorageSyncSupportPolicy
    var unlockFillStateStorageRequirements: [String]
    var workerUnloadReloadStorageRequirement: String
    var storageEventDispatchAvailable: Bool
    var runtimeMessagingStillBlocked: Bool
    var nativeMessagingStillBlocked: Bool
    var passwordManagerStorageReady: Bool
    var blockers: [String]
}

struct ChromeMV3StorageBrokerReadinessReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var modeledAreas: [ChromeMV3StorageAreaKind]
    var storageLocalModelAvailable: Bool
    var storageSessionModelAvailable: Bool
    var storageSyncPolicy: ChromeMV3StorageSyncSupportPolicy
    var brokerModelOperationsAvailable: Bool
    var canReadStorageNow: Bool
    var canWriteStorageNow: Bool
    var canDispatchStorageChangeEventNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var passwordManagerStorageReady: Bool
}

struct ChromeMV3StorageBrokerReadinessReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var extensionID: String
    var profileID: String
    var storagePermissionDetected: Bool
    var storageAreaSupportSummary: [ChromeMV3StorageAreaRecord]
    var localPolicy: ChromeMV3StorageAreaRecord
    var sessionPolicy: ChromeMV3StorageSessionPolicySummary
    var syncPolicy: ChromeMV3StorageSyncPolicy
    var brokerNamespaceSummary: ChromeMV3StorageBrokerNamespaceSummary
    var operationContractCoverage: [ChromeMV3StorageOperationContractCoverage]
    var quotaErrorDiagnostics: [ChromeMV3StorageErrorDiagnostic]
    var changeEventContractCoverage: [ChromeMV3StorageOnChangedEventPayload]
    var passwordManagerStorageSummary:
        ChromeMV3PasswordManagerStorageReadinessSummary
    var canReadStorageNow: Bool
    var canWriteStorageNow: Bool
    var brokerModelOperationsAvailable: Bool
    var canDispatchStorageChangeEventNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var documentationSources: [ChromeMV3ManifestRewritePreviewSource]
    var diagnostics: [String]
    var blockers: [String]

    var summary: ChromeMV3StorageBrokerReadinessReportSummary {
        ChromeMV3StorageBrokerReadinessReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            modeledAreas: storageAreaSupportSummary.map(\.area).sorted(),
            storageLocalModelAvailable:
                localPolicy.availabilityStatus == .brokerModelAvailable,
            storageSessionModelAvailable:
                storageAreaSupportSummary.contains {
                    $0.area == .session
                        && $0.availabilityStatus == .brokerModelAvailable
                },
            storageSyncPolicy: syncPolicy.status,
            brokerModelOperationsAvailable: brokerModelOperationsAvailable,
            canReadStorageNow: false,
            canWriteStorageNow: false,
            canDispatchStorageChangeEventNow: false,
            canWakeServiceWorkerNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            passwordManagerStorageReady:
                passwordManagerStorageSummary.passwordManagerStorageReady
        )
    }
}

enum ChromeMV3StorageBrokerReadinessReportWriter {
    static let reportFileName = "runtime-storage-broker-readiness-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3StorageBrokerReadinessReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3StorageBrokerReadinessReport {
        guard directoryExists(rootURL.standardizedFileURL) else {
            return report
        }
        try ChromeMV3DeterministicJSON.write(
            report,
            to: rootURL.standardizedFileURL
                .appendingPathComponent(Self.reportFileName)
        )
        return report
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}

enum ChromeMV3StorageBrokerReadinessReportGenerator {
    static func makeReport(
        prerequisitesReport prerequisites:
            ChromeMV3RuntimeBridgePrerequisitesReport,
        profileID: String = "diagnostic-profile"
    ) -> ChromeMV3StorageBrokerReadinessReport {
        makeReport(
            extensionID: prerequisites.candidateID,
            profileID: profileID,
            storagePermissionDetected:
                prerequisites.manifestFacts.storagePermissionPresent
                    || prerequisites.passwordManagerPrerequisiteSummary
                    .storagePermissionPresent,
            passwordManagerLikeFixtureDetected:
                prerequisites.passwordManagerPrerequisiteSummary
                .contentScriptsPresent
                    || prerequisites.passwordManagerPrerequisiteSummary
                    .actionPopupPresent
                    || prerequisites.passwordManagerPrerequisiteSummary
                    .nativeMessagingPermissionPresent,
            runtimeMessagingStillBlocked: true,
            nativeMessagingStillBlocked:
                prerequisites.nativeMessagingPrerequisites
                .nativeMessagingBlocked
        )
    }

    static func makeReport(
        extensionID: String,
        profileID: String,
        storagePermissionDetected: Bool,
        passwordManagerLikeFixtureDetected: Bool = false,
        runtimeMessagingStillBlocked: Bool = true,
        nativeMessagingStillBlocked: Bool = true
    ) -> ChromeMV3StorageBrokerReadinessReport {
        let records = ChromeMV3StorageAreaKind.allCases.sorted().map {
            ChromeMV3StorageAreaRecord.make(
                area: $0,
                extensionID: extensionID,
                profileID: profileID
            )
        }
        let local = records.first { $0.area == .local }
            ?? ChromeMV3StorageAreaRecord.make(
                area: .local,
                extensionID: extensionID,
                profileID: profileID
            )
        let session = sessionPolicy(
            records.first { $0.area == .session }
        )
        let namespaceSummary = namespaceSummary(
            records: records,
            extensionID: extensionID,
            profileID: profileID
        )
        let operationCoverage = operationCoverage(records: records)
        let eventCoverage = records
            .filter { $0.area == .local || $0.area == .session }
            .map { record in
                ChromeMV3StorageChangeSet.make(
                    namespace: ChromeMV3StorageNamespace(
                        profileID: record.profileID,
                        extensionID: record.extensionID,
                        area: record.area
                    ),
                    oldValues: [
                        "example": .string("old"),
                    ],
                    newValues: [
                        "example": .string("new"),
                    ]
                ).futureOnChangedPayload
            }
            .sorted { $0.areaName < $1.areaName }
        let quotaDiagnostics = quotaDiagnostics(records: records)
        let password = passwordSummary(
            storagePermissionDetected: storagePermissionDetected,
            passwordManagerLikeFixtureDetected:
                passwordManagerLikeFixtureDetected,
            runtimeMessagingStillBlocked: runtimeMessagingStillBlocked,
            nativeMessagingStillBlocked: nativeMessagingStillBlocked
        )
        let blockers = uniqueSorted(
            [
                "chrome.storage JavaScript API calls remain blocked.",
                "storage.onChanged listener registration and dispatch remain blocked.",
                "Service-worker wake remains blocked.",
                "Context loading remains blocked.",
                "runtimeLoadable remains false.",
            ] + password.blockers
        )
        let reportID = ChromeMV3StorageStableID.make(
            prefix: "runtime-storage-broker-readiness",
            components: [
                profileID,
                extensionID,
                storagePermissionDetected.description,
                passwordManagerLikeFixtureDetected.description,
            ]
        )

        return ChromeMV3StorageBrokerReadinessReport(
            schemaVersion: 1,
            id: reportID,
            reportFileName:
                ChromeMV3StorageBrokerReadinessReportWriter.reportFileName,
            extensionID: extensionID.isEmpty
                ? "unknown-extension"
                : extensionID,
            profileID: profileID.isEmpty ? "unknown-profile" : profileID,
            storagePermissionDetected: storagePermissionDetected,
            storageAreaSupportSummary: records,
            localPolicy: local,
            sessionPolicy: session,
            syncPolicy: .conservativeV1,
            brokerNamespaceSummary: namespaceSummary,
            operationContractCoverage: operationCoverage,
            quotaErrorDiagnostics: quotaDiagnostics,
            changeEventContractCoverage: eventCoverage,
            passwordManagerStorageSummary: password,
            canReadStorageNow: false,
            canWriteStorageNow: false,
            brokerModelOperationsAvailable: true,
            canDispatchStorageChangeEventNow: false,
            canWakeServiceWorkerNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            documentationSources: documentationSources(),
            diagnostics: [
                "storage.local model exists and can be exercised by host-side tests.",
                "storage.session model exists and can be exercised by host-side tests.",
                "storage.sync is deferred as a local-only future-emulation policy decision.",
                "storage.managed is unsupported.",
                "Broker namespaces include profile id, extension id, and storage area.",
                "No active extension storage runtime handle is opened.",
            ],
            blockers: blockers
        )
    }

    static func makeReport(
        loadingPrerequisitesReportFrom rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> ChromeMV3StorageBrokerReadinessReport {
        let reportURL = rootURL.standardizedFileURL
            .appendingPathComponent(
                ChromeMV3RuntimeBridgePrerequisitesReportWriter
                    .reportFileName
            )
        let data = try Data(contentsOf: reportURL)
        let prerequisites = try JSONDecoder().decode(
            ChromeMV3RuntimeBridgePrerequisitesReport.self,
            from: data
        )
        _ = fileManager
        return makeReport(prerequisitesReport: prerequisites)
    }

    private static func sessionPolicy(
        _ record: ChromeMV3StorageAreaRecord?
    ) -> ChromeMV3StorageSessionPolicySummary {
        ChromeMV3StorageSessionPolicySummary(
            persistencePolicy:
                record?.persistencePolicy ?? .memoryOnlyExtensionSession,
            workerUnloadReloadExpectation:
                "Modeled session values survive service-worker idle unload/reload because this layer has no worker; they do not survive extension disable, reload, update, profile session cleanup, or browser restart.",
            profileSessionCleanupPolicy:
                "Clear session storage when the profile session closes or a test imports an empty session snapshot.",
            extensionDisableCleanupPolicy:
                "Clear session storage on extension disable, reload, update, or uninstall before any future runtime handle is exposed.",
            accessLevelDefault:
                record?.contentScriptAccessDefault ?? .notExposedByDefault,
            runtimeImplementedNow: false,
            diagnostics: [
                "storage.session is memory-only in this foundation.",
                "No service-worker lifecycle object is created.",
                "No content-script access level is applied at runtime.",
            ]
        )
    }

    private static func namespaceSummary(
        records: [ChromeMV3StorageAreaRecord],
        extensionID: String,
        profileID: String
    ) -> ChromeMV3StorageBrokerNamespaceSummary {
        let namespaces = records.map {
            ChromeMV3StorageNamespace(
                profileID: profileID,
                extensionID: extensionID,
                area: $0.area
            )
        }
        return ChromeMV3StorageBrokerNamespaceSummary(
            profileID: profileID.isEmpty ? "unknown-profile" : profileID,
            extensionID: extensionID.isEmpty
                ? "unknown-extension"
                : extensionID,
            namespaceIDs: namespaces.map(\.namespaceID).sorted(),
            areas: records.map(\.area).sorted(),
            profileIsolated: records.allSatisfy(\.profileIsolated),
            activeRuntimeHandleOpened: false,
            diagnostics: [
                "Every broker namespace is keyed by profile id, extension id, and storage area.",
                "Disabled extensions do not receive an active storage runtime handle.",
            ]
        )
    }

    private static func operationCoverage(
        records: [ChromeMV3StorageAreaRecord]
    ) -> [ChromeMV3StorageOperationContractCoverage] {
        records.flatMap { record in
            ChromeMV3StorageOperationKind.allCases.sorted().map { operation in
                let readOperation: Bool
                switch operation {
                case .get, .getAll, .getBytesInUse, .exportSnapshot:
                    readOperation = true
                case .clear, .importSnapshot, .remove, .set:
                    readOperation = false
                }
                let available = readOperation
                    ? record.readAllowedByModel
                    : record.writeAllowedByModel
                return ChromeMV3StorageOperationContractCoverage(
                    area: record.area,
                    operation: operation,
                    modeled: true,
                    brokerModelOperationsAvailable: available,
                    readAllowedByModel: record.readAllowedByModel,
                    writeAllowedByModel: record.writeAllowedByModel,
                    runtimeImplementedNow: false,
                    canReadStorageNow: false,
                    canWriteStorageNow: false,
                    canDispatchStorageChangeEventNow: false,
                    canWakeServiceWorkerNow: false,
                    diagnostics: record.diagnostics
                )
            }
        }.sorted {
            if $0.area != $1.area {
                return $0.area < $1.area
            }
            return $0.operation < $1.operation
        }
    }

    private static func quotaDiagnostics(
        records: [ChromeMV3StorageAreaRecord]
    ) -> [ChromeMV3StorageErrorDiagnostic] {
        records.flatMap { record -> [ChromeMV3StorageErrorDiagnostic] in
            var diagnostics: [ChromeMV3StorageErrorDiagnostic] = []
            if let quotaBytes = record.quotaPolicy.quotaBytes {
                diagnostics.append(
                    ChromeMV3StorageErrorDiagnostic(
                        code: .quotaBytesExceeded,
                        area: record.area,
                        key: nil,
                        message:
                            "Would report quota failure above \(quotaBytes) modeled bytes for \(record.area.chromeAreaName).",
                        wouldSetRuntimeLastError: true,
                        wouldRejectPromise: true,
                        runtimeImplementedNow: false
                    )
                )
            }
            if let perItem = record.quotaPolicy.quotaBytesPerItem {
                diagnostics.append(
                    ChromeMV3StorageErrorDiagnostic(
                        code: .quotaBytesPerItemExceeded,
                        area: record.area,
                        key: nil,
                        message:
                            "Would report per-item quota failure above \(perItem) modeled bytes for \(record.area.chromeAreaName).",
                        wouldSetRuntimeLastError: true,
                        wouldRejectPromise: true,
                        runtimeImplementedNow: false
                    )
                )
            }
            if let maxItems = record.quotaPolicy.maxItems {
                diagnostics.append(
                    ChromeMV3StorageErrorDiagnostic(
                        code: .maxItemsExceeded,
                        area: record.area,
                        key: nil,
                        message:
                            "Would report max item quota failure above \(maxItems) keys for \(record.area.chromeAreaName).",
                        wouldSetRuntimeLastError: true,
                        wouldRejectPromise: true,
                        runtimeImplementedNow: false
                    )
                )
            }
            if record.readAllowedByModel == false
                && record.writeAllowedByModel == false
            {
                diagnostics.append(
                    ChromeMV3StorageErrorDiagnostic(
                        code: .readOnlyOrUnsupportedArea,
                        area: record.area,
                        key: nil,
                        message:
                            "\(record.area.chromeAreaName) is not available for broker operations in this foundation.",
                        wouldSetRuntimeLastError: true,
                        wouldRejectPromise: true,
                        runtimeImplementedNow: false
                    )
                )
            }
            return diagnostics
        }.sorted {
            if $0.area != $1.area {
                return $0.area < $1.area
            }
            return $0.code < $1.code
        }
    }

    private static func passwordSummary(
        storagePermissionDetected: Bool,
        passwordManagerLikeFixtureDetected: Bool,
        runtimeMessagingStillBlocked: Bool,
        nativeMessagingStillBlocked: Bool
    ) -> ChromeMV3PasswordManagerStorageReadinessSummary {
        let blockers = uniqueSorted(
            [
                runtimeMessagingStillBlocked
                    ? "Runtime messaging remains blocked."
                    : nil,
                nativeMessagingStillBlocked
                    ? "Native messaging remains blocked."
                    : nil,
                "storage.onChanged dispatch is not available.",
                "chrome.storage is not exposed to JavaScript.",
                "Context loading remains blocked.",
                "Password-manager storage readiness remains false until runtime dispatch, context, and event delivery exist.",
            ].compactMap { $0 }
        )
        return ChromeMV3PasswordManagerStorageReadinessSummary(
            storagePermissionDetected: storagePermissionDetected,
            storageLocalModelAvailable: true,
            storageSessionPolicyAvailable: true,
            storageSyncPolicy:
                ChromeMV3StorageSyncPolicy.conservativeV1.status,
            unlockFillStateStorageRequirements: [
                "Persistent storage.local state for extension vault metadata, settings, and durable unlock diagnostics.",
                "Volatile storage.session state for in-browser unlock/fill flow coordination.",
                "Explicit storage.sync fallback behavior before any extension assumes synced state.",
            ],
            workerUnloadReloadStorageRequirement:
                "State needed after service-worker unload must live in modeled storage rather than worker globals.",
            storageEventDispatchAvailable: false,
            runtimeMessagingStillBlocked: runtimeMessagingStillBlocked,
            nativeMessagingStillBlocked: nativeMessagingStillBlocked,
            passwordManagerStorageReady: false,
            blockers: passwordManagerLikeFixtureDetected
                ? blockers
                : uniqueSorted([
                    "No password-manager-like fixture was detected, but storage remains non-executing.",
                ] + blockers)
        )
    }

    private static func documentationSources()
        -> [ChromeMV3ManifestRewritePreviewSource]
    {
        [
            ChromeMV3ManifestRewritePreviewSource(
                kind: .chromeDocumentation,
                title: "Chrome storage API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/storage",
                note:
                    "Defines storage.local, storage.session, storage.sync, get, set, remove, clear, getBytesInUse, onChanged, quotas, access levels, and service-worker persistence guidance."
            ),
            ChromeMV3ManifestRewritePreviewSource(
                kind: .chromeDocumentation,
                title: "Chrome extension service-worker lifecycle",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle",
                note:
                    "Defines service-worker idle behavior and guidance to persist state rather than relying on globals."
            ),
            ChromeMV3ManifestRewritePreviewSource(
                kind: .currentSumiCode,
                title: "Sumi Chrome MV3 runtime readiness contracts",
                url: nil,
                note:
                    "Runtime messaging, listener delivery, context loading, and service-worker wake remain blocked by existing diagnostics."
            ),
        ]
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

private enum ChromeMV3StorageByteCounter {
    static func totalBytes(
        values: [String: ChromeMV3StorageValue]
    ) -> Int {
        values.keys.sorted().reduce(0) { total, key in
            total + key.utf8.count + (values[key]?.deterministicByteCount ?? 0)
        }
    }

    static func evaluate(
        values: [String: ChromeMV3StorageValue],
        policy: ChromeMV3StorageQuotaPolicy
    ) -> ChromeMV3StorageQuotaEvaluation {
        let itemUsage = values.keys.sorted().map { key in
            ChromeMV3StorageItemByteUsage(
                key: key,
                bytes: key.utf8.count
                    + (values[key]?.deterministicByteCount ?? 0)
            )
        }
        let total = itemUsage.reduce(0) { $0 + $1.bytes }
        var errors: [ChromeMV3StorageErrorDiagnostic] = []
        if let quotaBytes = policy.quotaBytes, total > quotaBytes {
            errors.append(
                error(
                    code: .quotaBytesExceeded,
                    area: policy.area,
                    key: nil,
                    message:
                        "Modeled storage bytes \(total) exceed quota \(quotaBytes)."
                )
            )
        }
        if let quotaBytesPerItem = policy.quotaBytesPerItem {
            for item in itemUsage where item.bytes > quotaBytesPerItem {
                errors.append(
                    error(
                        code: .quotaBytesPerItemExceeded,
                        area: policy.area,
                        key: item.key,
                        message:
                            "Modeled item bytes \(item.bytes) exceed per-item quota \(quotaBytesPerItem)."
                    )
                )
            }
        }
        if let maxItems = policy.maxItems, values.count > maxItems {
            errors.append(
                error(
                    code: .maxItemsExceeded,
                    area: policy.area,
                    key: nil,
                    message:
                        "Modeled item count \(values.count) exceeds max items \(maxItems)."
                )
            )
        }
        return ChromeMV3StorageQuotaEvaluation(
            area: policy.area,
            totalBytes: total,
            quotaBytes: policy.quotaBytes,
            quotaBytesPerItem: policy.quotaBytesPerItem,
            maxItems: policy.maxItems,
            itemByteUsage: itemUsage,
            withinQuota: errors.isEmpty,
            errorDiagnostics: errors.sorted {
                if $0.code != $1.code {
                    return $0.code < $1.code
                }
                return ($0.key ?? "") < ($1.key ?? "")
            }
        )
    }

    private static func error(
        code: ChromeMV3StorageErrorCode,
        area: ChromeMV3StorageAreaKind,
        key: String?,
        message: String
    ) -> ChromeMV3StorageErrorDiagnostic {
        ChromeMV3StorageErrorDiagnostic(
            code: code,
            area: area,
            key: key,
            message: message,
            wouldSetRuntimeLastError: true,
            wouldRejectPromise: true,
            runtimeImplementedNow: false
        )
    }
}

private enum ChromeMV3StorageStableID {
    static func make(prefix: String, components: [String]) -> String {
        let seed = ([prefix] + components).joined(separator: "|")
        return "\(prefix)-\(sha256Hex(Data(seed.utf8)).prefix(32))"
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
