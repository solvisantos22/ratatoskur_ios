import SwiftUI
import UIKit

struct AvatarImageView: View {
    let resourceName: String

    var body: some View {
        Group {
            if let image = Self.loadAvatarImage(resourceName: resourceName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                SVGLogoView(resourceName: resourceName)
            }
        }
    }

    private static let imageCache = NSCache<NSString, UIImage>()

    private static func loadAvatarImage(resourceName: String) -> UIImage? {
        let cacheKey = resourceName as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let normalizedPath = resourceName.replacingOccurrences(of: "\\", with: "/")
        let pathParts = normalizedPath.split(separator: "/")
        let baseName = String(pathParts.last ?? "")
        guard !baseName.isEmpty else { return nil }

        let subdirectory = pathParts.dropLast().isEmpty ? nil : pathParts.dropLast().joined(separator: "/")

        let candidates: [URL?] = [
            Bundle.main.url(forResource: baseName, withExtension: "png", subdirectory: subdirectory),
            subdirectory.flatMap { Bundle.main.url(forResource: baseName, withExtension: "png", subdirectory: "Resources/\($0)") },
            Bundle.main.url(forResource: baseName, withExtension: "png"),
            Bundle.main.url(forResource: normalizedPath, withExtension: "png"),
            Bundle.main.url(forResource: "Resources/\(normalizedPath)", withExtension: "png")
        ]

        for candidate in candidates {
            guard let url = candidate, let image = UIImage(contentsOfFile: url.path) else {
                continue
            }
            imageCache.setObject(image, forKey: cacheKey)
            return image
        }

        if let fallback = Bundle.main
            .urls(forResourcesWithExtension: "png", subdirectory: nil)?
            .first(where: { $0.lastPathComponent == "\(baseName).png" }),
           let image = UIImage(contentsOfFile: fallback.path) {
            imageCache.setObject(image, forKey: cacheKey)
            return image
        }

        return nil
    }
}
