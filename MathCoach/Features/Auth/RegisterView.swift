import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var authManager: AuthManager
    @AppStorage("profile.avatar.id") private var selectedAvatarID: String = ProfileAvatarOption.defaultID
    @StateObject private var viewModel = AuthViewModel()
    @State private var localError: String?

    var body: some View {
        VStack(spacing: 12) {
            labeledInput(title: "Nafn") {
                TextField(
                    "",
                    text: $viewModel.fullName,
                    prompt: Text("Jón Jónsson").foregroundColor(AppTheme.Auth.textSecondary.opacity(0.75))
                )
                .foregroundColor(AppTheme.Auth.textPrimary)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .textContentType(.name)
                .submitLabel(.next)
            }

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
                    prompt: Text("Veldu lykilorð").foregroundColor(AppTheme.Auth.textSecondary.opacity(0.75))
                )
                .foregroundColor(AppTheme.Auth.textPrimary)
                .textContentType(.newPassword)
                .submitLabel(.next)
            }

            labeledInput(title: "Staðfesta lykilorð") {
                SecureField(
                    "",
                    text: $viewModel.confirmPassword,
                    prompt: Text("Sláðu inn aftur").foregroundColor(AppTheme.Auth.textSecondary.opacity(0.75))
                )
                .foregroundColor(AppTheme.Auth.textPrimary)
                .textContentType(.newPassword)
                .submitLabel(.go)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Veldu táknmynd")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.textSecondary)

                ProfileAvatarPicker(
                    selectedAvatarID: $selectedAvatarID,
                    columns: 3,
                    iconSize: 48,
                    iconPadding: 0,
                    labelSize: 13
                )
            }
            .padding(12)
            .background(AppTheme.Auth.background.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.Auth.border, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Leyfa notkunargreiningu", isOn: $viewModel.consentAnalytics)
                    .toggleStyle(.switch)
                Toggle("Leyfa innri gagnasafnsnotkun", isOn: $viewModel.consentDatasetInternal)
                    .toggleStyle(.switch)
                Toggle("Leyfa birtanlegt gagnasafn", isOn: $viewModel.consentDatasetPublish)
                    .toggleStyle(.switch)
            }
            .font(.footnote.weight(.semibold))
            .padding(12)
            .background(AppTheme.Auth.background.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.Auth.border, lineWidth: 1)
            )

            if let error = localError ?? authManager.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Auth.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            PrimaryButton(
                title: "Stofna aðgang",
                isLoading: authManager.isSubmitting,
                backgroundColor: AppTheme.Auth.primary,
                pressedColor: AppTheme.Auth.primaryPressed
            ) {
                localError = viewModel.validateRegistration()
                guard localError == nil else { return }

                Task {
                    await authManager.register(
                        fullName: viewModel.fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                        email: viewModel.email,
                        password: viewModel.password,
                        consentAnalytics: viewModel.consentAnalytics,
                        consentDatasetInternal: viewModel.consentDatasetInternal,
                        consentDatasetPublish: viewModel.consentDatasetPublish
                    )
                }
            }
            .accessibilityHint("Stofnar nýjan aðgang og skráir þig inn.")
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
        .onChange(of: viewModel.fullName) { _, _ in
            localError = nil
        }
        .onChange(of: viewModel.password) { _, _ in
            localError = nil
        }
        .onChange(of: viewModel.confirmPassword) { _, _ in
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
