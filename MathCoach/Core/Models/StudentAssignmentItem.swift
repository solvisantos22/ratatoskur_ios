import Foundation

struct StudentAssignmentItem: Decodable, Identifiable {
    let id: String
    let title: String
    let position: Int
    let image_url: URL
    let problem_id: String?
    var last_submitted_at: String? = nil
}
