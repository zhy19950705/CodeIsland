import SwiftUI

// Preview colors follow the host appearance so the markdown sheet feels native inside both light and dark settings windows.
enum SkillMarkdownTheme {
    case light
    case dark

    init(colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }

    var styleSheet: String {
        """
        :root {
            color-scheme: \(colorSchemeCSSValue);
            --bg: \(background);
            --text: \(text);
            --muted: \(muted);
            --muted-strong: \(mutedStrong);
            --code-bg: \(codeBackground);
            --code-border: \(codeBorder);
            --accent: \(accent);
            --accent-soft: \(accentSoft);
            --rule: \(rule);
            --table-border: \(tableBorder);
            --surface: \(surface);
            --surface-strong: \(surfaceStrong);
            --shadow: \(shadow);
            --button-text: \(buttonText);
            --selection: \(selection);
            --heading: \(heading);
            --code-text: \(codeText);
            --quote-bg: \(quoteBackground);
            --token-keyword: \(tokenKeyword);
            --token-type: \(tokenType);
            --token-string: \(tokenString);
            --token-number: \(tokenNumber);
            --token-comment: \(tokenComment);
            --token-operator: \(tokenOperator);
        }

        * { box-sizing: border-box; }

        body {
            margin: 0;
            padding: 22px 22px 34px;
            background:
                radial-gradient(circle at top left, \(glow), transparent 28%),
                linear-gradient(180deg, \(surfaceStrong), rgba(255, 255, 255, 0.00)),
                var(--bg);
            color: var(--text);
            font: 15px/1.78 -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", sans-serif;
            text-rendering: optimizeLegibility;
            -webkit-font-smoothing: antialiased;
        }

        ::selection {
            background: var(--selection);
        }

        .markdown-body {
            max-width: 940px;
            margin: 0 auto;
            word-break: break-word;
        }

        h1, h2, h3, h4, h5, h6 {
            margin: 1.65em 0 0.5em;
            line-height: 1.2;
            font-weight: 760;
            letter-spacing: -0.03em;
            color: var(--heading);
            scroll-margin-top: 16px;
        }

        h1 {
            margin-top: 0.2em;
            font-size: 2.15rem;
        }
        h2 {
            font-size: 1.55rem;
            padding-bottom: 0.4em;
            border-bottom: 1px solid var(--rule);
        }
        h3 { font-size: 1.24rem; }
        h4, h5, h6 {
            font-size: 1rem;
            letter-spacing: -0.01em;
        }

        p, ul, ol, pre, table, blockquote {
            margin: 0 0 1.1em;
        }

        p {
            color: var(--text);
        }

        p + p {
            margin-top: -0.15em;
        }

        ul, ol {
            padding-left: 1.55em;
        }

        li + li {
            margin-top: 0.42em;
        }

        li > p {
            margin-bottom: 0.55em;
        }

        code {
            padding: 0.16em 0.42em;
            border-radius: 7px;
            background: var(--accent-soft);
            color: var(--accent);
            font: 0.9em/1.45 "SF Mono", SFMono-Regular, ui-monospace, monospace;
        }

        .code-block {
            margin: 1.15em 0 1.35em;
            border-radius: 14px;
            border: 1px solid var(--code-border);
            background: linear-gradient(180deg, var(--surfaceStrong), rgba(255, 255, 255, 0.00)), var(--code-bg);
            overflow: hidden;
            box-shadow: 0 14px 32px var(--shadow);
        }

        .code-toolbar {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 12px;
            padding: 9px 12px;
            border-bottom: 1px solid var(--code-border);
            background: var(--surfaceStrong);
        }

        .code-language {
            font: 11px/1.2 "SF Mono", SFMono-Regular, ui-monospace, monospace;
            letter-spacing: 0.08em;
            text-transform: uppercase;
            color: var(--muted-strong);
        }

        .copy-button {
            border: 1px solid var(--code-border);
            border-radius: 999px;
            background: var(--surface);
            color: var(--button-text);
            font: 12px/1.2 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            padding: 6px 10px;
            cursor: pointer;
            transition: background 140ms ease, color 140ms ease, border-color 140ms ease;
        }

        .copy-button:hover {
            background: var(--accent-soft);
            color: var(--accent);
        }

        pre {
            overflow-x: auto;
            margin: 0;
            padding: 16px 18px 18px;
        }

        pre code {
            padding: 0;
            background: transparent;
            border-radius: 0;
            color: var(--code-text);
            font-size: 0.92em;
            white-space: pre;
            display: block;
        }

        .table-scroll {
            overflow-x: auto;
            margin: 1.2em 0 1.3em;
            border-radius: 14px;
            border: 1px solid var(--table-border);
            box-shadow:
                inset 18px 0 18px -18px var(--shadow),
                inset -18px 0 18px -18px var(--shadow);
            background: var(--surface);
        }

        table {
            width: 100%;
            min-width: max-content;
            border-collapse: collapse;
            margin: 0;
            background: transparent;
            font-size: 0.96rem;
        }

        thead {
            background: var(--surfaceStrong);
        }

        th, td {
            padding: 12px 14px;
            text-align: left;
            vertical-align: top;
            border-bottom: 1px solid var(--table-border);
        }

        th {
            position: sticky;
            top: 0;
            z-index: 1;
            color: var(--heading);
            font-weight: 650;
        }

        tr:last-child td {
            border-bottom: none;
        }

        blockquote {
            margin-left: 0;
            padding: 0.55em 0.95em 0.6em 1.05em;
            border-left: 3px solid var(--accent);
            color: var(--muted-strong);
            background: var(--quote-bg);
            border-radius: 0 12px 12px 0;
        }

        a {
            color: var(--accent);
            text-decoration: underline;
            text-decoration-color: var(--rule);
            text-underline-offset: 0.15em;
        }

        a:hover {
            text-decoration-color: var(--accent);
        }

        hr {
            border: 0;
            border-top: 1px solid var(--rule);
            margin: 1.9em 0;
        }

        .markdown-fallback {
            border-radius: 14px;
            border: 1px solid var(--code-border);
            background: var(--code-bg);
            box-shadow: 0 14px 32px var(--shadow);
        }

        .token-keyword {
            color: var(--token-keyword);
            font-weight: 620;
        }

        .token-type {
            color: var(--token-type);
        }

        .token-string {
            color: var(--token-string);
        }

        .token-number {
            color: var(--token-number);
        }

        .token-comment {
            color: var(--token-comment);
            font-style: italic;
        }

        .token-operator {
            color: var(--token-operator);
        }

        .empty {
            color: var(--muted);
        }
        """
    }

    private var colorSchemeCSSValue: String {
        self == .dark ? "dark" : "light"
    }

    private var background: String {
        self == .dark ? "#0f1324" : "#f6f8ff"
    }

    private var text: String {
        self == .dark ? "#edf1ff" : "#162033"
    }

    private var muted: String {
        self == .dark ? "#a7b1d9" : "#5f6b85"
    }

    private var mutedStrong: String {
        self == .dark ? "#c0c8eb" : "#4a5770"
    }

    private var codeBackground: String {
        self == .dark ? "#0a1020" : "#eef3ff"
    }

    private var codeBorder: String {
        self == .dark ? "rgba(157, 172, 255, 0.12)" : "rgba(86, 108, 169, 0.14)"
    }

    private var accent: String {
        self == .dark ? "#8ab4ff" : "#2f6fed"
    }

    private var accentSoft: String {
        self == .dark ? "rgba(138, 180, 255, 0.12)" : "rgba(47, 111, 237, 0.10)"
    }

    private var rule: String {
        self == .dark ? "rgba(157, 172, 255, 0.12)" : "rgba(86, 108, 169, 0.16)"
    }

    private var tableBorder: String {
        self == .dark ? "rgba(157, 172, 255, 0.14)" : "rgba(86, 108, 169, 0.16)"
    }

    private var surface: String {
        self == .dark ? "rgba(255, 255, 255, 0.02)" : "rgba(255, 255, 255, 0.86)"
    }

    private var surfaceStrong: String {
        self == .dark ? "rgba(255, 255, 255, 0.04)" : "rgba(255, 255, 255, 0.94)"
    }

    private var shadow: String {
        self == .dark ? "rgba(7, 12, 26, 0.34)" : "rgba(58, 77, 122, 0.14)"
    }

    private var buttonText: String {
        self == .dark ? "#dfe8ff" : "#26427a"
    }

    private var selection: String {
        self == .dark ? "rgba(115, 154, 255, 0.24)" : "rgba(76, 124, 255, 0.20)"
    }

    private var heading: String {
        self == .dark ? "#f6f8ff" : "#0f1b33"
    }

    private var codeText: String {
        self == .dark ? "#dfe7ff" : "#18315f"
    }

    private var quoteBackground: String {
        self == .dark ? "rgba(255, 255, 255, 0.03)" : "rgba(255, 255, 255, 0.78)"
    }

    private var tokenKeyword: String {
        self == .dark ? "#8ab4ff" : "#315fdb"
    }

    private var tokenType: String {
        self == .dark ? "#8fe1c2" : "#0b8a63"
    }

    private var tokenString: String {
        self == .dark ? "#f7c97b" : "#b86a00"
    }

    private var tokenNumber: String {
        self == .dark ? "#ff9e9e" : "#c24646"
    }

    private var tokenComment: String {
        self == .dark ? "#7f89af" : "#7280a5"
    }

    private var tokenOperator: String {
        self == .dark ? "#d4dcff" : "#3f4e74"
    }

    private var glow: String {
        self == .dark ? "rgba(90, 120, 255, 0.10)" : "rgba(74, 128, 255, 0.12)"
    }
}
