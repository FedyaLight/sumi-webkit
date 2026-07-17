//
//  ProfileRetirementStore.swift
//  Sumi
//

import Foundation
import SwiftData

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
    let icon: String
    let index: Int
}

struct ProfileRetirementRecord: Equatable, Sendable {
    let snapshot: ProfileRetirementSnapshot
    let fallbackProfileID: UUID
    let token: ProfileRetirementToken
    let phase: ProfileRetirementPhase
    let nextCleanupStep: ProfileRetirementCleanupStep
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
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func records() throws -> [ProfileRetirementRecord] {
        try context.fetch(
            FetchDescriptor<ProfileRetirementEntity>(
                sortBy: [SortDescriptor(\.profileIndex, order: .forward)]
            )
        ).map(record(from:))
    }

    func record(for token: ProfileRetirementToken) throws -> ProfileRetirementRecord? {
        guard let entity = try exactEntity(for: token) else { return nil }
        return try record(from: entity)
    }

    func reserve(
        profileID: UUID,
        fallbackProfileID: UUID,
        generation: UUID
    ) throws -> ProfileRetirementRecord {
        guard profileID != fallbackProfileID else {
            throw ProfileRetirementStoreError.fallbackMatchesRetiringProfile
        }
        guard let profile = try profileEntity(profileID: profileID) else {
            throw ProfileRetirementStoreError.profileNotFound(profileID)
        }
        guard try profileEntity(profileID: fallbackProfileID) != nil else {
            throw ProfileRetirementStoreError.fallbackProfileNotFound(fallbackProfileID)
        }

        let retirements = try context.fetch(
            FetchDescriptor<ProfileRetirementEntity>()
        )
        if retirements.contains(where: { $0.profileID == profileID }) {
            throw ProfileRetirementStoreError.retirementAlreadyExists(profileID)
        }
        if retirements.contains(where: { $0.profileID == fallbackProfileID }) {
            throw ProfileRetirementStoreError.fallbackProfileIsRetiring(fallbackProfileID)
        }
        let activeRetirements = retirements.filter {
            $0.phaseRawValue != ProfileRetirementPhase.retired.rawValue
        }
        if let activeRetirement = activeRetirements.first {
            throw ProfileRetirementStoreError.anotherRetirementInProgress(
                activeRetirement.profileID
            )
        }

        let retirement = ProfileRetirementEntity(
            profileID: profile.id,
            profileName: profile.name,
            profileIcon: profile.icon,
            profileIndex: profile.index,
            fallbackProfileID: fallbackProfileID,
            generation: generation,
            phase: .reserved,
            nextCleanupStep: .websiteData
        )
        context.insert(retirement)
        do {
            try context.save()
            return try record(from: retirement)
        } catch {
            context.rollback()
            throw error
        }
    }

    func beginReferenceMigration(_ token: ProfileRetirementToken) throws -> Bool {
        guard let entity = try exactEntity(for: token),
              entity.phaseRawValue == ProfileRetirementPhase.reserved.rawValue
        else {
            return false
        }
        return try save {
            entity.phaseRawValue = ProfileRetirementPhase.migratingReferences.rawValue
        }
    }

    /// Deletes the migrating profile, normalizes remaining profile indices, and
    /// records the durable cleanup handoff in one ModelContext save.
    func commitLogicalDeletion(_ token: ProfileRetirementToken) throws -> Bool {
        guard let retirement = try exactEntity(for: token),
              retirement.phaseRawValue == ProfileRetirementPhase.migratingReferences.rawValue,
              let profile = try profileEntity(profileID: token.profileID),
              try profileEntity(profileID: retirement.fallbackProfileID) != nil
        else {
            return false
        }

        do {
            let remainingProfiles = try context.fetch(
                FetchDescriptor<ProfileEntity>(
                    sortBy: [SortDescriptor(\.index, order: .forward)]
                )
            ).filter { $0.id != token.profileID }
            context.delete(profile)
            for (index, remainingProfile) in remainingProfiles.enumerated() {
                remainingProfile.index = index
            }
            retirement.phaseRawValue = ProfileRetirementPhase.logicallyDeleted.rawValue
            try context.save()
            return true
        } catch {
            context.rollback()
            throw error
        }
    }

    func beginCleaning(_ token: ProfileRetirementToken) throws -> Bool {
        guard let entity = try exactEntity(for: token),
              entity.phaseRawValue == ProfileRetirementPhase.logicallyDeleted.rawValue
        else {
            return false
        }
        return try save {
            entity.phaseRawValue = ProfileRetirementPhase.cleaning.rawValue
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
        guard let entity = try exactEntity(for: token),
              entity.phaseRawValue == ProfileRetirementPhase.cleaning.rawValue,
              let currentStep = ProfileRetirementCleanupStep(
                  rawValue: entity.nextCleanupStepRawValue
              ),
              currentStep.successor == nextStep
        else {
            return false
        }
        return try save {
            entity.nextCleanupStepRawValue = nextStep.rawValue
        }
    }

    /// Retains a durable tombstone so old session archives and backups cannot
    /// silently regain authority for the deleted profile UUID.
    func markRetired(_ token: ProfileRetirementToken) throws -> Bool {
        guard let entity = try exactEntity(for: token),
              entity.phaseRawValue == ProfileRetirementPhase.cleaning.rawValue,
              entity.nextCleanupStepRawValue == ProfileRetirementCleanupStep.completed.rawValue
        else {
            return false
        }
        return try save {
            entity.phaseRawValue = ProfileRetirementPhase.retired.rawValue
        }
    }

    func cancel(_ token: ProfileRetirementToken) throws -> Bool {
        guard let entity = try exactEntity(for: token),
              entity.phaseRawValue == ProfileRetirementPhase.reserved.rawValue
        else {
            return false
        }
        do {
            context.delete(entity)
            try context.save()
            return true
        } catch {
            context.rollback()
            throw error
        }
    }

    private func save(mutation: () -> Void) throws -> Bool {
        mutation()
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            throw error
        }
    }

    private func exactEntity(
        for token: ProfileRetirementToken
    ) throws -> ProfileRetirementEntity? {
        guard let entity = try entity(profileID: token.profileID),
              entity.generation == token.generation
        else {
            return nil
        }
        return entity
    }

    private func entity(profileID: UUID) throws -> ProfileRetirementEntity? {
        let predicate = #Predicate<ProfileRetirementEntity> {
            $0.profileID == profileID
        }
        return try context.fetch(
            FetchDescriptor<ProfileRetirementEntity>(predicate: predicate)
        ).first
    }

    private func profileEntity(profileID: UUID) throws -> ProfileEntity? {
        let predicate = #Predicate<ProfileEntity> { $0.id == profileID }
        return try context.fetch(
            FetchDescriptor<ProfileEntity>(predicate: predicate)
        ).first
    }

    private func record(
        from entity: ProfileRetirementEntity
    ) throws -> ProfileRetirementRecord {
        guard let phase = ProfileRetirementPhase(rawValue: entity.phaseRawValue) else {
            throw ProfileRetirementStoreError.invalidPersistedPhase(entity.profileID)
        }
        guard let cleanupStep = ProfileRetirementCleanupStep(
            rawValue: entity.nextCleanupStepRawValue
        ) else {
            throw ProfileRetirementStoreError.invalidPersistedCleanupStep(entity.profileID)
        }
        return ProfileRetirementRecord(
            snapshot: ProfileRetirementSnapshot(
                id: entity.profileID,
                name: entity.profileName,
                icon: entity.profileIcon,
                index: entity.profileIndex
            ),
            fallbackProfileID: entity.fallbackProfileID,
            token: ProfileRetirementToken(
                profileID: entity.profileID,
                generation: entity.generation
            ),
            phase: phase,
            nextCleanupStep: cleanupStep
        )
    }
}
