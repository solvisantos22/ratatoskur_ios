import Foundation

enum ExamPackSize: Int, CaseIterable, Identifiable {
    case ten = 10
    case twenty = 20
    case thirty = 30

    var id: Int { rawValue }
}

enum ExamBuildMode: String, CaseIterable, Identifiable, Codable {
    case auto
    case manual

    var id: String { rawValue }
}

enum ExamFeedbackMode: String, CaseIterable, Identifiable, Codable {
    case per_question
    case end_exam

    var id: String { rawValue }
}

enum ExamTopic: String, CaseIterable, Identifiable, Codable {
    case algebra
    case fractions

    var id: String { rawValue }
}

enum ExamErrorTarget: String, CaseIterable, Identifiable, Codable {
    case sign_error
    case order_of_operations
    case distribution_error
    case equation_isolation_error
    case fraction_common_denominator_error
    case fraction_simplification_error
    case fraction_arithmetic_error

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sign_error: return "Formerkjavillur"
        case .order_of_operations: return "Röð aðgerða"
        case .distribution_error: return "Dreifiregla"
        case .equation_isolation_error: return "Einangrun í jöfnum"
        case .fraction_common_denominator_error: return "Samnefnari"
        case .fraction_simplification_error: return "Einföldun brota"
        case .fraction_arithmetic_error: return "Reikningur með brotum"
        }
    }
}

struct ExamPackCreateRequest: Encodable {
    let title: String
    let pack_size: Int
    let build_mode: String
    let feedback_mode: String
    let topics: [String]
    let manual_error_targets: [String]?
}

struct ExamPackItemSummary: Decodable, Hashable, Identifiable {
    let id: String
    let position: Int
    let topic: String
    let difficulty: String
    let target_error_type: String?
    let target_concept_tag: String?
    let question_text: String
    let answer_format: String
}

struct ExamPackSummary: Decodable, Hashable, Identifiable {
    let id: String
    let title: String
    let pack_size: Int
    let build_mode: String
    let feedback_mode: String
    let topics: [String]
    let manual_error_targets: [String]?
    let status: String
    let generation_model: String?
    let generation_prompt_version: String?
    let created_at: String
    let updated_at: String
}

struct ExamPackDetail: Decodable, Hashable {
    let id: String
    let title: String
    let pack_size: Int
    let build_mode: String
    let feedback_mode: String
    let topics: [String]
    let manual_error_targets: [String]?
    let status: String
    let generation_model: String?
    let generation_prompt_version: String?
    let created_at: String
    let updated_at: String
    let items: [ExamPackItemSummary]
}

struct ExamSessionStartResponse: Decodable, Hashable {
    let session_id: String
    let pack: ExamPackDetail
}

struct ExamAnswerUpdateRequest: Encodable {
    let answer_text: String?
    let answer_image_base64: String?
}

struct ExamAnswerUpdateResponse: Decodable, Hashable {
    let session_id: String
    let item_id: String
    let answer_text: String?
    let is_correct: Bool?
    let score: Double?
    let feedback_text: String?
    let graded: Bool
}

struct ExamSessionSubmitResponse: Decodable, Hashable {
    let session_id: String
    let status: String
    let score_correct: Int
    let score_total: Int
    let score_percent: Double
}

struct ExamSessionResultItem: Decodable, Hashable, Identifiable {
    let item_id: String
    let position: Int
    let topic: String
    let difficulty: String
    let target_error_type: String?
    let question_text: String
    let answer_format: String
    let answer_text: String?
    let is_correct: Bool?
    let score: Double?
    let feedback_text: String?

    var id: String { item_id }
}

struct ExamSessionResultsResponse: Decodable, Hashable {
    let session_id: String
    let pack_id: String
    let status: String
    let feedback_mode: String
    let score_correct: Int?
    let score_total: Int?
    let score_percent: Double?
    let started_at: String
    let submitted_at: String?
    let graded_at: String?
    let items: [ExamSessionResultItem]
}
