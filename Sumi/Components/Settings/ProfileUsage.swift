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

    var spacesText: String {
        spaces == 1 ? "1 space" : "\(spaces) spaces"
    }

    var tabsText: String {
        tabs == 1 ? "1 tab" : "\(tabs) tabs"
    }
}
