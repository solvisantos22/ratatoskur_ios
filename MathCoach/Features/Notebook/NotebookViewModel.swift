import PencilKit
import SwiftUI
import UIKit
import CoreGraphics
import Combine

struct QueryAttemptContext {
    let problemId: String
    let attemptId: String?
    let clientRequestId: String
    let sessionId: String
    let observability: QueryObservability?
}

struct FailedSubmissionContext {
    let problemId: String
    let mode: QueryMode
    let expertMode: ExpertMode
    let pipelineMode: PipelineMode?
    let confirmedReading: [QueryReadingField]?
}

struct NotebookPage: Identifiable {
    let id: String
    var order: Int
    var drawing: PKDrawing
    let createdAt: Date
    var updatedAt: Date

    static func empty(order: Int) -> NotebookPage {
        let now = Date()
        return NotebookPage(
            id: UUID().uuidString,
            order: order,
            drawing: PKDrawing(),
            createdAt: now,
            updatedAt: now
        )
    }
}

@MainActor
final class NotebookViewModel: ObservableObject {
    enum SubmissionStage {
        case preparing
        case optimizing
        case sending
        case waitingForTutor
        case streaming

        var label: String {
            switch self {
            case .preparing:
                return "Undirbý síður..."
            case .optimizing:
                return "Fínstilli innsendingu..."
            case .sending:
                return "Sendi innsendingu..."
            case .waitingForTutor:
                return "Kennari undirbýr endurgjöf..."
            case .streaming:
                return "Birti svar..."
            }
        }
    }

    @Published var problemImage: UIImage?
    @Published var pages: [NotebookPage] = [NotebookPage.empty(order: 0)]
    @Published var selectedPageIndex: Int = 0
    @Published var drawing: PKDrawing = .init()
    @Published var selectedMode: QueryMode = .hint
    @Published var selectedExpertMode: ExpertMode = .off
    @Published var response: QueryResponse?
    @Published var streamedResponseText: String = ""
    @Published var isStreamingResponse: Bool = false
    @Published var submissionStage: SubmissionStage?
    @Published var isShowingReadingConfirmation: Bool = false
    @Published var readingConfirmationFields: [QueryReadingField] = []
    @Published var attempts: [ProblemAttempt] = []
    @Published var feedbackRatingsByAttemptId: [String: AttemptFeedbackRating] = [:]
    @Published var feedbackCommentsByAttemptId: [String: String] = [:]
    @Published var feedbackSubmittingAttemptId: String?
    @Published var feedbackErrorMessage: String?
    @Published var feedbackErrorAttemptId: String?
    @Published var errorMessage: String?
    @Published var isSubmitting: Bool = false
    @Published var isLoadingAttempts: Bool = false
    @Published var lastQueryContext: QueryAttemptContext?
    @Published var lastFailedSubmission: FailedSubmissionContext?

    @Published private(set) var hasUnscopedLegacyDraft = false
    private var draftStore: ProblemDraftStore?
    private var autosaveTask: Task<Void, Never>?
    private var observabilityByAttemptId: [String: QueryObservability] = [:]
    private let softSubmissionSizeLimitBytes = 12 * 1024 * 1024
    private let maxPages = 12

    var canAddPage: Bool { pages.count < maxPages }
    var pageCount: Int { pages.count }
    var canRevealSolution: Bool {
        attempts.contains { attempt in
            guard let verdict = attempt.verdict?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                return false
            }
            return verdict == "fully_solved" || verdict == "fully_correct"
        }
    }
    var canRetryLastSubmission: Bool {
        lastFailedSubmission != nil && !isSubmitting
    }

    func pageLabel(for index: Int) -> String {
        "Blað \(index + 1)"
    }

    func setProblemImage(_ image: UIImage) {
        problemImage = image
    }

    func clearCanvas() {
        drawing = PKDrawing()
        syncCurrentDrawingToPages()
    }

    func resetResponse() {
        response = nil
        errorMessage = nil
    }

    func selectPage(index: Int) {
        guard pages.indices.contains(index) else {
            return
        }
        syncCurrentDrawingToPages()
        selectedPageIndex = index
        drawing = pages[index].drawing
    }

    func addPage() {
        guard canAddPage else {
            errorMessage = "Hámarksfjölda blaða náð fyrir þetta dæmi."
            return
        }
        syncCurrentDrawingToPages()
        pages.append(NotebookPage.empty(order: pages.count))
        selectedPageIndex = pages.count - 1
        drawing = pages[selectedPageIndex].drawing
        errorMessage = nil
    }

    func deleteSelectedPage() {
        guard pages.indices.contains(selectedPageIndex) else {
            return
        }

        if pages.count == 1 {
            clearCanvas()
            return
        }

        syncCurrentDrawingToPages()
        pages.remove(at: selectedPageIndex)
        normalizePageOrder()
        selectedPageIndex = min(selectedPageIndex, pages.count - 1)
        drawing = pages[selectedPageIndex].drawing
    }

    func duplicateSelectedPage() {
        guard canAddPage else {
            errorMessage = "Hámarksfjölda blaða náð fyrir þetta dæmi."
            return
        }
        guard pages.indices.contains(selectedPageIndex) else {
            return
        }

        syncCurrentDrawingToPages()
        let source = pages[selectedPageIndex]
        var duplicate = NotebookPage.empty(order: selectedPageIndex + 1)
        duplicate.drawing = source.drawing
        pages.insert(duplicate, at: selectedPageIndex + 1)
        normalizePageOrder()
        selectedPageIndex += 1
        drawing = pages[selectedPageIndex].drawing
    }

    func moveSelectedPageLeft() {
        guard pages.indices.contains(selectedPageIndex), selectedPageIndex > 0 else {
            return
        }
        syncCurrentDrawingToPages()
        pages.swapAt(selectedPageIndex, selectedPageIndex - 1)
        selectedPageIndex -= 1
        normalizePageOrder()
        drawing = pages[selectedPageIndex].drawing
    }

    func moveSelectedPageRight() {
        guard pages.indices.contains(selectedPageIndex), selectedPageIndex < pages.count - 1 else {
            return
        }
        syncCurrentDrawingToPages()
        pages.swapAt(selectedPageIndex, selectedPageIndex + 1)
        selectedPageIndex += 1
        normalizePageOrder()
        drawing = pages[selectedPageIndex].drawing
    }

    func syncCurrentDrawingToPages() {
        guard pages.indices.contains(selectedPageIndex) else {
            return
        }
        pages[selectedPageIndex].drawing = drawing
        pages[selectedPageIndex].updatedAt = Date()
    }

    func submitQuery(
        authManager: AuthManager,
        problemId: String,
        pipelineMode: PipelineMode?,
        confirmedReading: [QueryReadingField]? = nil
    ) async {
        isSubmitting = true
        errorMessage = nil
        response = nil
        streamedResponseText = ""
        isStreamingResponse = false
        submissionStage = .preparing
        isShowingReadingConfirmation = false
        if confirmedReading == nil {
            readingConfirmationFields = []
        }
        let clientRequestId = UUID().uuidString
        defer { isSubmitting = false }
        let originalMode = selectedMode
        let originalExpertMode = selectedExpertMode

        do {
            syncCurrentDrawingToPages()

            guard let problemImage else {
                throw AppError.missingProblemImage
            }

            guard var problemData = problemImage.jpegData(compressionQuality: 0.9) ?? problemImage.pngData() else {
                throw AppError.encodingFailed
            }

            let pageImages = try renderSolutionPagesForSubmission()
            var solutionPageData = try encodeSolutionPageImages(pageImages)
            let drawingPageData = makeDrawingDataPagesForSubmission()
            submissionStage = .sending

            if totalSubmissionSize(
                problemData: problemData,
                solutionPageData: solutionPageData,
                drawingPageData: drawingPageData
            ) > softSubmissionSizeLimitBytes {
                submissionStage = .optimizing
                let optimizedProblem = optimizeImageForUpload(problemImage)
                problemData = try pngData(from: optimizedProblem)
                solutionPageData = try encodeSolutionPageImages(
                    pageImages.map { optimizeImageForUpload($0) }
                )
            }

            if totalSubmissionSize(
                problemData: problemData,
                solutionPageData: solutionPageData,
                drawingPageData: drawingPageData
            ) > softSubmissionSizeLimitBytes {
                throw AppError.message(
                    "Innsendingin er of stór. Einfaldaðu teikninguna eða skiptu vinnunni í fleiri innsendingar."
                )
            }

            submissionStage = .waitingForTutor
            let result = try await authManager.query(
                problemId: problemId,
                mode: selectedMode,
                pipelineMode: pipelineMode,
                expertMode: selectedExpertMode,
                problemImage: problemData,
                solutionImages: solutionPageData,
                drawingDataPages: drawingPageData,
                pageCount: pages.count,
                confirmedReading: confirmedReading,
                clientRequestId: clientRequestId
            )
            try Task.checkCancellation()
            response = result
            if result.response_type?.lowercased() == "confirm_reading" {
                submissionStage = nil
                streamedResponseText = result.message_is ?? ""
                isStreamingResponse = false
                readingConfirmationFields = buildReadingConfirmationFields(from: result)
                isShowingReadingConfirmation = !readingConfirmationFields.isEmpty
                if !isShowingReadingConfirmation {
                    errorMessage = "Ekki tókst að undirbúa leiðréttingu á lestri. Reyndu aftur."
                }
                return
            }

            submissionStage = .streaming
            await streamResponseText(result.message_is ?? "")
            submissionStage = nil

            await loadAttempts(authManager: authManager, problemId: problemId)
            lastFailedSubmission = nil
            lastQueryContext = QueryAttemptContext(
                problemId: problemId,
                attemptId: nil,
                clientRequestId: clientRequestId,
                sessionId: authManager.sessionId,
                observability: result.observability
            )
            logObservabilityIfNeeded(from: result, problemId: problemId, clientRequestId: clientRequestId)
            if let newestAttemptId = attempts.first?.id, let current = lastQueryContext, current.problemId == problemId {
                if let observability = current.observability {
                    observabilityByAttemptId[newestAttemptId] = observability
                }
                lastQueryContext = QueryAttemptContext(
                    problemId: current.problemId,
                    attemptId: newestAttemptId,
                    clientRequestId: current.clientRequestId,
                    sessionId: current.sessionId,
                    observability: current.observability
                )
            }
        } catch {
            submissionStage = nil
            isStreamingResponse = false
            if error is CancellationError {
                errorMessage = "Submission was cancelled."
            } else if let localizedError = error as? LocalizedError {
                errorMessage = localizedError.errorDescription ?? "Query failed."
            } else {
                errorMessage = error.localizedDescription
            }
            lastFailedSubmission = FailedSubmissionContext(
                problemId: problemId,
                mode: originalMode,
                expertMode: originalExpertMode,
                pipelineMode: pipelineMode,
                confirmedReading: confirmedReading
            )
        }
    }

    func submitConfirmedReading(
        authManager: AuthManager,
        problemId: String,
        pipelineMode: PipelineMode?
    ) async {
        let cleaned = readingConfirmationFields
            .map { field in
                QueryReadingField(
                    id: field.id,
                    page: field.page,
                    label: field.label,
                    text: field.text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.text.isEmpty }

        guard !cleaned.isEmpty else {
            errorMessage = "Skrifaðu að minnsta kosti eina leiðréttingu áður en þú metur."
            return
        }

        await submitQuery(
            authManager: authManager,
            problemId: problemId,
            pipelineMode: pipelineMode,
            confirmedReading: cleaned
        )
    }

    func retryLastSubmission(authManager: AuthManager) async {
        guard let retry = lastFailedSubmission else {
            return
        }
        selectedMode = retry.mode
        selectedExpertMode = retry.expertMode
        await submitQuery(
            authManager: authManager,
            problemId: retry.problemId,
            pipelineMode: retry.pipelineMode,
            confirmedReading: retry.confirmedReading
        )
    }

    func cancelSubmission() {
        submissionStage = nil
        isStreamingResponse = false
        errorMessage = "Submission was cancelled."
    }

    func dismissReadingConfirmation() {
        isShowingReadingConfirmation = false
    }

#if DEBUG
    func presentDebugReadingConfirmation() {
        let mockFields: [QueryReadingField] = [
            QueryReadingField(
                id: "debug_reading_1",
                page: 1,
                label: "Bls. 1",
                text: ""
            ),
            QueryReadingField(
                id: "debug_reading_2",
                page: 1,
                label: "Bls. 1",
                text: "x = 4"
            ),
            QueryReadingField(
                id: "debug_reading_3",
                page: 2,
                label: "Bls. 2",
                text: "y = (3+1)/2"
            ),
        ]
        let mockRegions: [QueryAmbiguousRegion] = [
            QueryAmbiguousRegion(page: 1, snippet: "2 ? 2", reason: "Óskýrt veldismerki"),
            QueryAmbiguousRegion(page: 1, snippet: "x = ?", reason: "Lokasvar óskýrt"),
            QueryAmbiguousRegion(page: 2, snippet: "(3+1)/2", reason: "Brotaskrift óskýr"),
        ]
        response = QueryResponse(
            verdict: "unclear",
            response_type: "confirm_reading",
            message_is: "Ég er ekki alveg viss um stærðfræðitáknin í lausninni. Vinsamlegast staðfestu eða leiðréttu lesturinn áður en ég met skrefin.",
            error_type: nil,
            error_step: nil,
            correct_approach: nil,
            error_confidence: nil,
            all_readable: false,
            reading_confidence: 0.68,
            interpreted_reading: mockFields,
            ambiguous_regions: mockRegions,
            missing_parts: [],
            expert_mode: selectedExpertMode.rawValue,
            clarity_warning: nil,
            missing_justification: nil,
            concept_tag: nil,
            suggested_justification: nil,
            step_reference: nil,
            can_skip: nil,
            observability: nil
        )
        readingConfirmationFields = mockFields
        isShowingReadingConfirmation = true
        errorMessage = nil
    }
#endif

    func loadAttempts(authManager: AuthManager, problemId: String) async {
        isLoadingAttempts = true
        defer { isLoadingAttempts = false }

        do {
            attempts = try await authManager.listAttempts(problemId: problemId)
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Mistókst að sækja tilraunir."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitAttemptFeedback(
        attemptId: String,
        rating: AttemptFeedbackRating,
        comment: String?,
        authManager: AuthManager
    ) async {
        let trimmedComment = comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        let limitedComment = trimmedComment.map { String($0.prefix(FeedbackConstraints.maxCommentLength)) }
        let payloadComment = (limitedComment?.isEmpty == true) ? nil : limitedComment

        feedbackSubmittingAttemptId = attemptId
        feedbackErrorMessage = nil
        feedbackErrorAttemptId = nil
        defer { feedbackSubmittingAttemptId = nil }

        do {
            let observability = observabilityByAttemptId[attemptId]
            let saved = try await authManager.submitAttemptFeedback(
                attemptId: attemptId,
                rating: rating,
                observability: observability,
                clientRequestId: observability?.clientRequestId,
                comment: payloadComment
            )
            feedbackRatingsByAttemptId[attemptId] = rating
            if let savedComment = saved.comment?.trimmingCharacters(in: .whitespacesAndNewlines),
               !savedComment.isEmpty {
                feedbackCommentsByAttemptId[attemptId] = savedComment
            } else {
                feedbackCommentsByAttemptId.removeValue(forKey: attemptId)
            }
        } catch let error as LocalizedError {
            feedbackErrorMessage = error.errorDescription ?? "Mistókst að senda umsögn."
            feedbackErrorAttemptId = attemptId
        } catch {
            feedbackErrorMessage = error.localizedDescription
            feedbackErrorAttemptId = attemptId
        }
    }

    func restoreNotebook(problemId: String, backendURL: URL, userID: String, assignedImage: UIImage? = nil) {
        // Bind the notebook to the server/account that opened it, including delayed autosaves.
        autosaveTask?.cancel()
        let store = ProblemDraftStore(backendURL: backendURL, userID: userID)
        draftStore = store
        hasUnscopedLegacyDraft = store.hasUnscopedLegacyDraft(problemId: problemId)
        problemImage = nil
        selectedMode = .hint
        selectedExpertMode = .off
        loadLocalDraft(problemId: problemId)
        if let assignedImage {
            problemImage = assignedImage
        }
    }

    private func loadLocalDraft(problemId: String) {
        guard let draft = draftStore?.load(problemId: problemId) else {
            pages = [NotebookPage.empty(order: 0)]
            selectedPageIndex = 0
            drawing = pages[0].drawing
            return
        }

        let restoredPages = draft.pages
            .sorted { lhs, rhs in lhs.order < rhs.order }
            .compactMap { draftPage -> NotebookPage? in
                guard let restoredDrawing = try? PKDrawing(data: draftPage.drawingData) else {
                    return nil
                }
                return NotebookPage(
                    id: draftPage.id,
                    order: draftPage.order,
                    drawing: restoredDrawing,
                    createdAt: draftPage.createdAt,
                    updatedAt: draftPage.updatedAt
                )
            }

        if restoredPages.isEmpty {
            pages = [NotebookPage.empty(order: 0)]
        } else {
            pages = restoredPages
        }
        normalizePageOrder()

        if let selectedPageId = draft.selectedPageId,
           let idx = pages.firstIndex(where: { $0.id == selectedPageId }) {
            selectedPageIndex = idx
        } else {
            selectedPageIndex = 0
        }

        drawing = pages[selectedPageIndex].drawing

        if let imageData = draft.problemImageData, let restoredImage = UIImage(data: imageData) {
            problemImage = restoredImage
        }

        selectedMode = draft.selectedMode
        selectedExpertMode = draft.selectedExpertMode
    }

    func scheduleAutosave(problemId: String) {
        autosaveTask?.cancel()
        guard let draftStore else { return }
        let snapshot = makeDraftSnapshot()

        autosaveTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else {
                return
            }

            do {
                try draftStore.save(problemId: problemId, draft: snapshot)
            } catch {
                // Keep autosave best-effort and non-blocking for user flow.
            }
        }
    }

    func flushAutosaveNow(problemId: String) {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard let draftStore else { return }
        do {
            try draftStore.save(problemId: problemId, draft: makeDraftSnapshot())
        } catch {
            // Keep autosave best-effort and non-blocking for user flow.
        }
    }

    private func makeDraftSnapshot() -> ProblemDraft {
        syncCurrentDrawingToPages()
        let imageData = problemImage?.jpegData(compressionQuality: 0.9) ?? problemImage?.pngData()
        let pageDrafts = pages
            .sorted { lhs, rhs in lhs.order < rhs.order }
            .map { page in
                ProblemDraftPage(
                    id: page.id,
                    drawingData: page.drawing.dataRepresentation(),
                    order: page.order,
                    createdAt: page.createdAt,
                    updatedAt: page.updatedAt
                )
            }
        let selectedPageId = pages.indices.contains(selectedPageIndex) ? pages[selectedPageIndex].id : pages.first?.id

        return ProblemDraft(
            pages: pageDrafts,
            problemImageData: imageData,
            selectedMode: selectedMode,
            selectedExpertMode: selectedExpertMode,
            selectedPageId: selectedPageId
        )
    }

    private func renderSolutionPagesForSubmission() throws -> [UIImage] {
        let sortedPages = pages.sorted { lhs, rhs in lhs.order < rhs.order }
        let hasInk = sortedPages.contains { !$0.drawing.bounds.isEmpty }

        if !hasInk && selectedMode != .reveal {
            throw AppError.emptyDrawing
        }

        let drawings = sortedPages.isEmpty ? [PKDrawing()] : sortedPages.map(\.drawing)

        return try drawings.map { drawing in
            if drawing.bounds.isEmpty {
                return optimizeImageForUpload(renderEmptyCanvasImage())
            }
            let drawingBounds = drawing.bounds.insetBy(dx: -16, dy: -16)
            let image = drawing.image(from: drawingBounds, scale: 2.0)
            return optimizeImageForUpload(try normalizeForSubmission(image))
        }
    }

    private func makeDrawingDataPagesForSubmission() -> [Data] {
        let sortedPages = pages.sorted { lhs, rhs in lhs.order < rhs.order }
        let drawingPayloads = sortedPages.map { $0.drawing.dataRepresentation() }
        return drawingPayloads.isEmpty ? [PKDrawing().dataRepresentation()] : drawingPayloads
    }

    private func encodeSolutionPageImages(_ pageImages: [UIImage]) throws -> [Data] {
        let images = pageImages.isEmpty ? [renderEmptyCanvasImage()] : pageImages
        return try images.map(pngData(from:))
    }

    private func pngData(from image: UIImage) throws -> Data {
        guard let data = image.pngData() else {
            throw AppError.encodingFailed
        }
        return data
    }

    private func totalSubmissionSize(
        problemData: Data,
        solutionPageData: [Data],
        drawingPageData: [Data]
    ) -> Int {
        problemData.count + solutionPageData.reduce(0) { $0 + $1.count } + drawingPageData.reduce(0) { $0 + $1.count }
    }

    private func streamResponseText(_ fullText: String) async {
        let cleanText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            streamedResponseText = fullText
            isStreamingResponse = false
            return
        }

        isStreamingResponse = true
        streamedResponseText = ""

        var index = cleanText.startIndex
        while index < cleanText.endIndex {
            let nextIndex = cleanText.index(index, offsetBy: 6, limitedBy: cleanText.endIndex) ?? cleanText.endIndex
            streamedResponseText.append(contentsOf: cleanText[index..<nextIndex])
            index = nextIndex

            do {
                try await Task.sleep(nanoseconds: 28_000_000)
            } catch {
                break
            }
        }

        streamedResponseText = cleanText
        isStreamingResponse = false
    }

    private func buildReadingConfirmationFields(from response: QueryResponse) -> [QueryReadingField] {
        if let interpreted = response.interpreted_reading, !interpreted.isEmpty {
            return interpreted
        }

        var fallback: [QueryReadingField] = []
        if let regions = response.ambiguous_regions {
            for (index, region) in regions.enumerated() {
                let text = (region.snippet ?? region.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    continue
                }
                let label = region.page != nil ? "Bls. \(region.page ?? 1)" : "Óvíst svæði \(index + 1)"
                fallback.append(
                    QueryReadingField(
                        id: "fallback_\(index + 1)",
                        page: region.page,
                        label: label,
                        text: text
                    )
                )
            }
        }
        return fallback
    }

    private func renderEmptyCanvasImage() -> UIImage {
        let size = CGSize(width: 1200, height: 1600)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func normalizeForSubmission(_ image: UIImage) throws -> UIImage {
        guard let source = image.cgImage else {
            throw AppError.encodingFailed
        }

        let width = source.width
        let height = source.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw AppError.encodingFailed
        }

        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            throw AppError.encodingFailed
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)
        let whiteThreshold: UInt8 = 220

        for row in 0..<height {
            for col in 0..<width {
                let idx = row * bytesPerRow + col * bytesPerPixel
                let alpha = pixels[idx + 3]

                if alpha == 0 {
                    continue
                }

                var red = pixels[idx]
                var green = pixels[idx + 1]
                var blue = pixels[idx + 2]

                if red >= whiteThreshold, green >= whiteThreshold, blue >= whiteThreshold {
                    red = 0
                    green = 0
                    blue = 0
                }

                let alphaInt = Int(alpha)
                pixels[idx] = UInt8((Int(red) * alphaInt + 255 * (255 - alphaInt)) / 255)
                pixels[idx + 1] = UInt8((Int(green) * alphaInt + 255 * (255 - alphaInt)) / 255)
                pixels[idx + 2] = UInt8((Int(blue) * alphaInt + 255 * (255 - alphaInt)) / 255)
                pixels[idx + 3] = 255
            }
        }

        guard let output = context.makeImage() else {
            throw AppError.encodingFailed
        }

        return UIImage(cgImage: output, scale: image.scale, orientation: .up)
    }

    private func optimizeImageForUpload(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 2000
        let currentSize = image.size
        let largestDimension = max(currentSize.width, currentSize.height)
        guard largestDimension > maxDimension, largestDimension > 0 else {
            return image
        }

        let scaleRatio = maxDimension / largestDimension
        let targetSize = CGSize(
            width: max(1, floor(currentSize.width * scaleRatio)),
            height: max(1, floor(currentSize.height * scaleRatio))
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func normalizePageOrder() {
        for index in pages.indices {
            pages[index].order = index
        }
    }

    private func logObservabilityIfNeeded(from response: QueryResponse, problemId: String, clientRequestId: String) {
        #if DEBUG
        guard let observability = response.observability else {
            print("[Observability] Missing observability payload for problem_id=\(problemId), client_request_id=\(clientRequestId)")
            return
        }
        if observability.traceId == nil {
            print("[Observability] traceId missing for problem_id=\(problemId), client_request_id=\(clientRequestId)")
        }
        #endif
    }
}
