import Foundation
import WebKit

@MainActor
enum SumiReaderModeService {
    enum ReaderError: Error {
        case unavailable
        case extractionFailed
    }

    static func toggleReaderMode(on webView: WKWebView, tab: Tab?) async throws {
        if try await isReaderModeActive(on: webView) {
            webView.reload()
            return
        }

        guard let sourceURL = webView.url ?? tab?.url,
              sourceURL.isSumiReaderEligibleURL
        else {
            throw ReaderError.unavailable
        }

        guard let article = try await extractArticle(from: webView) else {
            throw ReaderError.extractionFailed
        }

        let html = readerHTML(for: article, sourceURL: sourceURL)
        try await write(html, into: webView)

        tab?.name = article.title
    }

    private static func isReaderModeActive(on webView: WKWebView) async throws -> Bool {
        let value = try await webView.evaluateJavaScript("""
            document.documentElement.dataset.sumiReaderMode === "true"
        """)
        return (value as? Bool) == true
    }

    private static func extractArticle(from webView: WKWebView) async throws -> Article? {
        let value = try await webView.evaluateJavaScript(extractorScript)
        guard let payload = value as? [String: Any] else { return nil }
        guard let title = payload["title"] as? String,
              let contentHTML = payload["contentHTML"] as? String,
              let excerpt = payload["excerpt"] as? String,
              let siteName = payload["siteName"] as? String,
              let byline = payload["byline"] as? String,
              let publishedTime = payload["publishedTime"] as? String,
              let textLength = payload["textLength"] as? NSNumber,
              textLength.intValue >= 600
        else {
            return nil
        }

        return Article(
            title: title,
            contentHTML: contentHTML,
            excerpt: excerpt,
            siteName: siteName,
            byline: byline,
            publishedTime: publishedTime
        )
    }

    private static func write(_ html: String, into webView: WKWebView) async throws {
        let data = try JSONSerialization.data(withJSONObject: [html], options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            throw ReaderError.extractionFailed
        }
        let script = """
            (() => {
              const html = \(json)[0];
              document.open();
              document.write(html);
              document.close();
            })();
        """
        _ = try await webView.evaluateJavaScript(script)
    }

    private static func readerHTML(for article: Article, sourceURL: URL) -> String {
        let source = escaped(sourceURL.absoluteString)
        let title = escaped(article.title)
        let siteName = escaped(article.siteName)
        let byline = escaped(article.byline)
        let publishedTime = escaped(article.publishedTime)
        let excerpt = escaped(article.excerpt)
        let metadata = [byline, publishedTime]
            .filter { !$0.isEmpty }
            .joined(separator: " - ")

        return """
        <!doctype html>
        <html lang="\(escaped(article.language))" data-sumi-reader-mode="true">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src http: https: data: blob:; media-src http: https: data: blob:; style-src 'unsafe-inline'; font-src data:;">
        <title>\(title)</title>
        <style>
        :root {
          color-scheme: light dark;
          --reader-bg: Canvas;
          --reader-text: color-mix(in srgb, CanvasText 92%, transparent);
          --reader-secondary: color-mix(in srgb, CanvasText 58%, transparent);
          --reader-rule: color-mix(in srgb, CanvasText 14%, transparent);
          --reader-link: LinkText;
          --reader-width: 720px;
        }
        * { box-sizing: border-box; }
        html { background: var(--reader-bg); }
        body {
          margin: 0;
          background: var(--reader-bg);
          color: var(--reader-text);
          font: 19px/1.62 ui-serif, "New York", "Iowan Old Style", Georgia, serif;
          text-rendering: optimizeLegibility;
          -webkit-font-smoothing: antialiased;
        }
        main {
          width: min(var(--reader-width), calc(100vw - 48px));
          margin: 0 auto;
          padding: clamp(42px, 8vh, 84px) 0 72px;
        }
        header {
          border-bottom: 1px solid var(--reader-rule);
          margin-bottom: 32px;
          padding-bottom: 24px;
        }
        .site {
          color: var(--reader-secondary);
          font: 600 12px/1.3 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          letter-spacing: 0;
          text-transform: uppercase;
          margin-bottom: 12px;
        }
        h1 {
          color: var(--reader-text);
          font: 700 clamp(34px, 5vw, 48px)/1.08 -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
          letter-spacing: 0;
          margin: 0;
        }
        .meta {
          color: var(--reader-secondary);
          font: 13px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          margin-top: 14px;
        }
        .excerpt {
          color: var(--reader-secondary);
          font: 18px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          margin: 18px 0 0;
        }
        article :is(h2, h3) {
          color: var(--reader-text);
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
          letter-spacing: 0;
          line-height: 1.2;
          margin: 1.65em 0 .55em;
        }
        article h2 { font-size: 1.45em; }
        article h3 { font-size: 1.18em; }
        p, ul, ol, blockquote, pre, figure { margin: 1.05em 0; }
        ul, ol { padding-left: 1.35em; }
        li + li { margin-top: .35em; }
        a { color: var(--reader-link); text-decoration-thickness: .06em; text-underline-offset: .16em; }
        blockquote {
          border-left: 3px solid var(--reader-rule);
          color: var(--reader-secondary);
          padding-left: 1em;
        }
        img, video {
          display: block;
          max-width: 100%;
          height: auto;
          border-radius: 8px;
          margin: 1.25em auto;
        }
        figcaption {
          color: var(--reader-secondary);
          font: 13px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          text-align: center;
          margin-top: -0.65em;
        }
        pre {
          overflow-x: auto;
          padding: 14px 16px;
          border-radius: 8px;
          background: color-mix(in srgb, CanvasText 8%, Canvas);
          font: 14px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace;
        }
        code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .88em; }
        .source {
          border-top: 1px solid var(--reader-rule);
          color: var(--reader-secondary);
          display: block;
          font: 13px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          margin-top: 42px;
          padding-top: 18px;
          overflow-wrap: anywhere;
        }
        @media (max-width: 680px) {
          body { font-size: 18px; }
          main { width: min(100vw - 32px, var(--reader-width)); padding-top: 34px; }
        }
        </style>
        </head>
        <body>
        <main>
          <header>
            \(siteName.isEmpty ? "" : "<div class=\"site\">\(siteName)</div>")
            <h1>\(title)</h1>
            \(metadata.isEmpty ? "" : "<div class=\"meta\">\(metadata)</div>")
            \(excerpt.isEmpty ? "" : "<p class=\"excerpt\">\(excerpt)</p>")
          </header>
          <article>
          \(article.contentHTML)
          </article>
          <a class="source" href="\(source)">\(source)</a>
        </main>
        </body>
        </html>
        """
    }

    private static func escaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private struct Article {
        let title: String
        let contentHTML: String
        let excerpt: String
        let siteName: String
        let byline: String
        let publishedTime: String

        let language = "en"
    }

    private static let extractorScript = #"""
    (() => {
      if (!/^text\/html\b/i.test(document.contentType || "")) return null;

      const blockedSelector = [
        "script", "style", "noscript", "template", "svg", "canvas",
        "nav", "aside", "form", "footer", "header[role=banner]",
        "[role=complementary]", "[role=navigation]", "[aria-hidden=true]",
        ".ad", ".ads", ".advertisement", ".promo", ".social", ".share",
        ".comments", "#comments", ".newsletter", ".subscribe", ".related"
      ].join(",");
      const positivePattern = /article|body|content|entry|hentry|main|page|post|story|text/i;
      const negativePattern = /ad|banner|breadcrumb|comment|combx|community|disqus|extra|foot|header|menu|meta|nav|promo|related|remark|rss|share|shoutbox|sidebar|sponsor|subscribe|tag|tool|widget/i;

      function text(el) {
        return (el && el.textContent || "").replace(/\s+/g, " ").trim();
      }

      function attr(el, name) {
        return (el && el.getAttribute(name) || "").trim();
      }

      function absolutize(value) {
        try { return new URL(value, document.baseURI).href; } catch (_) { return ""; }
      }

      function linkDensity(el) {
        const total = text(el).length;
        if (!total) return 1;
        let linkText = 0;
        for (const link of el.querySelectorAll("a")) linkText += text(link).length;
        return linkText / total;
      }

      function scoreNode(el) {
        const paragraphs = Array.from(el.querySelectorAll("p, li, blockquote"));
        let score = 0;
        let length = 0;
        for (const p of paragraphs) {
          const t = text(p);
          if (t.length < 45) continue;
          length += t.length;
          score += Math.min(160, t.length);
          score += (t.match(/[.!?;:]/g) || []).length * 12;
        }
        const name = `${el.id || ""} ${el.className || ""}`;
        if (positivePattern.test(name)) score *= 1.25;
        if (negativePattern.test(name)) score *= 0.55;
        score *= Math.max(0.1, 1 - linkDensity(el));
        score += Math.min(280, length / 12);
        return { score, length };
      }

      const clone = document.body ? document.body.cloneNode(true) : null;
      if (!clone) return null;
      for (const node of clone.querySelectorAll(blockedSelector)) node.remove();

      const candidates = [
        ...clone.querySelectorAll("article, main, [role=main], .article, .post, .entry, .content, .story"),
        clone
      ];
      let best = null;
      for (const candidate of candidates) {
        const scored = scoreNode(candidate);
        if (!best || scored.score > best.score) best = { node: candidate, ...scored };
      }
      if (!best || best.length < 600 || best.score < 450) return null;

      const allowed = new Set(["A", "P", "BR", "H1", "H2", "H3", "H4", "UL", "OL", "LI", "BLOCKQUOTE", "PRE", "CODE", "STRONG", "B", "EM", "I", "FIGURE", "FIGCAPTION", "IMG", "PICTURE", "SOURCE", "VIDEO"]);
      const blockTags = new Set(["P", "H1", "H2", "H3", "H4", "UL", "OL", "LI", "BLOCKQUOTE", "PRE", "FIGURE"]);

      function clean(node) {
        if (node.nodeType === Node.TEXT_NODE) return document.createTextNode(node.nodeValue);
        if (node.nodeType !== Node.ELEMENT_NODE) return document.createDocumentFragment();

        let tag = node.tagName;
        if (tag === "DIV" || tag === "SECTION") {
          const fragment = document.createDocumentFragment();
          for (const child of node.childNodes) fragment.appendChild(clean(child));
          return fragment;
        }
        if (!allowed.has(tag)) return document.createDocumentFragment();

        const out = document.createElement(tag.toLowerCase());
        if (tag === "A") {
          const href = absolutize(attr(node, "href"));
          if (href && /^(https?|mailto):/i.test(href)) out.setAttribute("href", href);
        } else if (tag === "IMG") {
          const src = absolutize(attr(node, "src") || attr(node, "data-src") || attr(node, "data-original") || attr(node, "data-lazy-src"));
          if (!src) return document.createDocumentFragment();
          out.setAttribute("src", src);
          out.setAttribute("loading", "lazy");
          const alt = attr(node, "alt");
          if (alt) out.setAttribute("alt", alt.slice(0, 240));
        } else if (tag === "SOURCE") {
          const srcset = attr(node, "srcset");
          if (srcset) out.setAttribute("srcset", srcset);
          const type = attr(node, "type");
          if (type) out.setAttribute("type", type);
        } else if (tag === "VIDEO") {
          const src = absolutize(attr(node, "src"));
          if (src) out.setAttribute("src", src);
          out.setAttribute("controls", "");
          out.setAttribute("preload", "metadata");
        }

        for (const child of node.childNodes) out.appendChild(clean(child));
        if (blockTags.has(tag) && text(out).length < 2 && !out.querySelector("img,video")) {
          return document.createDocumentFragment();
        }
        return out;
      }

      const article = document.createElement("article");
      for (const child of best.node.childNodes) article.appendChild(clean(child));

      const title =
        text(document.querySelector("article h1, main h1, h1")) ||
        attr(document.querySelector("meta[property='og:title'], meta[name='twitter:title']"), "content") ||
        document.title.replace(/\s+[-|]\s+.*$/, "").trim();
      const byline =
        attr(document.querySelector("meta[name=author], meta[property='article:author']"), "content") ||
        text(document.querySelector("[rel=author], .byline, .author"));
      const publishedTime =
        attr(document.querySelector("meta[property='article:published_time'], meta[name='date'], time[datetime]"), "content") ||
        attr(document.querySelector("time[datetime]"), "datetime") ||
        text(document.querySelector("time"));
      const siteName =
        attr(document.querySelector("meta[property='og:site_name']"), "content") ||
        location.hostname.replace(/^www\./, "");
      const excerpt =
        attr(document.querySelector("meta[name=description], meta[property='og:description']"), "content");

      return {
        title: title || document.title || location.hostname,
        contentHTML: article.innerHTML,
        excerpt,
        siteName,
        byline,
        publishedTime,
        textLength: text(article).length
      };
    })();
    """#
}

private extension URL {
    var isSumiReaderEligibleURL: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
