import Foundation
import OSLog

enum SumiBoostCSSBuilder {
    static let styleAttribute = "data-sumi-boost"
    static let filterStyleAttribute = "data-sumi-boost-filter"
    static let activeAttribute = "data-sumi-boost-active"
    private static let log = Logger.sumi(category: "Boosts")

    private enum PayloadEncodingError: LocalizedError {
        case nonUTF8Payload

        var errorDescription: String? {
            switch self {
            case .nonUTF8Payload:
                "Boost CSS payload could not be represented as UTF-8 JSON"
            }
        }
    }

    static func contentCSS(for data: SumiBoostData) -> String {
        var chunks: [String] = []

        if data.enableColorBoost {
            let background = boostBackgroundColor(for: data)
            chunks.append(
                """
                html, body {
                    background-color: \(background) !important;
                }
                """
            )
        }

        let zapCSS = data.zapSelectors
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "\($0):not([zen-zap-unhide]) { display: none !important; }" }
            .joined(separator: "\n")
        if !zapCSS.isEmpty {
            chunks.append(zapCSS)
        }

        if !data.fontFamily.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || data.textCaseOverride != .none {
            var declarations: [String] = []
            let font = data.fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
            if !font.isEmpty {
                declarations.append("font-family: '\(cssString(font))' !important;")
            }
            if data.textCaseOverride != .none {
                declarations.append("text-transform: \(data.textCaseOverride.rawValue) !important;")
            }
            chunks.append(
                """
                body *:not(.google-symbols, gf-load-icon-font, mat-icon, .google-material-icons) {
                    \(declarations.joined(separator: "\n    "))
                }
                """
            )
        }

        let customCSS = data.customCSS.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customCSS.isEmpty {
            chunks.append(customCSS)
        }

        return chunks.joined(separator: "\n\n")
    }

    static func filterCSS(for data: SumiBoostData) -> String {
        var filters: [String] = []

        if data.enableColorBoost {
            // The page accent is conveyed by the background color set in
            // contentCSS (the secondary dot color). We deliberately do NOT
            // apply a hue-rotate filter here: a global hue-rotate would also
            // shift the background and break the match between the editor
            // dots and the actual page colors. The advanced sliders only tune
            // luminance/saturation/contrast on top of the picked hue.
            let brightness = clamped(0.7 + data.brightness * 0.6, lower: 0.4, upper: 1.6)
            let saturation = clamped(data.saturation * 2, lower: 0, upper: 2.5)
            let contrast = clamped(0.5 + data.contrast, lower: 0.4, upper: 2.0)
            filters.append("brightness(\(format(brightness)))")
            filters.append("saturate(\(format(saturation)))")
            filters.append("contrast(\(format(contrast)))")
        }

        if data.smartInvert {
            filters.append("invert(1)")
            filters.append("hue-rotate(180deg)")
        }

        guard !filters.isEmpty else { return "" }

        var css = """
        html {
            filter: \(filters.joined(separator: " ")) !important;
        }
        """

        if data.smartInvert {
            css += """

            img, video, canvas, picture, iframe {
                filter: invert(1) hue-rotate(180deg) !important;
            }
            """
        }

        return css
    }

    // MARK: - Threat model: user CSS/JS string embedding into the page content world
    //
    // `installJavaScript` returns a JavaScript source string that is injected with
    // `requiresRunInPageContentWorld = true` (see `SumiBoostUserScript`), i.e. it runs
    // in the *page's own* JS realm, sharing `window`/`document` with the page's scripts
    // and any extensions the page trusts. Unlike an isolated content world, code that
    // escapes its intended data context here executes with the page's own privileges.
    // We deliberately accept that trade-off because a Boost's CSS must land in the
    // page's own CSSOM/document (author style tags, `!important` cascades against the
    // page's own rules, live `document.documentElement` attributes for `:not()` zap
    // selectors) rather than in a sandboxed shadow world the page cannot see or that
    // an isolated-world CSSStyleSheet API cannot reach on all WebKit versions.
    //
    // Attacker model: `boost.data` (customCSS, zapSelectors, fontFamily, boostId) is
    // user-authored and may also arrive via `SumiBoostExportPackage` import from an
    // untrusted file, i.e. we must treat every string field as attacker-controlled.
    // The attack we defend against is a *JS string breakout*: a crafted CSS payload
    // containing sequences like `"; maliciousCode(); "`, backslashes, quotes,
    // backtick/`${}` template syntax, or U+2028/U+2029 line separators, designed to
    // terminate the JS string literal that carries it and get arbitrary statements
    // executed in the page content world instead of merely being treated as inert
    // style text.
    //
    // Containment mechanism: `contentCSS`/`filterCSS`/`boostId` are never
    // string-interpolated directly into the generated JS. They are placed into a
    // Swift `[String: String]` and serialized once via `JSONEncoder` into `payload`,
    // which is embedded as a single JSON object literal (`const payload = <json>;`).
    // JSON string encoding is a strict subset of valid JS string literal syntax (every
    // control character, backslash, and double quote is escaped; JSON.parse-shaped
    // output is always balanced), so no payload value can close the enclosing string
    // or object literal early. The generated script then only ever *reads*
    // `payload.contentCSS` / `payload.filterCSS` as opaque string values (assigned to
    // `textContent`, never `eval`'d, never used to build a `<script>` tag or passed to
    // `innerHTML`), so even a value that looks like `</script><script>...` stays inert
    // text content instead of being reparsed as markup or code.
    //
    // Invariants this relies on (see `SumiBoostCSSBuilderTests` for coverage):
    //   1. `encodedPayloadLiteral` is the only place that turns Boost strings into JS
    //      source; every field of the payload dictionary must go through it.
    //   2. The decoded JSON payload must round-trip byte-for-byte back to the original
    //      `contentCSS`/`filterCSS`/`boostId` inputs (proves JSON escaping did not
    //      truncate or corrupt the payload while still being safe JS source).
    //   3. Evaluating the generated script must never execute attacker-supplied code
    //      or throw a syntax error, for a battery of classic JSON-into-JS breakout
    //      payloads (quotes, backslashes, U+2028/U+2029, template literals, `</script>`).
    //   4. Separately, `cssString(_:)` performs *CSS* single-quoted string escaping
    //      (backslash/quote/newline) for values embedded directly into generated CSS
    //      text (e.g. `font-family`); this is a distinct containment boundary from the
    //      JSON/JS one above and only needs to prevent breaking out of a CSS string,
    //      since CSS text itself is not executable.
    static func installJavaScript(for boost: SumiBoost) -> String {
        installJavaScript(
            boostId: boost.id.uuidString,
            contentCSS: contentCSS(for: boost.data),
            filterCSS: filterCSS(for: boost.data)
        )
    }

    static func installJavaScript(
        boostId: String,
        contentCSS: String,
        filterCSS: String
    ) -> String {
        let payload: [String: String] = [
            "boostId": boostId,
            "contentCSS": contentCSS,
            "filterCSS": filterCSS,
        ]
        let encoded = encodedPayloadLiteral(payload)

        return """
        (function() {
            const payload = \(encoded);
            function root() {
                return document.head || document.documentElement || document.body;
            }
            function upsertStyle(attributeName, cssText) {
                const existing = document.querySelector('style[' + attributeName + ']');
                if (!cssText) {
                    if (existing) existing.remove();
                    return;
                }
                const tag = existing || document.createElement('style');
                tag.setAttribute(attributeName, payload.boostId);
                if (tag.textContent !== cssText) tag.textContent = cssText;
                if (!existing) root().appendChild(tag);
            }
            upsertStyle('\(styleAttribute)', payload.contentCSS);
            upsertStyle('\(filterStyleAttribute)', payload.filterCSS);
            document.documentElement.setAttribute('\(activeAttribute)', payload.boostId);
        })();
        """
    }

    /// The sole JS-string-breakout containment boundary for Boost payloads — see the
    /// threat-model comment on `installJavaScript` above. Every attacker-controlled
    /// string that ends up embedded into the generated page-content-world script must
    /// flow through this function's `JSONEncoder`, never through raw interpolation.
    private static func encodedPayloadLiteral(_ payload: [String: String]) -> String {
        do {
            let data = try JSONEncoder().encode(payload)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw PayloadEncodingError.nonUTF8Payload
            }
            return encoded
        } catch {
            log.error("Failed to encode boost CSS payload: \(error.localizedDescription, privacy: .public)")
            return #"{"boostId":"","contentCSS":"","filterCSS":""}"#
        }
    }

    static func removalJavaScript() -> String {
        """
        (function() {
            document.querySelectorAll('style[\(styleAttribute)], style[\(filterStyleAttribute)]').forEach(function(tag) {
                tag.remove();
            });
            if (document.documentElement) {
                document.documentElement.removeAttribute('\(activeAttribute)');
            }
        })();
        """
    }

    /// CSS single-quoted string escaping boundary (distinct from the JS/JSON boundary
    /// in `encodedPayloadLiteral`): prevents attacker-controlled values such as
    /// `fontFamily` from closing the `'...'` CSS string they are embedded into. CSS
    /// text is not executable, so this only needs to preserve CSS syntax, not JS safety.
    private static func cssString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    private static func boostBackgroundColor(for data: SumiBoostData) -> String {
        let hue = normalizedDegrees(data.dotAngleDeg + data.secondaryDotAngleDegDelta)
        let saturation = clamped(data.dotDistance, lower: 0.05, upper: 1) * 100
        return "hsl(\(format(hue))deg, \(format(saturation))%, 20.000%)"
    }

    private static func clamped(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(upper, value))
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
