import Foundation

struct StudentAssignment: Decodable, Identifiable {
    let id: String
    let class_id: String
    let class_name: String
    let title: String
    let item_count: Int
    let created_at: String
    let items: [StudentAssignmentItem]
}
