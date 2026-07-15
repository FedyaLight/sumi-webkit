//
//  Space.swift
//  Sumi
//
//

import AppKit
import Observation
import SumiDomain
import SwiftUI

enum SumiProfileRuntimeState: String, Codable, CaseIterable {
    case dormant
    case loadedInactive
    case active
}

@MainActor
@Observable
public class Space: NSObject, Identifiable {
    public let id: UUID
    var name: String
    var icon: String
    var color: NSColor
    var workspaceTheme: WorkspaceTheme
    var activeTabId: UUID?
    @ObservationIgnored private var profileIdStorage: UUID?
    private(set) var profileId: UUID? {
        get {
            access(keyPath: \.profileId)
            return profileIdStorage
        }
        set {
            withMutation(keyPath: \.profileId) {
                profileIdStorage = newValue
            }
        }
    }
    var profileRuntimeState: SumiProfileRuntimeState = .dormant

    /// Whether this space belongs to an ephemeral/incognito profile
    var isEphemeral: Bool = false

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = SumiPersistentGlyph.spaceDefaultIconValue,
        color: NSColor = .controlAccentColor,
        workspaceTheme: WorkspaceTheme = .default,
        profileId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = SumiPersistentGlyph.normalizedSpaceIconValue(icon)
        self.color = color
        self.workspaceTheme = workspaceTheme
        self.activeTabId = nil
        profileIdStorage = profileId
        super.init()
    }

    func replaceProfileIDWithoutObservation(_ profileID: UUID?) {
        profileIdStorage = profileID
    }

    func publishCurrentProfileID() {
        withMutation(keyPath: \.profileId) {}
    }
}
