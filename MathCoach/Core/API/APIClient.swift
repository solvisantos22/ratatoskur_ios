import Foundation

final class APIClient {
    private static let timeoutInterval: TimeInterval = 60
    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(baseURL: URL = AppConfig.baseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.session = session ?? APIClient.makeSession()
    }

    func register(
        fullName: String,
        email: String,
        password: String,
        consentAnalytics: Bool,
        consentDatasetInternal: Bool,
        consentDatasetPublish: Bool
    ) async throws -> TokenResponse {
        let payload = RegisterRequest(
            full_name: fullName,
            email: email,
            password: password,
            consent_analytics: consentAnalytics,
            consent_dataset_internal: consentDatasetInternal,
            consent_dataset_publish: consentDatasetPublish
        )
        var request = try makeRequest(endpoint: .register)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(payload)
        return try await perform(request, decodeAs: TokenResponse.self)
    }

    func login(email: String, password: String) async throws -> TokenResponse {
        let payload = LoginRequest(email: email, password: password)
        var request = try makeRequest(endpoint: .login)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(payload)
        return try await perform(request, decodeAs: TokenResponse.self)
    }

    func refresh() async throws -> TokenResponse {
        let request = try makeRequest(endpoint: .refresh)
        return try await perform(request, decodeAs: TokenResponse.self)
    }

    func me(accessToken: String) async throws -> MeResponse {
        var request = try makeRequest(endpoint: .me)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: MeResponse.self)
    }

    func updateMe(fullName: String?, accessToken: String) async throws -> MeResponse {
        let payload = UpdateMeRequest(full_name: fullName)
        var request = try makeRequest(endpoint: .updateMe)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(payload)
        return try await perform(request, decodeAs: MeResponse.self)
    }

    func logout() async throws {
        let request = try makeRequest(endpoint: .logout)
        _ = try await perform(request, decodeAs: LogoutResponse.self)
    }

    func query(
        problemId: String,
        mode: QueryMode,
        pipelineMode: PipelineMode?,
        expertMode: ExpertMode,
        problemImage: Data,
        solutionImages: [Data],
        drawingDataPages: [Data],
        pageCount: Int,
        confirmedReading: [QueryReadingField]?,
        clientRequestId: String,
        sessionId: String,
        accessToken: String
    ) async throws -> QueryResponse {
        guard !solutionImages.isEmpty, !drawingDataPages.isEmpty else {
            throw AppError.message("Engar lausnarsíður eru tiltækar til að senda.")
        }
        guard solutionImages.count == drawingDataPages.count else {
            throw AppError.message("Síður passa ekki saman í innsendingu. Reyndu aftur.")
        }

        let builder = MultipartBuilder()
        var parts: [MultipartPart] = [
            MultipartPart(
                name: "problem_id",
                filename: nil,
                contentType: nil,
                data: Data(problemId.utf8)
            ),
            MultipartPart(
                name: "mode",
                filename: nil,
                contentType: nil,
                data: Data(mode.rawValue.utf8)
            ),
            MultipartPart(
                name: "prob_image",
                filename: "problem.png",
                contentType: "image/png",
                data: problemImage
            ),
            MultipartPart(
                name: "page_count",
                filename: nil,
                contentType: nil,
                data: Data(String(pageCount).utf8)
            ),
            MultipartPart(
                name: "client_request_id",
                filename: nil,
                contentType: nil,
                data: Data(clientRequestId.utf8)
            ),
            MultipartPart(
                name: "session_id",
                filename: nil,
                contentType: nil,
                data: Data(sessionId.utf8)
            )
        ]
        if let pipelineMode {
            parts.append(
                MultipartPart(
                    name: "pipeline_mode",
                    filename: nil,
                    contentType: nil,
                    data: Data(pipelineMode.rawValue.utf8)
                )
            )
        }
        parts.append(
            MultipartPart(
                name: "expert_mode",
                filename: nil,
                contentType: nil,
                data: Data(expertMode.rawValue.utf8)
            )
        )
        if let confirmedReading, !confirmedReading.isEmpty {
            let confirmedData = try encode(confirmedReading)
            parts.append(
                MultipartPart(
                    name: "confirmed_reading_json",
                    filename: nil,
                    contentType: nil,
                    data: confirmedData
                )
            )
        }
        parts.append(
            contentsOf: solutionImages.enumerated().map { index, page in
                MultipartPart(
                    name: "sol_images",
                    filename: String(format: "solution_page_%03d.png", index + 1),
                    contentType: "image/png",
                    data: page
                )
            }
        )
        parts.append(
            contentsOf: drawingDataPages.enumerated().map { index, page in
                MultipartPart(
                    name: "drawing_data_pages",
                    filename: String(format: "drawing_page_%03d.bin", index + 1),
                    contentType: "application/octet-stream",
                    data: page
                )
            }
        )
        let body = builder.build(parts: parts)

        var request = try makeRequest(endpoint: .query)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(clientRequestId, forHTTPHeaderField: "x-client-request-id")
        request.setValue(sessionId, forHTTPHeaderField: "x-session-id")
        request.setValue("multipart/form-data; boundary=\(builder.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await perform(request, decodeAs: QueryResponse.self)
    }

    func listStudentClasses(accessToken: String) async throws -> [StudentClass] {
        var request = try makeRequest(endpoint: .studentClasses)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: [StudentClass].self)
    }

    func joinStudentClass(code: String, accessToken: String) async throws -> StudentClass {
        var request = try makeRequest(endpoint: .studentClassJoin)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(StudentClassJoinRequest(join_code: code))
        return try await perform(request, decodeAs: StudentClass.self)
    }

    func listStudentAssignments(accessToken: String) async throws -> [StudentAssignment] {
        var request = try makeRequest(endpoint: .studentAssignments)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: [StudentAssignment].self)
    }

    func startStudentAssignment(assignmentId: String, itemId: String, accessToken: String) async throws -> StudentAssignmentStartResponse {
        var request = try makeRequest(endpoint: .studentAssignmentStart(assignmentId: assignmentId, itemId: itemId))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: StudentAssignmentStartResponse.self)
    }

    func invalidateSession() {
        session.invalidateAndCancel()
        session.configuration.httpCookieStorage?.cookies?.forEach {
            session.configuration.httpCookieStorage?.deleteCookie($0)
        }
        session.configuration.urlCredentialStorage?.allCredentials.forEach { protectionSpace, credentials in
            credentials.values.forEach {
                session.configuration.urlCredentialStorage?.remove($0, for: protectionSpace)
            }
        }
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    func listProblems(accessToken: String) async throws -> [ProblemSummary] {
        var request = try makeRequest(endpoint: .problems)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: [ProblemSummary].self)
    }

    func createProblem(title: String, folderId: String?, accessToken: String) async throws -> ProblemSummary {
        let payload = ProblemCreateRequest(title: title, folder_id: folderId)
        var request = try makeRequest(endpoint: .problem)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(payload)
        return try await perform(request, decodeAs: ProblemSummary.self)
    }

    func deleteProblem(problemId: String, accessToken: String) async throws -> ProblemSummary {
        var request = try makeRequest(endpoint: .problemDelete(problemId: problemId))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: ProblemSummary.self)
    }

    func listFolders(accessToken: String) async throws -> [FolderSummary] {
        var request = try makeRequest(endpoint: .folders)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: [FolderSummary].self)
    }

    func createFolder(
        name: String,
        color: String?,
        parentFolderId: String?,
        accessToken: String
    ) async throws -> FolderSummary {
        let payload = FolderCreateRequest(name: name, color: color, parent_folder_id: parentFolderId)
        var request = try makeRequest(endpoint: .foldersCreate)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(payload)
        return try await perform(request, decodeAs: FolderSummary.self)
    }

    func updateFolder(
        folderId: String,
        name: String?,
        color: String?,
        parentFolderId: String?,
        accessToken: String
    ) async throws -> FolderSummary {
        let payload = FolderUpdateRequest(name: name, color: color, parent_folder_id: parentFolderId)
        var request = try makeRequest(endpoint: .folder(folderId: folderId))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(payload)
        return try await perform(request, decodeAs: FolderSummary.self)
    }

    func archiveFolder(folderId: String, accessToken: String) async throws -> FolderSummary {
        var request = try makeRequest(endpoint: .folder(folderId: folderId))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: FolderSummary.self)
    }

    func moveProblem(problemId: String, folderId: String, accessToken: String) async throws -> ProblemSummary {
        let payload = ProblemMoveRequest(folder_id: folderId)
        var request = try makeRequest(endpoint: .problemMove(problemId: problemId))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(payload)
        return try await perform(request, decodeAs: ProblemSummary.self)
    }

    func moveProblemsBatch(problemIds: [String], folderId: String, accessToken: String) async throws -> Int {
        let payload = ProblemBatchMoveRequest(problem_ids: problemIds, folder_id: folderId)
        var request = try makeRequest(endpoint: .problemsMoveBatch)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(payload)
        let response = try await perform(request, decodeAs: ProblemBatchMoveResponse.self)
        return response.moved_count
    }

    func listAttempts(problemId: String, accessToken: String) async throws -> [ProblemAttempt] {
        var request = try makeRequest(endpoint: .problemAttempts(problemId: problemId))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: [ProblemAttempt].self)
    }

    func submitAttemptFeedback(
        attemptId: String,
        rating: AttemptFeedbackRating,
        comment: String?,
        observability: QueryObservability?,
        clientRequestId: String?,
        sessionId: String?,
        accessToken: String
    ) async throws -> AttemptFeedbackResponse {
        let payload = AttemptFeedbackCreateRequest(
            rating: rating.rawValue,
            comment: comment,
            trace_id: observability?.traceId,
            observation_id: observability?.observationId,
            message_id: observability?.messageId,
            request_id: observability?.requestId,
            client_request_id: clientRequestId ?? observability?.clientRequestId,
            session_id: sessionId ?? observability?.sessionId,
            model_name: observability?.modelName,
            prompt_version: observability?.promptVersion
        )

        var request = try makeRequest(endpoint: .attemptFeedback(attemptId: attemptId))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(payload)
        return try await perform(request, decodeAs: AttemptFeedbackResponse.self)
    }

    func getAnalyticsSummary(accessToken: String) async throws -> UserStatsSummary {
        var request = try makeRequest(endpoint: .analyticsSummary)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: UserStatsSummary.self)
    }

    func getErrorEventTypeSummary(
        folderId: String?,
        accessToken: String
    ) async throws -> ErrorEventTypeSummaryResponse {
        var queryItems: [URLQueryItem] = []
        if let folderId, !folderId.isEmpty {
            queryItems.append(URLQueryItem(name: "folder_id", value: folderId))
        }
        var request = try makeRequest(endpoint: .analyticsErrorEventTypes, queryItems: queryItems)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: ErrorEventTypeSummaryResponse.self)
    }

    func getErrorEvents(
        errorType: String,
        folderId: String?,
        cursor: String?,
        limit: Int = 20,
        accessToken: String
    ) async throws -> ErrorEventPageResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "error_type", value: errorType),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let folderId, !folderId.isEmpty {
            queryItems.append(URLQueryItem(name: "folder_id", value: folderId))
        }
        if let cursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        var request = try makeRequest(endpoint: .analyticsErrorEvents, queryItems: queryItems)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: ErrorEventPageResponse.self)
    }

    func createExamPack(payload: ExamPackCreateRequest, accessToken: String) async throws -> ExamPackDetail {
        var request = try makeRequest(endpoint: .examPacksCreate)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(payload)
        return try await perform(request, decodeAs: ExamPackDetail.self)
    }

    func listExamPacks(accessToken: String) async throws -> [ExamPackSummary] {
        var request = try makeRequest(endpoint: .examPacksList)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: [ExamPackSummary].self)
    }

    func getExamPack(packId: String, accessToken: String) async throws -> ExamPackDetail {
        var request = try makeRequest(endpoint: .examPack(packId: packId))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: ExamPackDetail.self)
    }

    func startExamPack(packId: String, accessToken: String) async throws -> ExamSessionStartResponse {
        var request = try makeRequest(endpoint: .examPackStart(packId: packId))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: ExamSessionStartResponse.self)
    }

    func saveExamAnswer(
        sessionId: String,
        itemId: String,
        answerText: String?,
        answerImageBase64: String?,
        accessToken: String
    ) async throws -> ExamAnswerUpdateResponse {
        let payload = ExamAnswerUpdateRequest(
            answer_text: answerText,
            answer_image_base64: answerImageBase64
        )
        var request = try makeRequest(endpoint: .examSessionAnswer(sessionId: sessionId, itemId: itemId))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encode(payload)
        return try await perform(request, decodeAs: ExamAnswerUpdateResponse.self)
    }

    func submitExamSession(sessionId: String, accessToken: String) async throws -> ExamSessionSubmitResponse {
        var request = try makeRequest(endpoint: .examSessionSubmit(sessionId: sessionId))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: ExamSessionSubmitResponse.self)
    }

    func getExamSessionResults(sessionId: String, accessToken: String) async throws -> ExamSessionResultsResponse {
        var request = try makeRequest(endpoint: .examSessionResults(sessionId: sessionId))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request, decodeAs: ExamSessionResultsResponse.self)
    }

    private func makeRequest(endpoint: Endpoint) throws -> URLRequest {
        try makeRequest(endpoint: endpoint, queryItems: [])
    }

    private func makeRequest(endpoint: Endpoint, queryItems: [URLQueryItem]) throws -> URLRequest {
        guard let url = endpointURL(for: endpoint, queryItems: queryItems) else {
            throw AppError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = Self.timeoutInterval
        request.httpShouldHandleCookies = true
        return request
    }

    private func endpointURL(for endpoint: Endpoint, queryItems: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = endpoint.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, endpointPath].filter { !$0.isEmpty }.joined(separator: "/")
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw AppError.encodingFailed
        }
    }

    private func perform<Response: Decodable>(
        _ request: URLRequest,
        decodeAs _: Response.Type
    ) async throws -> Response {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw mapTransportError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw AppError.unauthorized
            }
            let message = parseServerMessage(from: data)
            throw AppError.server(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw AppError.decodingFailed
        }
    }

    private func parseServerMessage(from data: Data) -> String {
        guard !data.isEmpty else {
            return "Engar nánari villuupplýsingar."
        }

        if let object = try? JSONSerialization.jsonObject(with: data),
           let dictionary = object as? [String: Any],
           let detail = dictionary["detail"] {
            if let detailString = detail as? String {
                return detailString
            }
            if let detailArray = detail as? [[String: Any]] {
                return detailArray
                    .compactMap { $0["msg"] as? String }
                    .joined(separator: ", ")
            }
            return String(describing: detail)
        }

        return String(decoding: data, as: UTF8.self)
    }

    private func mapTransportError(_ error: Error) -> AppError {
        guard let urlError = error as? URLError else {
            return .message(error.localizedDescription)
        }

        switch urlError.code {
        case .notConnectedToInternet:
            return .message("Engin nettenging. Athugaðu tengingu og reyndu aftur.")
        case .networkConnectionLost:
            return .message("Tenging datt út meðan beiðni var í gangi. Reyndu aftur.")
        case .timedOut:
            return .message("Beiðni rann út á tíma. Reyndu aftur.")
        case .dataLengthExceedsMaximum:
            return .message("Gögn frá þjóninum fóru yfir hámarksstærð. Reyndu aftur.")
        case .cannotFindHost, .cannotConnectToHost:
            return .message("Næ ekki sambandi við bakenda. Athugaðu slóð og stöðu þjóns.")
        case .dnsLookupFailed:
            return .message("DNS uppfletting á bakenda mistókst. Athugaðu tengingu og slóð.")
        default:
            return .message(urlError.localizedDescription)
        }
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.httpCookieStorage = HTTPCookieStorage.shared
        // Fail fast when connectivity is unavailable so auth bootstrap can leave loading state.
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval
        return URLSession(configuration: config)
    }
}

private struct LogoutResponse: Decodable {
    let ok: Bool
}
