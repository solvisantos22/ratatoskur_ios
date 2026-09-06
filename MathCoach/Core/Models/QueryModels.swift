import Foundation

enum QueryMode: String, CaseIterable, Identifiable, Codable {
    case hint
    case check_solution
    case reveal

    var id: String { rawValue }

    static func availableModes(assignmentAllowReveal: Bool?) -> [QueryMode] {
        allCases.filter { assignmentAllowReveal != false || $0 != .reveal }
    }

    static let assignmentPolicyExplanation = "Kennarinn hefur slökkt á fullum lausnum í þessu verkefni. Þú getur fengið vísbendingu eða látið fara yfir lausnina."

    var displayName: String {
        switch self {
        case .hint:
            return "Vísbending"
        case .check_solution:
            return "Fara yfir lausn"
        case .reveal:
            return "Sýna lausn"
        }
    }
}

enum ExpertMode: String, CaseIterable, Identifiable, Codable {
    case off
    case clarity

    var id: String { rawValue }

    static var allCases: [ExpertMode] { [.off, .clarity] }

    var displayName: String {
        switch self {
        case .off:
            return "Af"
        case .clarity:
            return "Skýrleiki"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case ExpertMode.off.rawValue:
            self = .off
        case ExpertMode.clarity.rawValue, "strict":
            self = .clarity
        default:
            self = .off
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum PipelineMode: String, CaseIterable, Identifiable, Codable {
    case singlePass = "single_pass"
    case twoPass = "two_pass"

    static let appStorageKey = "query.pipeline.mode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singlePass:
            return "Frammistaða"
        case .twoPass:
            return "Nákvæmni"
        }
    }

    var explanation: String {
        switch self {
        case .singlePass:
            return "Svarar beint við innsendingu án sérstaks læsileikaprófara."
        case .twoPass:
            return "Keyrir læsileikaprófara áður en svarið er búið til til að ná betri lestri á efni."
        }
    }
}

struct QueryObservability: Decodable, Hashable {
    let traceId: String?
    let observationId: String?
    let messageId: String?
    let requestId: String?
    let modelName: String?
    let promptVersion: String?
    let retryCount: Int?
    let clientRequestId: String?
    let sessionId: String?
}

struct QueryReadingField: Codable, Hashable, Identifiable {
    let id: String
    let page: Int?
    let label: String?
    var text: String
}

struct QueryAmbiguousRegion: Decodable, Hashable {
    let page: Int?
    let snippet: String?
    let reason: String?
}

struct QueryResponse: Decodable {
    let verdict: String?
    let response_type: String?
    let message_is: String?
    let error_type: String?
    let error_step: String?
    let correct_approach: String?
    let error_confidence: Double?
    let all_readable: Bool?
    let reading_confidence: Double?
    let interpreted_reading: [QueryReadingField]?
    let ambiguous_regions: [QueryAmbiguousRegion]?
    let missing_parts: [String]?
    let expert_mode: String?
    let clarity_warning: Bool?
    let missing_justification: Bool?
    let concept_tag: String?
    let suggested_justification: String?
    let step_reference: String?
    let can_skip: Bool?
    let observability: QueryObservability?

    private enum CodingKeys: String, CodingKey {
        case verdict
        case response_type
        case message_is
        case error_type
        case error_step
        case correct_approach
        case error_confidence
        case all_readable
        case reading_confidence
        case interpreted_reading
        case ambiguous_regions
        case ambiguous_steps
        case missing_parts
        case expert_mode
        case clarity_warning
        case missing_justification
        case concept_tag
        case suggested_justification
        case step_reference
        case can_skip
        case observability
    }

    init(
        verdict: String?,
        response_type: String?,
        message_is: String?,
        error_type: String?,
        error_step: String?,
        correct_approach: String?,
        error_confidence: Double?,
        all_readable: Bool?,
        reading_confidence: Double?,
        interpreted_reading: [QueryReadingField]?,
        ambiguous_regions: [QueryAmbiguousRegion]?,
        missing_parts: [String]?,
        expert_mode: String?,
        clarity_warning: Bool?,
        missing_justification: Bool?,
        concept_tag: String?,
        suggested_justification: String?,
        step_reference: String?,
        can_skip: Bool?,
        observability: QueryObservability?
    ) {
        self.verdict = verdict
        self.response_type = response_type
        self.message_is = message_is
        self.error_type = error_type
        self.error_step = error_step
        self.correct_approach = correct_approach
        self.error_confidence = error_confidence
        self.all_readable = all_readable
        self.reading_confidence = reading_confidence
        self.interpreted_reading = interpreted_reading
        self.ambiguous_regions = ambiguous_regions
        self.missing_parts = missing_parts
        self.expert_mode = expert_mode
        self.clarity_warning = clarity_warning
        self.missing_justification = missing_justification
        self.concept_tag = concept_tag
        self.suggested_justification = suggested_justification
        self.step_reference = step_reference
        self.can_skip = can_skip
        self.observability = observability
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        verdict = try container.decodeIfPresent(String.self, forKey: .verdict)
        response_type = try container.decodeIfPresent(String.self, forKey: .response_type)
        message_is = try container.decodeIfPresent(String.self, forKey: .message_is)
        error_type = try container.decodeIfPresent(String.self, forKey: .error_type)
        error_step = try container.decodeIfPresent(String.self, forKey: .error_step)
        correct_approach = try container.decodeIfPresent(String.self, forKey: .correct_approach)
        error_confidence = try container.decodeIfPresent(Double.self, forKey: .error_confidence)
        all_readable = try container.decodeIfPresent(Bool.self, forKey: .all_readable)
        reading_confidence = try container.decodeIfPresent(Double.self, forKey: .reading_confidence)
        interpreted_reading = try container.decodeIfPresent([QueryReadingField].self, forKey: .interpreted_reading)
        ambiguous_regions = try container.decodeIfPresent([QueryAmbiguousRegion].self, forKey: .ambiguous_regions)
            ?? container.decodeIfPresent([QueryAmbiguousRegion].self, forKey: .ambiguous_steps)
        missing_parts = try container.decodeIfPresent([String].self, forKey: .missing_parts)
        expert_mode = try container.decodeIfPresent(String.self, forKey: .expert_mode)
        clarity_warning = try container.decodeIfPresent(Bool.self, forKey: .clarity_warning)
        missing_justification = try container.decodeIfPresent(Bool.self, forKey: .missing_justification)
        concept_tag = try container.decodeIfPresent(String.self, forKey: .concept_tag)
        suggested_justification = try container.decodeIfPresent(String.self, forKey: .suggested_justification)
        step_reference = try container.decodeIfPresent(String.self, forKey: .step_reference)
        can_skip = try container.decodeIfPresent(Bool.self, forKey: .can_skip)
        observability = try container.decodeIfPresent(QueryObservability.self, forKey: .observability)
    }
}
