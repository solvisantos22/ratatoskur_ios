import SwiftUI

struct PrimaryButton: View {
    let title: String
    let isLoading: Bool
    let backgroundColor: Color
    let pressedColor: Color
    let action: () -> Void

    init(
        title: String,
        isLoading: Bool,
        backgroundColor: Color = AppTheme.Auth.primary,
        pressedColor: Color = AppTheme.Auth.primaryPressed,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isLoading = isLoading
        self.backgroundColor = backgroundColor
        self.pressedColor = pressedColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(PrimaryButtonStyle(backgroundColor: backgroundColor, pressedColor: pressedColor))
        .disabled(isLoading)
        .opacity(isLoading ? 0.7 : 1.0)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    let backgroundColor: Color
    let pressedColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(configuration.isPressed ? pressedColor : backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
