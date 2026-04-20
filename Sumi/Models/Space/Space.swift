//
//  Space.swift
//  Sumi
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import AppKit
import SwiftUI
 
// Gradient configuration for spaces
// See: SpaceGradient.swift

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
    var profileId: UUID?
    var profileRuntimeState: SumiProfileRuntimeState = .dormant
    
    /// Whether this space belongs to an ephemeral/incognito profile
    var isEphemeral: Bool = false

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "square.grid.2x2",
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
        self.profileId = profileId
        super.init()
    }

    var gradient: SpaceGradient {
        get { workspaceTheme.gradient }
        set { workspaceTheme.gradient = newValue }
    }
}
