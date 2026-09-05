import Foundation

enum AppConfig {
    static let backendOverrideKey = "backend.baseURL"

    static var baseURL: URL {
        if let saved = UserDefaults.standard.string(forKey: backendOverrideKey),
           let url = try? validatedBackendURL(saved) {
            return url
        }
        return configuredBaseURL
    }

    static let configuredBaseURL: URL = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "BACKEND_BASE_URL") as? String,
           let parsed = URL(string: value),
           !value.isEmpty {
            return parsed
        }
        return URL(string: "http://127.0.0.1:8000/")!
    }()

    static func validatedBackendURL(_ input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              !host.contains(where: \.isWhitespace),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else {
            throw AppError.message("Sláðu inn gilda http:// eða https:// slóð án aðgangsorðs, fyrirspurnar eða myllumerkis.")
        }
        #if !DEBUG
        guard scheme == "https" else {
            throw AppError.message("Nota þarf https:// tengingu í útgefinni útgáfu.")
        }
        #endif
        components.scheme = scheme
        if !components.path.hasSuffix("/") { components.path += "/" }
        guard let url = components.url else { throw AppError.invalidURL }
        return url
    }
}
