import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var viewModel = AuthViewModel()
    @State private var localError: String?

    var body: some View {
        VStack(spacing: 12) {
            labeledInput(title: "Netfang") {
                TextField(
                    "",
                    text: $viewModel.email,
                    prompt: Text(verbatim: "jonjonsson@mail.is")
                        .foregroundColor(AppTheme.Auth.textSecondary.opacity(0.75))
                )
                .foregroundColor(AppTheme.Auth.textPrimary)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textContentType(.emailAddress)
                .submitLabel(.next)
            }

            labeledInput(title: "Lykilorð") {
                SecureField(
                    "",
                    text: $viewModel.password,
                    prompt: Text("Sláðu inn lykilorð").foregroundColor(AppTheme.Auth.textSecondary.opacity(0.75))
                )
                .foregroundColor(AppTheme.Auth.textPrimary)
                .textContentType(.password)
                .submitLabel(.go)
            }

            if let error = localError ?? authManager.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Auth.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            PrimaryButton(
                title: "Skrá inn",
                isLoading: authManager.isSubmitting,
                backgroundColor: AppTheme.Auth.primary,
                pressedColor: AppTheme.Auth.primaryPressed
            ) {
                localError = viewModel.validateLogin()
                guard localError == nil else { return }

                Task {
                    await authManager.login(email: viewModel.email, password: viewModel.password)
                }
            }
            .accessibilityHint("Skráir þig inn á aðganginn.")
        }
        .padding(16)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.Auth.logo.opacity(0.18), lineWidth: 1)
        )
        .foregroundStyle(AppTheme.Auth.textPrimary)
        .onChange(of: viewModel.email) { _, _ in
            localError = nil
        }
        .onChange(of: viewModel.password) { _, _ in
            localError = nil
        }
    }

    @ViewBuilder
    private func labeledInput<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.Auth.textSecondary)

            content()
                .foregroundColor(AppTheme.Auth.textPrimary)
                .tint(AppTheme.Auth.primary)
                .padding(12)
                .background(AppTheme.Auth.background.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.Auth.border, lineWidth: 1)
                )
                .accessibilityLabel(title)
        }
    }
}
