import AppKit
import SwiftUI
import WebKit

// WebKit gives the preview proper block layout, tables, and code blocks that SwiftUI Text cannot render well.
struct SkillMarkdownPreview: NSViewRepresentable {
    let markdown: String
    let bodyHTML: String?
    let theme: SkillMarkdownTheme

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: Coordinator.copyMessageHandlerName)
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.documentEnhancementScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        context.coordinator.lastHTML = renderedDocumentHTML()
        webView.loadHTMLString(context.coordinator.lastHTML, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = renderedDocumentHTML()
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    // Structured HTML from marketplace sources should stay HTML so the preview keeps headings, lists, and code block boundaries.
    private func renderedDocumentHTML() -> String {
        if let bodyHTML, !bodyHTML.isEmpty {
            return SkillMarkdownHTMLRenderer.document(forHTML: bodyHTML, theme: theme)
        }
        return SkillMarkdownHTMLRenderer.document(for: markdown, theme: theme)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let copyMessageHandlerName = "copyCode"
        var lastHTML = ""

        // Copy code through AppKit so the feature works consistently inside the native app sandbox.
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.copyMessageHandlerName,
                  let text = message.body as? String else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        // Open links externally so preview navigation does not replace the markdown document.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    // The script stays local so markdown previews work offline while still getting copy buttons and lightweight syntax colors.
    private static let documentEnhancementScript = """
    (function() {
      function escapeHTML(text) {
        return text
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;');
      }

      function placeholderStore() {
        const values = [];
        return {
          stash(rawText, className) {
            const marker = String.fromCharCode(0xE000 + values.length);
            values.push('<span class="' + className + '">' + escapeHTML(rawText) + '</span>');
            return marker;
          },
          stashHTML(html) {
            const marker = String.fromCharCode(0xE000 + values.length);
            values.push(html);
            return marker;
          },
          restore(text) {
            return text.replace(/[\\uE000-\\uF8FF]/g, function(marker) {
              return values[marker.charCodeAt(0) - 0xE000] || '';
            });
          }
        };
      }

      function patternsFor(language) {
        const value = (language || '').toLowerCase();
        if (['python', 'py'].includes(value)) {
          return {
            comments: [/#.*$/gm],
            strings: [/"(?:\\\\.|[^"\\\\])*"/g, /'(?:\\\\.|[^'\\\\])*'/g],
            keywords: /\\b(def|class|if|elif|else|for|while|try|except|finally|return|import|from|as|with|lambda|pass|yield|raise|in|is|and|or|not|None|True|False)\\b/g
          };
        }
        if (['swift'].includes(value)) {
          return {
            comments: [/\\/\\*[\\s\\S]*?\\*\\//g, /\\/\\/.*$/gm],
            strings: [/#"(?:\\\\.|[^"\\\\])*"#/g, /"(?:\\\\.|[^"\\\\])*"/g],
            keywords: /\\b(import|let|var|func|struct|class|enum|protocol|extension|if|else|guard|for|while|switch|case|default|return|throws|throw|do|catch|try|async|await|true|false|nil)\\b/g
          };
        }
        if (['javascript', 'js', 'typescript', 'ts', 'json'].includes(value)) {
          return {
            comments: [/\\/\\*[\\s\\S]*?\\*\\//g, /\\/\\/.*$/gm],
            strings: [/`(?:\\\\.|[^`\\\\])*`/g, /"(?:\\\\.|[^"\\\\])*"/g, /'(?:\\\\.|[^'\\\\])*'/g],
            keywords: /\\b(const|let|var|function|return|if|else|for|while|switch|case|break|continue|import|from|export|class|new|extends|async|await|try|catch|finally|true|false|null|undefined|interface|type)\\b/g
          };
        }
        if (['bash', 'sh', 'shell', 'zsh'].includes(value)) {
          return {
            comments: [/#.*$/gm],
            strings: [/"(?:\\\\.|[^"\\\\])*"/g, /'(?:\\\\.|[^'\\\\])*'/g],
            keywords: /\\b(if|then|else|fi|for|do|done|case|esac|function|export|local|readonly|return|in)\\b/g
          };
        }
        if (['sql'].includes(value)) {
          return {
            comments: [/--.*$/gm],
            strings: [/"(?:\\\\.|[^"\\\\])*"/g, /'(?:\\\\.|[^'\\\\])*'/g],
            keywords: /\\b(select|from|where|join|left|right|inner|outer|on|group|by|order|limit|insert|update|delete|create|table|into|values|set|and|or|not|null|as|distinct)\\b/gi
          };
        }
        return {
          comments: [/\\/\\*[\\s\\S]*?\\*\\//g, /\\/\\/.*$/gm, /#.*$/gm],
          strings: [/`(?:\\\\.|[^`\\\\])*`/g, /"(?:\\\\.|[^"\\\\])*"/g, /'(?:\\\\.|[^'\\\\])*'/g],
          keywords: /\\b(true|false|null|nil|return|if|else|for|while|class|def|func|import|from|const|let|var)\\b/g
        };
      }

      function highlightCode(source, language) {
        const store = placeholderStore();
        const patterns = patternsFor(language);
        let working = source.replace(/\\r\\n/g, '\\n');

        patterns.comments.forEach(function(regex) {
          working = working.replace(regex, function(match) { return store.stash(match, 'token-comment'); });
        });
        patterns.strings.forEach(function(regex) {
          working = working.replace(regex, function(match) { return store.stash(match, 'token-string'); });
        });

        working = escapeHTML(working);
        working = working.replace(patterns.keywords, function(match) {
          return store.stashHTML('<span class="token-keyword">' + match + '</span>');
        });
        working = working.replace(/\\b\\d+(?:\\.\\d+)?\\b/g, function(match) {
          return store.stashHTML('<span class="token-number">' + match + '</span>');
        });
        working = working.replace(/(->|=>|==|!=|<=|>=|\\+|\\-|\\*|\\/|=)/g, function(match) {
          return store.stashHTML('<span class="token-operator">' + match + '</span>');
        });
        working = working.replace(/\\b([A-Z][A-Za-z0-9_]+)\\b/g, function(match) {
          return store.stashHTML('<span class="token-type">' + match + '</span>');
        });
        return store.restore(working);
      }

      document.querySelectorAll('.code-block code').forEach(function(code) {
        if (code.dataset.highlighted === 'true') return;
        const languageClass = Array.from(code.classList).find(function(name) { return name.indexOf('language-') === 0; }) || 'language-text';
        const language = languageClass.replace('language-', '');
        const source = code.textContent || '';
        code.innerHTML = highlightCode(source, language);
        code.dataset.highlighted = 'true';
      });

      document.addEventListener('click', function(event) {
        const button = event.target.closest('.copy-button');
        if (!button) return;
        const code = button.closest('.code-block')?.querySelector('code');
        if (!code) return;
        const text = code.textContent || '';
        window.webkit.messageHandlers.\(Coordinator.copyMessageHandlerName).postMessage(text);
        const original = button.textContent;
        button.textContent = 'Copied';
        setTimeout(function() { button.textContent = original; }, 1200);
      });
    })();
    """
}
