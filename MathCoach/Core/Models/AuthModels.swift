import Foundation

struct RegisterRequest: Encodable {
    let full_name: String
    let email: String
    let password: String
    let consent_analytics: Bool
    let consent_dataset_internal: Bool
    let consent_dataset_publish: Bool
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct UpdateMeRequest: Encodable {
    let full_name: String?
}

struct TokenResponse: Decodable {
    let access_token: String
    let token_type: String
}

struct MeResponse: Decodable {
    let id: String
    let email: String
    let full_name: String?
    let anon_user_id: String?
    let consent_analytics: Bool?
    let consent_dataset_internal: Bool?
    let consent_dataset_publish: Bool?
}
