import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var showBackendSettings = false
    @State private var authMode: AuthMode = .login
    @Namespace private var authModeSelectionAnimation

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Auth.background
                    .ignoresSafeArea()

                VStack(spacing: 22) {
                    Color.clear
                        .frame(height: 20)

                    VStack(spacing: 8) {
                        SVGLogoView(resourceName: "ratatoskur_logo")
                            .frame(width: 140, height: 140)
                            .accessibilityHidden(true)

                        Text("Ratatoskur")
                            .font(.system(size: 40, weight: .bold, design: .serif))
                            .foregroundStyle(AppTheme.Auth.textPrimary)

                        Text("Persónulegi einkakennarinn þinn")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.Auth.textSecondary)
                    }

                    Button("Tengistillingar", systemImage: "network") {
                        showBackendSettings = true
                    }
                    .font(.footnote)
                    .disabled(authManager.isSubmitting)

                    authModeToggle

                    Group {
                        if authMode == .login {
                            LoginView()
                        } else {
                            RegisterView()
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 320, alignment: .top)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: 430, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 22)
                .padding(.vertical, 28)
            }
            .sheet(isPresented: $showBackendSettings) {
                BackendSettingsView()
            }
            .toolbar(.hidden, for: .navigationBar)
            .tint(AppTheme.Auth.primary)
        }
    }

    private var authModeToggle: some View {
        HStack(spacing: 8) {
            authModeButton(title: "Innskráning", mode: .login)
            authModeButton(title: "Nýskráning", mode: .register)
        }
        .padding(6)
        .background(AppTheme.Auth.surface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Innskráningarhamur")
    }

    @ViewBuilder
    private func authModeButton(title: String, mode: AuthMode) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                authMode = mode
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(authMode == mode ? Color.white : AppTheme.Auth.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    if authMode == mode {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(AppTheme.Auth.primary)
                            .matchedGeometryEffect(id: "auth_mode_selection", in: authModeSelectionAnimation)
                    } else {
                        Color.clear
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(authMode == mode ? .isSelected : [])
    }
}

private enum AuthMode {
    case login
    case register
}
