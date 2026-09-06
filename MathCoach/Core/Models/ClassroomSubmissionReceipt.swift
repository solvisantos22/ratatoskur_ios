import Foundation

struct ClassroomSubmissionReceipt: Decodable, Identifiable, Hashable {
    let id: String
    let created_at: String
    let page_count: Int

    var submittedDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: created_at) ?? ISO8601DateFormatter().date(from: created_at)
    }

    var submittedDateLabel: String {
        submittedDate?.formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: "is_IS"))) ?? created_at
    }
}
