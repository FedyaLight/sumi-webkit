import Foundation

enum SumiWebPageMenuTextFormatter {
    static func menuSnippet(for text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        guard normalized.count > 40 else { return normalized }
        return "\(normalized.prefix(40))..."
    }

    static func textFragmentComponent(for text: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
