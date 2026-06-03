import SwiftUI
import WebKit

struct SVGLogoView: UIViewRepresentable {
    let resourceName: String
    let colorMap: [String: String]

    init(resourceName: String, colorMap: [String: String] = [:]) {
        self.resourceName = resourceName
        self.colorMap = colorMap
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context _: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isUserInteractionEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let normalizedPath = resourceName.replacingOccurrences(of: "\\", with: "/")
        let pathParts = normalizedPath.split(separator: "/")
        let baseName = String(pathParts.last ?? "")
        let subdirectory = pathParts.dropLast().isEmpty ? nil : pathParts.dropLast().joined(separator: "/")

        guard
            !baseName.isEmpty,
            let url = resolveSVGURL(baseName: baseName, normalizedPath: normalizedPath, subdirectory: subdirectory),
            let rawSVG = try? String(contentsOf: url, encoding: .utf8)
        else {
            return
        }

        let colorSignature = colorMap
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "|")

        let loadKey = "\(url.path)|\(colorSignature)"
        guard context.coordinator.lastLoadKey != loadKey else {
            return
        }
        context.coordinator.lastLoadKey = loadKey

        var recoloredSVG = rawSVG

        for (sourceColor, targetColor) in colorMap {
            for attribute in ["fill", "stroke"] {
                recoloredSVG = recoloredSVG.replacingOccurrences(
                    of: "\(attribute)=\"\(sourceColor)\"",
                    with: "\(attribute)=\"\(targetColor)\""
                )
            }
        }

        recoloredSVG = recoloredSVG
            .replacingOccurrences(of: #"preserveAspectRatio="none""#, with: #"preserveAspectRatio="xMidYMid meet""#)

        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
          <style>
            html, body {
              margin: 0;
              padding: 0;
              width: 100%;
              height: 100%;
              overflow: hidden;
              background: transparent;
            }
            svg {
              width: 100%;
              height: 100%;
              display: block;
            }
          </style>
        </head>
        <body>\(recoloredSVG)</body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
    }

    private func resolveSVGURL(baseName: String, normalizedPath: String, subdirectory: String?) -> URL? {
        if let subdirectory,
           let url = Bundle.main.url(forResource: baseName, withExtension: "svg", subdirectory: subdirectory) {
            return url
        }
        if let subdirectory,
           let url = Bundle.main.url(forResource: baseName, withExtension: "svg", subdirectory: "Resources/\(subdirectory)") {
            return url
        }
        if let url = Bundle.main.url(forResource: baseName, withExtension: "svg") {
            return url
        }
        if let url = Bundle.main.url(forResource: normalizedPath, withExtension: "svg") {
            return url
        }
        if let url = Bundle.main.url(forResource: "Resources/\(normalizedPath)", withExtension: "svg") {
            return url
        }
        return Bundle.main
            .urls(forResourcesWithExtension: "svg", subdirectory: nil)?
            .first(where: { $0.lastPathComponent == "\(baseName).svg" })
    }

    final class Coordinator {
        var lastLoadKey: String?
    }
}
