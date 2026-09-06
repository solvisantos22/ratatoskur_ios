import Foundation
import Combine

@MainActor
final class AuthManager: ObservableObject {
    enum Status {
        case loading
        case unauthenticated
        case authenticated(MeResponse)
    }

    @Published private(set) var status: Status = .loading
    @Published var errorMessage: String?
    @Published var isSubmitting: Bool = false

    private var api: APIClient
    private let keychain: any TokenStore
    private let accessTokenKey = "mathcoach.access_token"
    private var accessToken: String?
    let sessionId: String = UUID().uuidString

    var currentUser: MeResponse? {
        guard case let .authenticated(me) = status else {
            return nil
        }
        return me
    }

    init(api: APIClient, keychain: any TokenStore) {
        self.api = api
        self.keychain = keychain
    }

    convenience init() {
        self.init(api: APIClient(), keychain: KeychainStore())
    }

    func bootstrap() async {
        status = .loading
        errorMessage = nil

        if let storedToken = keychain.get(accessTokenKey) {
            accessToken = storedToken
            if await loadProfile(using: storedToken) {
                return
            }
        }

        if await refreshSession() {
            return
        }

        clearSession()
    }

    func login(email: String, password: String) async {
        await submitAuthAction {
            let response = try await api.login(email: email, password: password)
            try await establishSession(with: response.access_token)
        }
    }

    func register(
        fullName: String,
        email: String,
        password: String,
        consentAnalytics: Bool,
        consentDatasetInternal: Bool,
        consentDatasetPublish: Bool
    ) async {
        await submitAuthAction {
            let response = try await api.register(
                fullName: fullName,
                email: email,
                password: password,
                consentAnalytics: consentAnalytics,
                consentDatasetInternal: consentDatasetInternal,
                consentDatasetPublish: consentDatasetPublish
            )
            try await establishSession(with: response.access_token)
        }
    }

    func logout() async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await api.logout()
        } catch {
            // Keep local logout behavior deterministic even if backend logout fails.
        }
        clearSession()
    }

    func updateProfile(fullName: String?) async throws -> MeResponse {
        let normalizedName = fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloadName = (normalizedName?.isEmpty == true) ? nil : normalizedName
        let token = try await ensureAccessToken()

        do {
            let me = try await api.updateMe(fullName: payloadName, accessToken: token)
            status = .authenticated(me)
            return me
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            let me = try await api.updateMe(fullName: payloadName, accessToken: refreshedToken)
            status = .authenticated(me)
            return me
        }
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
        confirmedReading: [QueryReadingField]? = nil,
        clientRequestId: String
    ) async throws -> QueryResponse {
        let token = try await ensureAccessToken()
        do {
            return try await api.query(
                problemId: problemId,
                mode: mode,
                pipelineMode: pipelineMode,
                expertMode: expertMode,
                problemImage: problemImage,
                solutionImages: solutionImages,
                drawingDataPages: drawingDataPages,
                pageCount: pageCount,
                confirmedReading: confirmedReading,
                clientRequestId: clientRequestId,
                sessionId: sessionId,
                accessToken: token
            )
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.query(
                problemId: problemId,
                mode: mode,
                pipelineMode: pipelineMode,
                expertMode: expertMode,
                problemImage: problemImage,
                solutionImages: solutionImages,
                drawingDataPages: drawingDataPages,
                pageCount: pageCount,
                confirmedReading: confirmedReading,
                clientRequestId: clientRequestId,
                sessionId: sessionId,
                accessToken: refreshedToken
            )
        }
    }

    func listStudentClasses() async throws -> [StudentClass] {
        try await withStudentToken { try await self.api.listStudentClasses(accessToken: $0) }
    }

    func joinStudentClass(code: String) async throws -> StudentClass {
        try await withStudentToken { try await self.api.joinStudentClass(code: code, accessToken: $0) }
    }

    func listStudentAssignments() async throws -> [StudentAssignment] {
        try await withStudentToken { try await self.api.listStudentAssignments(accessToken: $0) }
    }

    func startStudentAssignment(assignmentId: String, itemId: String) async throws -> StudentAssignmentStartResponse {
        try await withStudentToken {
            try await self.api.startStudentAssignment(assignmentId: assignmentId, itemId: itemId, accessToken: $0)
        }
    }

    func submitClassroomWork(assignmentId: String, itemId: String, problemId: String, submissionId: String, pages: [Data]) async throws -> ClassroomSubmissionReceipt {
        try await withStudentToken {
            try await self.api.submitClassroomWork(assignmentId: assignmentId, itemId: itemId, problemId: problemId, submissionId: submissionId, pages: pages, accessToken: $0)
        }
    }

    private func withStudentToken<T>(_ action: (String) async throws -> T) async throws -> T {
        let token = try await ensureAccessToken()
        do {
            return try await action(token)
        } catch AppError.unauthorized {
            return try await action(try await refreshAccessToken())
        }
    }

    func changeBackend(to input: String) throws {
        guard case .unauthenticated = status, !isSubmitting else {
            throw AppError.message("Skráðu þig út áður en þú breytir tengingu.")
        }
        let url = try AppConfig.validatedBackendURL(input)
        guard url != AppConfig.baseURL else { return }
        // The settings screen is available only when no authentication action is running.
        // Invalidate the old session before storing the new address or creating its client.
        api.invalidateSession()
        clearSession()
        errorMessage = nil
        UserDefaults.standard.set(url.absoluteString, forKey: AppConfig.backendOverrideKey)
        api = APIClient(baseURL: url)
    }

    func listProblems() async throws -> [ProblemSummary] {
        let token = try await ensureAccessToken()
        do {
            return try await api.listProblems(accessToken: token)
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.listProblems(accessToken: refreshedToken)
        }
    }

    func createProblem(title: String, folderId: String? = nil) async throws -> ProblemSummary {
        let token = try await ensureAccessToken()
        do {
            return try await api.createProblem(title: title, folderId: folderId, accessToken: token)
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.createProblem(title: title, folderId: folderId, accessToken: refreshedToken)
        }
    }

    func deleteProblem(problemId: String) async throws -> ProblemSummary {
        let token = try await ensureAccessToken()
        do {
            return try await api.deleteProblem(problemId: problemId, accessToken: token)
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.deleteProblem(problemId: problemId, accessToken: refreshedToken)
        }
    }

    func listFolders() async throws -> [FolderSummary] {
        let token = try await ensureAccessToken()
        do {
            return try await api.listFolders(accessToken: token)
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.listFolders(accessToken: refreshedToken)
        }
    }

    func createFolder(
        name: String,
        color: String? = nil,
        parentFolderId: String? = nil
    ) async throws -> FolderSummary {
        let token = try await ensureAccessToken()
        do {
            return try await api.createFolder(
                name: name,
                color: color,
                parentFolderId: parentFolderId,
                accessToken: token
            )
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.createFolder(
                name: name,
                color: color,
                parentFolderId: parentFolderId,
                accessToken: refreshedToken
            )
        }
    }

    func archiveFolder(folderId: String) async throws -> FolderSummary {
        let token = try await ensureAccessToken()
        do {
            return try await api.archiveFolder(folderId: folderId, accessToken: token)
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.archiveFolder(folderId: folderId, accessToken: refreshedToken)
        }
    }

    func moveProblem(problemId: String, folderId: String) async throws -> ProblemSummary {
        let token = try await ensureAccessToken()
        do {
            return try await api.moveProblem(problemId: problemId, folderId: folderId, accessToken: token)
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.moveProblem(problemId: problemId, folderId: folderId, accessToken: refreshedToken)
        }
    }

    func moveProblemsBatch(problemIds: [String], folderId: String) async throws -> Int {
        let token = try await ensureAccessToken()
        do {
            return try await api.moveProblemsBatch(problemIds: problemIds, folderId: folderId, accessToken: token)
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.moveProblemsBatch(
                problemIds: problemIds,
                folderId: folderId,
                accessToken: refreshedToken
            )
        }
    }

    func listAttempts(problemId: String) async throws -> [ProblemAttempt] {
        let token = try await ensureAccessToken()
        do {
            return try await api.listAttempts(problemId: problemId, accessToken: token)
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.listAttempts(problemId: problemId, accessToken: refreshedToken)
        }
    }

    func submitAttemptFeedback(
        attemptId: String,
        rating: AttemptFeedbackRating,
        observability: QueryObservability? = nil,
        clientRequestId: String? = nil,
        comment: String? = nil
    ) async throws -> AttemptFeedbackResponse {
        let token = try await ensureAccessToken()
        do {
            return try await api.submitAttemptFeedback(
                attemptId: attemptId,
                rating: rating,
                comment: comment,
                observability: observability,
                clientRequestId: clientRequestId,
                sessionId: sessionId,
                accessToken: token
            )
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.submitAttemptFeedback(
                attemptId: attemptId,
                rating: rating,
                comment: comment,
                observability: observability,
                clientRequestId: clientRequestId,
                sessionId: sessionId,
                accessToken: refreshedToken
            )
        }
    }

    func getAnalyticsSummary() async throws -> UserStatsSummary {
        let token = try await ensureAccessToken()
        do {
            return try await api.getAnalyticsSummary(accessToken: token)
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.getAnalyticsSummary(accessToken: refreshedToken)
        }
    }

    func getErrorEventTypeSummary(folderId: String?) async throws -> ErrorEventTypeSummaryResponse {
        let token = try await ensureAccessToken()
        do {
            return try await api.getErrorEventTypeSummary(folderId: folderId, accessToken: token)
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.getErrorEventTypeSummary(folderId: folderId, accessToken: refreshedToken)
        }
    }

    func getErrorEvents(
        errorType: String,
        folderId: String?,
        cursor: String?,
        limit: Int = 20
    ) async throws -> ErrorEventPageResponse {
        let token = try await ensureAccessToken()
        do {
            return try await api.getErrorEvents(
                errorType: errorType,
                folderId: folderId,
                cursor: cursor,
                limit: limit,
                accessToken: token
            )
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.getErrorEvents(
                errorType: errorType,
                folderId: folderId,
                cursor: cursor,
                limit: limit,
                accessToken: refreshedToken
            )
        }
    }

    func createExamPack(payload: ExamPackCreateRequest) async throws -> ExamPackDetail {
        let token = try await ensureAccessToken()
        do {
            return try await api.createExamPack(payload: payload, accessToken: token)
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.createExamPack(payload: payload, accessToken: refreshedToken)
        }
    }

    func listExamPacks() async throws -> [ExamPackSummary] {
        let token = try await ensureAccessToken()
        do {
            return try await api.listExamPacks(accessToken: token)
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.listExamPacks(accessToken: refreshedToken)
        }
    }

    func getExamPack(packId: String) async throws -> ExamPackDetail {
        let token = try await ensureAccessToken()
        do {
            return try await api.getExamPack(packId: packId, accessToken: token)
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.getExamPack(packId: packId, accessToken: refreshedToken)
        }
    }

    func startExamPack(packId: String) async throws -> ExamSessionStartResponse {
        let token = try await ensureAccessToken()
        do {
            return try await api.startExamPack(packId: packId, accessToken: token)
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.startExamPack(packId: packId, accessToken: refreshedToken)
        }
    }

    func saveExamAnswer(
        sessionId: String,
        itemId: String,
        answerText: String?,
        answerImageBase64: String?
    ) async throws -> ExamAnswerUpdateResponse {
        let token = try await ensureAccessToken()
        do {
            return try await api.saveExamAnswer(
                sessionId: sessionId,
                itemId: itemId,
                answerText: answerText,
                answerImageBase64: answerImageBase64,
                accessToken: token
            )
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.saveExamAnswer(
                sessionId: sessionId,
                itemId: itemId,
                answerText: answerText,
                answerImageBase64: answerImageBase64,
                accessToken: refreshedToken
            )
        }
    }

    func submitExamSession(sessionId: String) async throws -> ExamSessionSubmitResponse {
        let token = try await ensureAccessToken()
        do {
            return try await api.submitExamSession(sessionId: sessionId, accessToken: token)
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.submitExamSession(sessionId: sessionId, accessToken: refreshedToken)
        }
    }

    func getExamSessionResults(sessionId: String) async throws -> ExamSessionResultsResponse {
        let token = try await ensureAccessToken()
        do {
            return try await api.getExamSessionResults(sessionId: sessionId, accessToken: token)
        } catch AppError.unauthorized {
            let refreshedToken = try await refreshAccessToken()
            return try await api.getExamSessionResults(sessionId: sessionId, accessToken: refreshedToken)
        }
    }

    private func submitAuthAction(_ action: () async throws -> Void) async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await action()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Innskráning mistókst."
            clearSession()
        } catch {
            errorMessage = error.localizedDescription
            clearSession()
        }
    }

    private func establishSession(with token: String) async throws {
        accessToken = token
        keychain.set(token, for: accessTokenKey)
        guard await loadProfile(using: token) else {
            throw AppError.unauthorized
        }
    }

    private func loadProfile(using token: String) async -> Bool {
        do {
            let me = try await api.me(accessToken: token)
            status = .authenticated(me)
            errorMessage = nil
            return true
        } catch AppError.unauthorized {
            return false
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func refreshSession() async -> Bool {
        do {
            let token = try await refreshAccessToken()
            return await loadProfile(using: token)
        } catch {
            return false
        }
    }

    private func refreshAccessToken() async throws -> String {
        let response = try await api.refresh()
        accessToken = response.access_token
        keychain.set(response.access_token, for: accessTokenKey)
        return response.access_token
    }

    private func ensureAccessToken() async throws -> String {
        if let token = accessToken {
            return token
        }
        if let token = keychain.get(accessTokenKey) {
            accessToken = token
            return token
        }
        return try await refreshAccessToken()
    }

    private func clearSession() {
        accessToken = nil
        keychain.delete(accessTokenKey)
        status = .unauthenticated
    }
}
