import SwiftUI

struct LoadingView: View {
    let label: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppTheme.Auth.primary)
            Text(label)
                .font(.footnote)
                .foregroundStyle(AppTheme.Auth.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Auth.background)
    }
}
