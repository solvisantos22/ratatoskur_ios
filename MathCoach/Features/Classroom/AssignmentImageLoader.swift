import Foundation
import UIKit

enum AssignmentImageLoader {
    static func load(url: URL) async throws -> UIImage {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            throw AppError.invalidURL
        }
        // Signed storage URLs authorize themselves; never forward backend cookies or bearer tokens.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let image = UIImage(data: data) else {
            throw AppError.message("Ekki tókst að sækja mynd kennarans. Reyndu aftur.")
        }
        return image
    }
}
