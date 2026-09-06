import Foundation
import Observation

@Observable
@MainActor
final class ClassroomSubmissionModel {
    private(set) var receipt: ClassroomSubmissionReceipt?
    private(set) var isSubmitting = false
    var errorMessage: String?
    private var pendingID: String?
    private var pendingPages: [Data]?

    func restoreReceipt(_ receipt: ClassroomSubmissionReceipt?) {
        guard let receipt else { return }
        if let currentDate = self.receipt?.submittedDate,
           let incomingDate = receipt.submittedDate, incomingDate < currentDate { return }
        self.receipt = receipt
    }

    func submit(pages: [Data], send: (String, [Data]) async throws -> ClassroomSubmissionReceipt) async {
        guard !isSubmitting, !Task.isCancelled else { return }
        errorMessage = nil
        guard (1...12).contains(pages.count), pages.allSatisfy({ !$0.isEmpty }) else {
            errorMessage = "Engar gildar lausnarsíður eru tiltækar til að senda."
            return
        }
        guard pages.allSatisfy({ $0.count <= 7 * 1024 * 1024 }),
              pages.reduce(0, { $0 + $1.count }) <= 30 * 1024 * 1024 else {
            errorMessage = "Skilin eru of stór. Einfaldaðu blöðin og reyndu aftur."
            return
        }
        if pendingPages != pages || pendingID == nil {
            pendingID = UUID().uuidString
            pendingPages = pages
        }
        guard let id = pendingID else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let result = try await send(id, pages)
            try Task.checkCancellation()
            receipt = result
            pendingID = nil
            pendingPages = nil
        } catch {
            guard !Task.isCancelled else { return }
            if case AppError.server(statusCode: 409, message: _) = error {
                errorMessage = "Skil með þessu auðkenni eru þegar til. Reyndu aftur til að senda nýtt afrit."
                pendingID = nil
                pendingPages = nil
            } else {
                errorMessage = "Ekki tókst að staðfesta skil. Drögin eru enn á tækinu. \(error.localizedDescription)"
            }
        }
    }
}
