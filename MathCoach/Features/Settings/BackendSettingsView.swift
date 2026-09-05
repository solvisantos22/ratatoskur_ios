import SwiftUI

struct BackendSettingsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var address = AppConfig.baseURL.absoluteString
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Slóð þjóns", text: $address)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(save)
                    Button("Nota sjálfgefna tengingu") {
                        address = AppConfig.configuredBaseURL.absoluteString
                    }
                } header: {
                    Text("Tenging við Ratatosk")
                } footer: {
                    Text("Á iPad notarðu slóð tölvunnar sem keyrir þjóninn. Bæði tækin þurfa að vera á sama Wi-Fi neti. Innskráning hreinsast þegar tengingu er breytt.")
                }
                #if DEBUG
                Section {
                    Text("Dæmi: http://192.168.1.20:8000/")
                        .font(.footnote.monospaced())
                    Text("127.0.0.1 vísar á þetta tæki. Notaðu staðbundna IP-tölu tölvunnar á raunverulegum iPad.")
                        .font(.footnote)
                }
                #endif
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Tengistillingar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hætta við") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Vista", action: save)
                        .disabled(authManager.isSubmitting)
                }
            }
        }
    }

    private func save() {
        do {
            try authManager.changeBackend(to: address)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
