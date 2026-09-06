import SwiftUI

struct ModePicker: View {
    @Binding var mode: QueryMode
    var assignmentAllowReveal: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Hamur", selection: $mode) {
                ForEach(QueryMode.availableModes(assignmentAllowReveal: assignmentAllowReveal)) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(AppTheme.Auth.primary)
            if assignmentAllowReveal == false {
                Text(QueryMode.assignmentPolicyExplanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: assignmentAllowReveal, initial: true) { _, allowReveal in
            if allowReveal == false && mode == .reveal { mode = .hint }
        }
    }
}
