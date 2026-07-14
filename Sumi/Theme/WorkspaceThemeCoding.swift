import Foundation
import SumiDomain

extension WorkspaceTheme {
    var encoded: Data? {
        do {
            return try JSONEncoder().encode(self)
        } catch {
            RuntimeDiagnostics.debug(
                "WorkspaceTheme encoding failed: \(error)",
                category: "WorkspaceTheme"
            )
            return nil
        }
    }

    static func decode(_ data: Data) -> WorkspaceTheme? {
        guard !data.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(WorkspaceTheme.self, from: data)
        } catch {
            RuntimeDiagnostics.debug(
                "WorkspaceTheme decoding failed: \(error)",
                category: "WorkspaceTheme"
            )
            return nil
        }
    }
}
