import Foundation

struct StudentClass: Decodable, Identifiable {
    let id: String
    let name: String
    let join_code: String
    let student_count: Int
    var teacher_name: String? = nil
}
