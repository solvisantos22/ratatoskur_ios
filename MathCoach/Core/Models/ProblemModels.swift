import Foundation

struct ProblemCreateRequest: Encodable {
    let title: String
    let folder_id: String?
}

struct FolderCreateRequest: Encodable {
    let name: String
    let color: String?
    let parent_folder_id: String?
}

struct FolderUpdateRequest: Encodable {
    let name: String?
    let color: String?
    let parent_folder_id: String?
}

struct ProblemMoveRequest: Encodable {
    let folder_id: String
}

struct ProblemBatchMoveRequest: Encodable {
    let problem_ids: [String]
    let folder_id: String
}

struct ProblemBatchMoveResponse: Decodable {
    let moved_count: Int
}

enum AttemptFeedbackRating: String, Codable {
    case up = "thumbs_up"
    case down = "thumbs_down"
}

enum FeedbackConstraints {
    static let maxCommentLength: Int = 500
    static let warningThreshold: Int = 450
}

struct ProblemSummary: Decodable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let folder_id: String?
    let folder_name: String?
    let title: String
    let created_at: String
    let updated_at: String
    var assignment_id: String? = nil
    var assignment_item_id: String? = nil
    var assignment_image_url: URL? = nil
    var assignment_allow_reveal: Bool? = nil

    var isAssigned: Bool { assignment_id != nil || assignment_item_id != nil }
}

struct FolderSummary: Decodable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let parent_folder_id: String?
    let name: String
    let color: String?
    let created_at: String
    let updated_at: String
    let archived_at: String?
    let problem_count: Int?
}

struct ProblemAttempt: Decodable, Identifiable, Hashable {
    let id: String
    let problem_id: String
    let user_id: String
    let mode: String
    let page_count: Int?
    let problem_image_url: String?
    let verdict: String?
    let response_type: String?
    let message_is: String?
    let error_type: String?
    let model_name: String?
    let prompt_version: String?
    let latency_ms: Int?
    let tokens_in: Int?
    let tokens_out: Int?
    let tokens_thoughts: Int?
    let tokens_total: Int?
    let created_at: String

    // Optional backend extension: direct URL to show stored solution image.
    let solution_image_url: String?
}

struct AttemptFeedbackCreateRequest: Encodable {
    let rating: String
    let comment: String?
    let trace_id: String?
    let observation_id: String?
    let message_id: String?
    let request_id: String?
    let client_request_id: String?
    let session_id: String?
    let model_name: String?
    let prompt_version: String?
}

struct AttemptFeedbackResponse: Decodable {
    let id: String
    let attempt_id: String
    let user_id: String
    let rating: String?
    let comment: String?
    let created_at: String
}

struct UserStatsSummary: Decodable {
    let solved_problems_count_current: Int
    let solved_problems_count_pre: Int
    let average_error_current: Double
    let average_error_pre: Double
    let active_streak: Int
    let average_attempts_current: Double
    let average_attempts_pre: Double
    let most_common_mode: String?
}

struct ErrorEventTypeCount: Decodable, Hashable {
    let error_type: String
    let count: Int
}

struct ErrorEventTypeSummaryResponse: Decodable, Hashable {
    let total_occurrences: Int
    let total_distinct_error_types: Int
    let entries: [ErrorEventTypeCount]
}

struct ErrorEventRecord: Decodable, Identifiable, Hashable {
    let id: String
    let attempt_id: String
    let problem_id: String
    let problem_title: String?
    let folder_id: String?
    let folder_name: String?
    let topic: String?
    let subtopic: String?
    let wrong_step: String?
    let correct_step: String?
    let error_type: String
    let confidence: Double?
    let created_at: String
}

struct ErrorEventPageResponse: Decodable, Hashable {
    let items: [ErrorEventRecord]
    let next_cursor: String?
}
