import SwiftUI

struct ModePicker: View {
    @Binding var mode: QueryMode

    var body: some View {
        Picker("Hamur", selection: $mode) {
            ForEach(QueryMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .tint(AppTheme.Auth.primary)
    }
}
