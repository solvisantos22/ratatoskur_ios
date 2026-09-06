import SwiftUI

struct ClassroomCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Auth.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).stroke(AppTheme.Auth.border, lineWidth: 1)
            }
    }
}

extension View {
    func classroomCard() -> some View { modifier(ClassroomCardStyle()) }
}
