import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var fullName: String = ""
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var consentAnalytics: Bool = false
    @Published var consentDatasetInternal: Bool = false
    @Published var consentDatasetPublish: Bool = false

    func resetFields() {
        fullName = ""
        password = ""
        confirmPassword = ""
        consentAnalytics = false
        consentDatasetInternal = false
        consentDatasetPublish = false
    }

    func validateLogin() -> String? {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedEmail.isEmpty {
            return "Netfang vantar."
        }
        if !isLikelyValidEmail(trimmedEmail) {
            return "Sláðu inn gilt netfang."
        }
        if password.count < 8 {
            return "Lykilorð þarf að vera að minnsta kosti 8 stafir."
        }
        return nil
    }

    func validateRegistration() -> String? {
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return "Nafn vantar."
        }
        if trimmedName.count > 128 {
            return "Nafn má mest vera 128 stafir."
        }
        if let loginError = validateLogin() {
            return loginError
        }
        if password != confirmPassword {
            return "Lykilorð passa ekki saman."
        }
        return nil
    }

    private func isLikelyValidEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@")
        guard parts.count == 2 else {
            return false
        }
        let domain = parts[1]
        return domain.contains(".")
    }
}
