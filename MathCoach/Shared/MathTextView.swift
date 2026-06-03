import SwiftUI
import WebKit

struct MathTextView: View {
    let text: String
    @State private var height: CGFloat = 44

    var body: some View {
        MathTextWebView(text: text, height: $height)
            .frame(height: max(height, 44))
    }
}

private struct MathTextWebView: UIViewRepresentable {
    let text: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context _: Context) {
        webView.loadHTMLString(html(for: normalizedText(text)), baseURL: nil)
    }

    private func html(for message: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
          <script>
            window.MathJax = {
              tex: {
                inlineMath: [['\\\\(', '\\\\)']],
                displayMath: [['\\\\[', '\\\\]']]
              },
              svg: { fontCache: 'none' }
            };
          </script>
          <script defer src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js"></script>
          <style>
            :root { color-scheme: light dark; }
            body {
              margin: 0;
              padding: 0;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
              font-size: 17px;
              line-height: 1.45;
              color: #111111;
              background: transparent;
              word-wrap: break-word;
            }
            @media (prefers-color-scheme: dark) {
              body { color: #f5f5f7; }
            }
          </style>
        </head>
        <body>\(escapeHTML(message))</body>
        </html>
        """
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\n", with: "<br/>")
    }

    private func normalizedText(_ text: String) -> String {
        var normalized = text

        // Some backend payloads arrive with one extra escaping layer such as
        // "\\n" or "\\t". Only collapse double-escaped control sequences so
        // LaTeX commands like "\neq" and "\text" remain intact.
        normalized = normalized
            .replacingOccurrences(of: "\\\\r\\\\n", with: "\n")
            .replacingOccurrences(of: "\\\\n", with: "\n")
            .replacingOccurrences(of: "\\\\r", with: "\r")
            .replacingOccurrences(of: "\\\\t", with: "\t")

        normalized = normalized.replacingOccurrences(of: "\\\\", with: "\\")
        return normalized
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: MathTextWebView

        init(parent: MathTextWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                guard let value = result as? NSNumber else {
                    return
                }
                DispatchQueue.main.async {
                    self.parent.height = CGFloat(truncating: value)
                }
            }
        }
    }
}
