//
//  ProfileRetirementEntity.swift
//  Sumi
//

import Foundation
import SwiftData

@Model
final class ProfileRetirementEntity {
    @Attribute(.unique) var profileID: UUID
    var profileName: String
    var profileIcon: String
    var profileIndex: Int
    var fallbackProfileID: UUID
    var generation: UUID
    var phaseRawValue: String
    var nextCleanupStepRawValue: String

    init(
        profileID: UUID,
        profileName: String,
        profileIcon: String,
        profileIndex: Int,
        fallbackProfileID: UUID,
        generation: UUID,
        phase: ProfileRetirementPhase,
        nextCleanupStep: ProfileRetirementCleanupStep
    ) {
        self.profileID = profileID
        self.profileName = profileName
        self.profileIcon = profileIcon
        self.profileIndex = profileIndex
        self.fallbackProfileID = fallbackProfileID
        self.generation = generation
        self.phaseRawValue = phase.rawValue
        self.nextCleanupStepRawValue = nextCleanupStep.rawValue
    }
}
