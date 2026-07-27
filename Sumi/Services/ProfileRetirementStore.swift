//
//  ProfileRetirementStore.swift
//  Sumi
//

import Foundation

enum ProfileRetirementPhase: String, CaseIterable, Sendable {
    case reserved
    case migratingReferences
    case logicallyDeleted
    case cleaning
    case retired
}

enum ProfileRetirementCleanupStep: String, CaseIterable, Sendable {
    case websiteData
    case applicationData
    case favicons
    case permissions
    case visitedLinks
    case persistentDataStore
    case completed

    static let ordered: [Self] = [
        .websiteData,
        .applicationData,
        .favicons,
        .permissions,
        .visitedLinks,
        .persistentDataStore,
    ]

    fileprivate var successor: Self? {
        switch self {
        case .websiteData: .applicationData
        case .applicationData: .favicons
        case .favicons: .permissions
        case .permissions: .visitedLinks
        case .visitedLinks: .persistentDataStore
        case .persistentDataStore: .completed
        case .completed: nil
        }
    }
}

struct ProfileRetirementToken: Equatable, Hashable, Sendable {
    let profileID: UUID
    let generation: UUID

    fileprivate init(profileID: UUID, generation: UUID) {
        self.profileID = profileID
        self.generation = generation
    }
}

struct ProfileRetirementSnapshot: Equatable, Sendable {
    let id: UUID
    let name: String
    let index: Int
}

struct ProfileRetirementRecord: Equatable, Sendable {
    let snapshot: ProfileRetirementSnapshot
    let fallbackProfileID: UUID
    let token: ProfileRetirementToken
    let phase: ProfileRetirementPhase
    let nextCleanupStep: ProfileRetirementCleanupStep
}

struct ProfileRetirementQuarantine: Equatable, Sendable {
    let profileID: UUID
    let fallbackProfileID: UUID
    let phaseRawValue: String
    let reason: String
}

struct ProfileRetirementStoreLoadResult: Sendable {
    let records: [ProfileRetirementRecord]
    let quarantined: [ProfileRetirementQuarantine]
}

enum ProfileRetirementStoreError: Error, Equatable {
    case fallbackMatchesRetiringProfile
    case profileNotFound(UUID)
    case fallbackProfileNotFound(UUID)
    case retirementAlreadyExists(UUID)
    case fallbackProfileIsRetiring(UUID)
    case anotherRetirementInProgress(UUID)
    case invalidPersistedPhase(UUID)
    case invalidPersistedCleanupStep(UUID)
}

@MainActor
final class ProfileRetirementStore {
    private let database: SumiDatabase

    init(database: SumiDatabase) {
        self.database = database
    }

    func records() throws -> [ProfileRetirementRecord] {
        try database.read {
            try $0.retirements.all().map(record(from:))
        }
    }

    func loadForAdmission() throws -> ProfileRetirementStoreLoadResult {
        let rows = try database.read { try $0.retirements.all() }
        var records: [ProfileRetirementRecord] = []
        var quarantined: [ProfileRetirementQuarantine] = []
        for row in rows {
            do {
                records.append(try record(from: row))
            } catch {
                quarantined.append(
                    ProfileRetirementQuarantine(
                        profileID: row.profileID,
                        fallbackProfileID: row.fallbackProfileID,
                        phaseRawValue: row.phaseRawValue,
                        reason: error.localizedDescription
                    )
                )
            }
        }
        return ProfileRetirementStoreLoadResult(
            records: records,
            quarantined: quarantined
        )
    }

    func record(for token: ProfileRetirementToken) throws -> ProfileRetirementRecord? {
        try database.read { connection in
            guard let row = try exactRow(for: token, in: connection) else {
                return nil
            }
            return try record(from: row)
        }
    }

    func reserve(
        profileID: UUID,
        fallbackProfileID: UUID,
        generation: UUID
    ) throws -> ProfileRetirementRecord {
        guard profileID != fallbackProfileID else {
            throw ProfileRetirementStoreError.fallbackMatchesRetiringProfile
        }
        return try database.transaction { connection in
            let profiles = try connection.profiles.all()
            guard let profile = profiles.first(where: { $0.id == profileID }) else {
                throw ProfileRetirementStoreError.profileNotFound(profileID)
            }
            guard profiles.contains(where: { $0.id == fallbackProfileID }) else {
                throw ProfileRetirementStoreError.fallbackProfileNotFound(fallbackProfileID)
            }

            let retirements = try connection.retirements.all()
            if retirements.contains(where: { $0.profileID == profileID }) {
                throw ProfileRetirementStoreError.retirementAlreadyExists(profileID)
            }
            if retirements.contains(where: { $0.profileID == fallbackProfileID }) {
                throw ProfileRetirementStoreError.fallbackProfileIsRetiring(fallbackProfileID)
            }
            if let active = retirements.first(where: {
                $0.phaseRawValue != ProfileRetirementPhase.retired.rawValue
            }) {
                throw ProfileRetirementStoreError.anotherRetirementInProgress(
                    active.profileID
                )
            }

            let row = ProfileRetirementRow(
                profileID: profile.id,
                profileName: profile.name,
                profileIndex: profile.index,
                fallbackProfileID: fallbackProfileID,
                generation: generation,
                phaseRawValue: ProfileRetirementPhase.reserved.rawValue,
                nextCleanupStepRawValue: ProfileRetirementCleanupStep.websiteData.rawValue
            )
            try connection.retirements.save(row)
            return try record(from: row)
        }
    }

    func beginReferenceMigration(_ token: ProfileRetirementToken) throws -> Bool {
        try update(token) { row in
            guard row.phaseRawValue == ProfileRetirementPhase.reserved.rawValue else {
                return false
            }
            row.phaseRawValue = ProfileRetirementPhase.migratingReferences.rawValue
            return true
        }
    }

    func retargetFallback(
        _ token: ProfileRetirementToken,
        to fallbackProfileID: UUID
    ) throws -> Bool {
        guard fallbackProfileID != token.profileID else { return false }
        return try database.transaction { connection in
            guard var row = try exactRow(for: token, in: connection),
                  row.phaseRawValue == ProfileRetirementPhase.migratingReferences.rawValue,
                  try connection.profiles.all().contains(where: {
                      $0.id == fallbackProfileID
                  }),
                  try connection.retirements.find(profileID: fallbackProfileID) == nil
            else {
                return false
            }
            row.fallbackProfileID = fallbackProfileID
            try connection.retirements.save(row)
            return true
        }
    }

    /// Deletes the profile, cascades its browser records, normalizes positions,
    /// and records the cleanup handoff in one database transaction.
    func commitLogicalDeletion(_ token: ProfileRetirementToken) throws -> Bool {
        try database.transaction { connection in
            guard var retirement = try exactRow(for: token, in: connection),
                  retirement.phaseRawValue
                    == ProfileRetirementPhase.migratingReferences.rawValue,
                  try connection.profiles.all().contains(where: {
                      $0.id == retirement.fallbackProfileID
                  })
            else {
                return false
            }

            try connection.profiles.delete(id: token.profileID)
            let remaining = try connection.profiles.all()
            for (index, var profile) in remaining.enumerated() {
                profile.index = index
                try connection.profiles.save(profile)
            }
            retirement.phaseRawValue = ProfileRetirementPhase.logicallyDeleted.rawValue
            try connection.retirements.save(retirement)
            return true
        }
    }

    func beginCleaning(_ token: ProfileRetirementToken) throws -> Bool {
        try update(token) { row in
            guard row.phaseRawValue
                    == ProfileRetirementPhase.logicallyDeleted.rawValue else {
                return false
            }
            row.phaseRawValue = ProfileRetirementPhase.cleaning.rawValue
            return true
        }
    }

    func completeCleanupStep(
        _ completedStep: ProfileRetirementCleanupStep,
        using token: ProfileRetirementToken
    ) throws -> Bool {
        guard completedStep != .completed,
              let nextStep = completedStep.successor
        else {
            return false
        }
        return try checkpointCleanup(nextStep: nextStep, using: token)
    }

    func checkpointCleanup(
        nextStep: ProfileRetirementCleanupStep,
        using token: ProfileRetirementToken
    ) throws -> Bool {
        try update(token) { row in
            guard row.phaseRawValue == ProfileRetirementPhase.cleaning.rawValue,
                  let currentStep = ProfileRetirementCleanupStep(
                      rawValue: row.nextCleanupStepRawValue
                  ),
                  currentStep.successor == nextStep
            else {
                return false
            }
            row.nextCleanupStepRawValue = nextStep.rawValue
            return true
        }
    }

    /// Retains a durable tombstone so old session archives and backups cannot
    /// silently regain authority for the deleted profile UUID.
    func markRetired(_ token: ProfileRetirementToken) throws -> Bool {
        try update(token) { row in
            guard row.phaseRawValue == ProfileRetirementPhase.cleaning.rawValue,
                  row.nextCleanupStepRawValue
                    == ProfileRetirementCleanupStep.completed.rawValue else {
                return false
            }
            row.phaseRawValue = ProfileRetirementPhase.retired.rawValue
            return true
        }
    }

    func cancel(_ token: ProfileRetirementToken) throws -> Bool {
        try database.transaction { connection in
            guard let row = try exactRow(for: token, in: connection),
                  row.phaseRawValue == ProfileRetirementPhase.reserved.rawValue
            else {
                return false
            }
            try connection.retirements.delete(profileID: token.profileID)
            return true
        }
    }

    private func update(
        _ token: ProfileRetirementToken,
        mutation: (inout ProfileRetirementRow) -> Bool
    ) throws -> Bool {
        try database.transaction { connection in
            guard var row = try exactRow(for: token, in: connection),
                  mutation(&row)
            else {
                return false
            }
            try connection.retirements.save(row)
            return true
        }
    }

    private func exactRow(
        for token: ProfileRetirementToken,
        in connection: SumiDatabaseConnection
    ) throws -> ProfileRetirementRow? {
        guard let row = try connection.retirements.find(profileID: token.profileID),
              row.generation == token.generation else {
            return nil
        }
        return row
    }

    private func record(from row: ProfileRetirementRow) throws -> ProfileRetirementRecord {
        guard let phase = ProfileRetirementPhase(rawValue: row.phaseRawValue) else {
            throw ProfileRetirementStoreError.invalidPersistedPhase(row.profileID)
        }
        guard let cleanupStep = ProfileRetirementCleanupStep(
            rawValue: row.nextCleanupStepRawValue
        ) else {
            throw ProfileRetirementStoreError.invalidPersistedCleanupStep(row.profileID)
        }
        return ProfileRetirementRecord(
            snapshot: ProfileRetirementSnapshot(
                id: row.profileID,
                name: row.profileName,
                index: row.profileIndex
            ),
            fallbackProfileID: row.fallbackProfileID,
            token: ProfileRetirementToken(
                profileID: row.profileID,
                generation: row.generation
            ),
            phase: phase,
            nextCleanupStep: cleanupStep
        )
    }
}
