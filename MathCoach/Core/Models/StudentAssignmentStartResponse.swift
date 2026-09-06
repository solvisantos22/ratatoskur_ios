import Foundation

struct StudentAssignmentStartResponse: Decodable, Identifiable, Hashable {
    let problem: ProblemSummary
    let image_url: URL
    var last_submission: ClassroomSubmissionReceipt? = nil

    var id: String { problem.id }
}
