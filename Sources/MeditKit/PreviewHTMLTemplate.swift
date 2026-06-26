import Foundation

/// Wraps an HTML body (from `MarkdownHTMLRenderer`) in a full document with the
/// preview's CSS. The CSS — not custom layout code — provides tables that grow to
/// content, cap at the viewport, and scroll horizontally (`overflow-x: auto`)
/// without ever splitting words; symmetric inline-code chips; code-block panels;
/// blockquote bars; headings; and light/dark theming. This is what makes the
/// preview behave like every other Markdown viewer (which all use a web view).
public enum PreviewHTMLTemplate {
    // CBB brand colors come straight from CBBColors (single source of truth) —
    // steel = table header band + inline-code text, blue = header text.
    private static let steel = CBBColors.steel.cssHex
    private static let blue = CBBColors.blue.cssHex

    public static func htmlDocument(body: String, isDark: Bool) -> String {
        let bg        = isDark ? "#1e1e1e" : "#ffffff"
        let fg        = isDark ? "#e6e6e6" : "#1a1a1a"
        let secondary = isDark ? "#9aa0a6" : "#5f6368"
        let border    = isDark ? "rgba(255,255,255,0.16)" : "rgba(0,0,0,0.14)"
        let codeBg    = isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.05)"
        let panelBg   = isDark ? "rgba(255,255,255,0.05)" : "rgba(0,0,0,0.035)"
        let quoteBar  = isDark ? "rgba(255,255,255,0.25)" : "rgba(0,0,0,0.2)"
        let linkColor = isDark ? "#6cb6ff" : "#0a66c2"
        let headColor = isDark ? "#7fb6ff" : "#0a2f66"

        let css = """
        html, body { margin: 0; padding: 0; }
        body {
          background: \(bg);
          color: \(fg);
          font: 15px -apple-system, "SF Pro Text", system-ui, sans-serif;
          line-height: 1.55;
          padding: 20px 24px;
          -webkit-text-size-adjust: 100%;
        }
        a { color: \(linkColor); }
        h1, h2, h3, h4, h5, h6 { color: \(headColor); line-height: 1.25; margin: 1.2em 0 0.5em; }
        h1 { font-size: 1.8em; border-bottom: 1px solid \(border); padding-bottom: .25em; }
        h2 { font-size: 1.45em; border-bottom: 1px solid \(border); padding-bottom: .2em; }
        h3 { font-size: 1.2em; }
        p { margin: 0.6em 0; }
        hr { border: none; border-top: 1px solid \(border); margin: 1.4em 0; }

        /* Inline code: a tight, vertically-symmetric chip (the browser centers it). */
        code {
          font-family: "SF Mono", ui-monospace, Menlo, monospace;
          font-size: 0.88em;
          background: \(codeBg);
          color: \(steel);
          border-radius: 4px;
          padding: 1px 5px;
        }
        /* Code block panel: its own horizontal scroll, no chip styling inside. */
        pre {
          background: \(panelBg);
          border-radius: 6px;
          padding: 10px 12px;
          overflow-x: auto;
        }
        pre code { background: none; color: \(fg); padding: 0; font-size: 0.85em; }

        blockquote {
          margin: 0.8em 0;
          padding: 0.2em 1em;
          border-left: 3px solid \(quoteBar);
          color: \(secondary);
        }

        ul, ol { padding-left: 1.6em; }
        li.task { list-style: none; margin-left: -1.2em; }

        .img-alt { color: \(secondary); font-style: italic; }

        /* Tables — the whole point of moving to a web view.
           The wrapper scrolls horizontally; the table grows to its content width but
           caps at the viewport (then the wrapper scrolls). Words never split. */
        .table-wrap { overflow-x: auto; margin: 1em 0; }
        table {
          border-collapse: collapse;
          width: max-content;
          max-width: 100%;
        }
        th, td {
          border: 1px solid \(border);
          padding: 6px 10px;
          text-align: left;
          vertical-align: top;
          white-space: normal;
        }
        thead th {
          background: \(steel);
          color: \(blue);
          font-weight: 600;
          text-align: center;
        }
        thead th code, thead th { white-space: nowrap; }
        """

        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style></head>
        <body>
        \(body)
        </body></html>
        """
    }

    /// App-injected JavaScript (run via `evaluateJavaScript` after each full shell
    /// load) that maps the standard navigation keys to document scrolling.
    ///
    /// Page-level/content JavaScript is disabled for security, so the preview shell
    /// itself carries no scripts; WebKit's built-in key scrolling for a
    /// `loadHTMLString` document is unreliable. The app injects this handler — which
    /// is NOT "content JS" — so Home/End, ⌃Home/⌃End, and PageUp/PageDown scroll the
    /// preview the way they do in the editor. Idempotent: a guard flag keeps repeated
    /// injection (one per full reload) from stacking listeners.
    public static let scrollKeyHandlerJS = """
    (function () {
      if (window.__meditScrollKeys) { return; }
      window.__meditScrollKeys = true;
      document.addEventListener('keydown', function (e) {
        if (e.metaKey || e.altKey) { return; }
        var el = document.scrollingElement || document.documentElement;
        var page = Math.max(40, window.innerHeight * 0.9);
        switch (e.key) {
          case 'Home':
            window.scrollTo({ top: 0 }); break;
          case 'End':
            window.scrollTo({ top: el.scrollHeight }); break;
          case 'PageUp':
            window.scrollBy({ top: -page }); break;
          case 'PageDown':
            window.scrollBy({ top: page }); break;
          default:
            return;
        }
        e.preventDefault();
      }, false);
    })();
    """
}
