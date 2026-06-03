import Foundation

enum AppConfig {
    static let baseURL: URL = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "BACKEND_BASE_URL") as? String,
           let parsed = URL(string: value),
           !value.isEmpty {
            return parsed
        }
        return URL(string: "http://127.0.0.1:8000/")!
    }()
}
