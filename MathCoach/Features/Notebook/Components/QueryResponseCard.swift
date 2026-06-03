import SwiftUI

struct QueryResponseCard: View {
    let response: QueryResponse
    let displayedMessage: String
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Niðurstaða: \(localizedVerdict(response.verdict))", systemImage: "checkmark.seal")
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                Spacer()
                Text(localizedResponseType)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.Auth.primary.opacity(0.15))
                    .clipShape(Capsule())
            }
            .font(.subheadline)

            if isStreaming {
                Text(displayedMessage + "|")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.body)
                    .foregroundStyle(AppTheme.Auth.textPrimary)
                    .accessibilityLabel("Svar kennara í vinnslu")
            } else {
                MathTextView(text: displayedMessage)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(AppTheme.Auth.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.Auth.border, lineWidth: 1)
        )
    }

    private var localizedResponseType: String {
        guard let responseType = response.response_type?.trimmingCharacters(in: .whitespacesAndNewlines),
              !responseType.isEmpty
        else {
            return "almennt"
        }

        switch responseType.lowercased() {
        case "general":
            return "almennt"
        case "hint":
            return "vísbending"
        case "fix_first":
            return "leiðrétta fyrst"
        case "explanation":
            return "skýring"
        case "full_solution":
            return "full lausn"
        case "ask_clarification":
            return "ósk um skýringu"
        case "confirm_reading":
            return "staðfesta lestur"
        default:
            return responseType
        }
    }

    private func localizedVerdict(_ verdict: String?) -> String {
        guard let verdict = verdict?.trimmingCharacters(in: .whitespacesAndNewlines), !verdict.isEmpty else {
            return "Óþekkt"
        }

        switch verdict.lowercased() {
        case "fully_solved", "fully_correct":
            return "Fullkomlega rétt"
        case "correct_so_far", "correct":
            return "Rétt hingað til"
        case "incorrect":
            return "Rangt"
        case "partial":
            return "Að hluta rétt"
        case "unclear":
            return "Óskýrt"
        default:
            return verdict
        }
    }
}
