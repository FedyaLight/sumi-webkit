import Foundation

extension URL {
    func sumiBookmarkButtonURLVariants() -> [URL] {
        guard let scheme = scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return [self]
        }

        let separatedScheme = "\(scheme)://"
        let baseURLString = absoluteString.replacingOccurrences(
            of: separatedScheme,
            with: "",
            options: [.anchored, .caseInsensitive]
        )
        let withoutTrailingSlash = baseURLString.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        let shouldAddTrailingSlash = query == nil && fragment == nil
        let withTrailingSlash = shouldAddTrailingSlash
            ? withoutTrailingSlash + "/"
            : withoutTrailingSlash

        let candidates: [String?] = [
            absoluteString,
            "http://\(withoutTrailingSlash)",
            "https://\(withoutTrailingSlash)",
            shouldAddTrailingSlash ? "http://\(withTrailingSlash)" : nil,
            shouldAddTrailingSlash ? "https://\(withTrailingSlash)" : nil,
        ]

        var seen = Set<String>()
        return candidates.compactMap { candidate in
            guard let candidate,
                  let url = URL(string: candidate)
            else {
                return nil
            }

            let normalized = url.absoluteString.lowercased()
            guard seen.insert(normalized).inserted else { return nil }
            return url
        }
    }
}
