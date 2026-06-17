import Foundation

enum SumiBoostCSSBuilder {
    static let styleAttribute = "data-sumi-boost"
    static let filterStyleAttribute = "data-sumi-boost-filter"
    static let activeAttribute = "data-sumi-boost-active"

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
            let hue = normalizedDegrees(data.dotAngleDeg)
            let brightness = clamped(0.7 + data.brightness * 0.6, lower: 0.4, upper: 1.6)
            let saturation = clamped(data.saturation * 2, lower: 0, upper: 2.5)
            let contrast = clamped(0.5 + data.contrast, lower: 0.4, upper: 2.0)
            filters.append("hue-rotate(\(format(hue))deg)")
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
        let encoded = (try? JSONEncoder().encode(payload))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? #"{"boostId":"","contentCSS":"","filterCSS":""}"#

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
