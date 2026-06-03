import SwiftUI

@main
struct MathCoachApp: App {
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .preferredColorScheme(.light)
                .task {
                    await authManager.bootstrap()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        Group {
            switch authManager.status {
            case .loading:
                LoadingView(label: "Hleð inn lotu...")
            case .unauthenticated:
                AuthView()
            case .authenticated(_):
                ProblemsOverviewView()
            }
        }
        .tint(AppTheme.Auth.primary)
    }
}
