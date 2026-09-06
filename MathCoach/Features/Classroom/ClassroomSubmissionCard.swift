import SwiftUI

struct ClassroomSubmissionCard: View {
    let model: ClassroomSubmissionModel
    let isReady: Bool
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Skil til kennara", systemImage: "paperplane")
                .font(.title3.bold()).fontDesign(.serif)
            Text("Sendu öll blöðin í þessu dæmi til kennarans. Þú þarft ekki að biðja Ratatosk um svar fyrst.")
                .font(.subheadline).foregroundStyle(AppTheme.Auth.textSecondary)
            if let receipt = model.receipt {
                Label("Síðast skilað: \(receipt.submittedDateLabel)", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                Text("Blaðafjöldi í síðustu skilum: \(receipt.page_count). Breytingar eftir skil fara ekki sjálfkrafa til kennarans; skilaðu aftur þegar þú ert tilbúin/n. Skil eru ekki einkunn eða staðfesting á réttri lausn.")
                    .font(.footnote).foregroundStyle(AppTheme.Auth.textSecondary)
            }
            if let error = model.errorMessage {
                Text(error).font(.footnote).foregroundStyle(AppTheme.Auth.error)
            }
            if model.isSubmitting {
                ProgressView("Sendi til kennara…")
            } else {
                Button(model.receipt == nil ? "Skila til kennara" : "Skila aftur til kennara", systemImage: "paperplane", action: onSubmit)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!isReady)
            }
        }
        .foregroundStyle(AppTheme.Auth.textPrimary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Auth.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
