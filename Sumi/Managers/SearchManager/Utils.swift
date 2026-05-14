import Foundation
import SwiftUI
import URLPredictor

struct SearchTextQuery {
  let raw: String
  let lowercase: String
  let folded: String

  init(_ text: String) {
    raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
    lowercase = raw.lowercased()
    folded = Self.normalized(raw)
  }

  var isEmpty: Bool {
    raw.isEmpty
  }

  func matches(_ text: String) -> Bool {
    let lowercasedText = text.lowercased()
    if lowercasedText.contains(lowercase) {
      return true
    }

    return Self.normalized(text).contains(folded)
  }

  static func normalized(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: .autoupdatingCurrent
    )
    .lowercased()
  }
}

func decodeSearchSuggestionEntities(_ text: String) -> String {
  guard text.contains("&") else { return text }

  var output = ""
  var index = text.startIndex

  while index < text.endIndex {
    guard text[index] == "&",
          let semicolon = text[index...].firstIndex(of: ";")
    else {
      output.append(text[index])
      index = text.index(after: index)
      continue
    }

    let entityStart = text.index(after: index)
    let entity = String(text[entityStart..<semicolon])
    if let decoded = decodeSearchSuggestionEntity(entity) {
      output.append(decoded)
      index = text.index(after: semicolon)
    } else {
      output.append(text[index])
      index = text.index(after: index)
    }
  }

  return output
}

private func decodeSearchSuggestionEntity(_ entity: String) -> Character? {
  if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
    let hexStart = entity.index(entity.startIndex, offsetBy: 2)
    guard let scalarValue = UInt32(entity[hexStart...], radix: 16),
          let scalar = UnicodeScalar(scalarValue)
    else { return nil }
    return Character(scalar)
  }

  if entity.hasPrefix("#") {
    let decimalStart = entity.index(after: entity.startIndex)
    guard let scalarValue = UInt32(entity[decimalStart...]),
          let scalar = UnicodeScalar(scalarValue)
    else { return nil }
    return Character(scalar)
  }

  switch entity {
  case "amp": return "&"
  case "quot": return "\""
  case "apos": return "'"
  case "lt": return "<"
  case "gt": return ">"
  default: return nil
  }
}

func normalizeURL(_ input: String, queryTemplate: String) -> String {
  let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

  if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ||
    trimmed.hasPrefix("file://") || trimmed.hasPrefix("about:")
  {
    return trimmed
  }

  if trimmed.lowercased().hasPrefix("sumi:") {
    return trimmed
  }

  let lowered = trimmed.lowercased()
  if lowered.hasPrefix("webkit-extension:") || lowered.hasPrefix("safari-web-extension:") {
    return trimmed
  }

  if let decision = try? Classifier.classify(input: trimmed),
     case .navigate(let url) = decision {
    return url.absoluteString
  }

  if trimmed.contains(".") && !trimmed.contains(" ") {
    return "https://\(trimmed)"
  }

  let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
  let urlString = String(format: queryTemplate, encoded)
  return urlString
}

func isLikelyURL(_ text: String) -> Bool {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  if let decision = try? Classifier.classify(input: trimmed),
     case .navigate = decision {
    return true
  }

  return trimmed.contains(".") &&
    (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ||
      trimmed.contains(".com") || trimmed.contains(".org") ||
      trimmed.contains(".net") || trimmed.contains(".io") ||
      trimmed.contains(".co") || trimmed.contains(".dev"))
}

enum SearchProvider: String, CaseIterable, Identifiable, Codable, Sendable {
  case google
  case duckDuckGo
  case bing
  case brave
  case yahoo
  case perplexity
  case unduck
  case ecosia
  case kagi

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .google: return "Google"
    case .duckDuckGo: return "DuckDuckGo"
    case .bing: return "Bing"
    case .brave: return "Brave"
    case .yahoo: return "Yahoo"
    case .perplexity: return "Perplexity"
    case .unduck: return "Unduck"
    case .ecosia: return "Ecosia"
    case .kagi: return "Kagi"
    }
  }

  var host: String {
    switch self {
    case .google: return "www.google.com"
    case .duckDuckGo: return "duckduckgo.com"
    case .bing: return "www.bing.com"
    case .brave: return "search.brave.com"
    case .yahoo: return "search.yahoo.com"
    case .perplexity: return "www.perplexity.ai"
    case .unduck: return "duckduckgo.com"
    case .ecosia: return "www.ecosia.org"
    case .kagi: return "kagi.com"
    }
  }

  var queryTemplate: String {
    switch self {
    case .google:
      return "https://www.google.com/search?q=%@"
    case .duckDuckGo:
      return "https://duckduckgo.com/?q=%@"
    case .bing:
      return "https://www.bing.com/search?q=%@"
    case .brave:
      return "https://search.brave.com/search?q=%@"
    case .yahoo:
      return "https://search.yahoo.com/search?p=%@"
    case .perplexity:
      return "https://www.perplexity.ai/search?q=%@"
    case .unduck:
      return "https://unduck.link?q=%@"
    case .ecosia:
      return "https://www.ecosia.org/search?q=%@"
    case .kagi:
      return "https://kagi.com/search?q=%@"
    }
  }
}
