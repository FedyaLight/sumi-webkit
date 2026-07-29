//
//  ProfileUsage.swift
//  Sumi
//
//  How much of the browser a single profile currently owns.
//

import Foundation

struct ProfileUsage: Equatable {
    static let none = ProfileUsage(spaces: 0, tabs: 0)

    let spaces: Int
    let tabs: Int
}

enum ProfileRetirementImpactPresentation {
    static func summary(for usage: ProfileUsage) -> String {
        switch (usage.spaces == 1, usage.tabs == 1) {
        case (true, true):
            return String(localized: "1 space - 1 tab")
        case (true, false):
            return String(localized: "1 space - \(usage.tabs) tabs")
        case (false, true):
            return String(localized: "\(usage.spaces) spaces - 1 tab")
        case (false, false):
            return String(
                localized: "\(usage.spaces) spaces - \(usage.tabs) tabs"
            )
        }
    }

    static func confirmationMessage(for usage: ProfileUsage) -> String {
        guard usage != .none else {
            return String(
                localized: "All website data stored for this profile will be permanently deleted. This action cannot be undone."
            )
        }
        switch (usage.spaces == 1, usage.tabs == 1) {
        case (true, true):
            return String(
                localized: "1 space and 1 tab that use this profile will be permanently deleted, along with all website data stored for the profile. This action cannot be undone."
            )
        case (true, false):
            return String(
                localized: "1 space and \(usage.tabs) tabs that use this profile will be permanently deleted, along with all website data stored for the profile. This action cannot be undone."
            )
        case (false, true):
            return String(
                localized: "\(usage.spaces) spaces and 1 tab that use this profile will be permanently deleted, along with all website data stored for the profile. This action cannot be undone."
            )
        case (false, false):
            return String(
                localized: "\(usage.spaces) spaces and \(usage.tabs) tabs that use this profile will be permanently deleted, along with all website data stored for the profile. This action cannot be undone."
            )
        }
    }
}
