import SumiDomain

enum DefaultSpaceConfiguration {
    static let name = "Space"
    static let icon = SumiPersistentGlyph.spaceDefaultIconValue

    static func makeTheme() -> WorkspaceTheme {
        .default
    }
}
