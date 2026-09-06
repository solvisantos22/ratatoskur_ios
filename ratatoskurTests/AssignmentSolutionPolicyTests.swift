import XCTest
import PencilKit
@testable import ratatoskur

@MainActor
final class AssignmentSolutionPolicyTests: XCTestCase {
    func testAssignmentAndProblemDecodeEnabledDisabledAndLegacyPolicies() throws {
        for (field, expected) in [("true", true), ("false", false), ("null", nil), (nil, nil)] as [(String?, Bool?)] {
            let problemPolicy = field.map { ",\"assignment_allow_reveal\":\($0)" } ?? ""
            let problem = try JSONDecoder().decode(ProblemSummary.self, from: Data("""
            {"id":"problem","user_id":"student","title":"Dæmi","created_at":"now","updated_at":"now","assignment_id":"assignment","assignment_item_id":"item"\(problemPolicy)}
            """.utf8))
            XCTAssertEqual(problem.assignment_allow_reveal, expected)
            let start = try JSONDecoder().decode(StudentAssignmentStartResponse.self, from: Data("""
            {"problem":{"id":"problem","user_id":"student","title":"Dæmi","created_at":"now","updated_at":"now"\(problemPolicy)},"image_url":"https://example.com/image"}
            """.utf8))
            XCTAssertEqual(start.problem.assignment_allow_reveal, expected)
            let assignmentPolicy = field.map { ",\"allow_reveal\":\($0)" } ?? ""
            let assignment = try JSONDecoder().decode(StudentAssignment.self, from: Data("""
            {"id":"assignment","class_id":"class","class_name":"Bekkur","title":"Dæmi","item_count":0,"created_at":"now","items":[]\(assignmentPolicy)}
            """.utf8))
            XCTAssertEqual(assignment.allow_reveal, expected)
        }
    }

    func testOnlyExplicitFalseRemovesRevealFromAvailableModes() {
        XCTAssertEqual(QueryMode.availableModes(assignmentAllowReveal: false), [.hint, .check_solution])
        XCTAssertEqual(QueryMode.availableModes(assignmentAllowReveal: true), [.hint, .check_solution, .reveal])
        XCTAssertEqual(QueryMode.availableModes(assignmentAllowReveal: nil), [.hint, .check_solution, .reveal])
    }

    func testRestoringDisabledRevealUsesHintAndPreservesAllInkAndSelectedPage() throws {
        let problemID = UUID().uuidString
        let backendURL = URL(string: "https://policy-test.example/")!
        let store = ProblemDraftStore(backendURL: backendURL, userID: "student")
        defer { store.delete(problemId: problemID) }
        let drawing = makeInk()
        let savedPages = ["first", "second"].enumerated().map { index, id in
            ProblemDraftPage(id: id, drawingData: drawing.dataRepresentation(), order: index, createdAt: Date(), updatedAt: Date())
        }
        try store.save(problemId: problemID, draft: ProblemDraft(pages: savedPages, problemImageData: nil, selectedMode: .reveal, selectedExpertMode: .clarity, selectedPageId: "second"))

        let model = NotebookViewModel()
        model.restoreNotebook(problemId: problemID, backendURL: backendURL, userID: "student", assignmentAllowReveal: false)
        XCTAssertEqual(model.selectedMode, .hint)
        XCTAssertEqual(model.selectedExpertMode, .clarity)
        XCTAssertEqual(model.pages.map(\.id), ["first", "second"])
        XCTAssertEqual(model.selectedPageIndex, 1)
        XCTAssertEqual(model.pages.map { $0.drawing.strokes.count }, [1, 1])
        XCTAssertEqual(model.drawing.strokes.first?.path.first?.location, CGPoint(x: 20, y: 30))
        model.flushAutosaveNow(problemId: problemID)
        XCTAssertEqual(store.load(problemId: problemID)?.selectedMode, .hint)
        XCTAssertEqual(store.load(problemId: problemID)?.selectedPageId, "second")
    }

    func testEnabledAndLegacyNotebooksKeepRestoredReveal() throws {
        let problemID = UUID().uuidString
        let backendURL = URL(string: "https://policy-test.example/")!
        let store = ProblemDraftStore(backendURL: backendURL, userID: "student")
        defer { store.delete(problemId: problemID) }
        let page = ProblemDraftPage(id: "page", drawingData: makeInk().dataRepresentation(), order: 0, createdAt: Date(), updatedAt: Date())
        try store.save(problemId: problemID, draft: ProblemDraft(pages: [page], problemImageData: nil, selectedMode: .reveal, selectedExpertMode: .off, selectedPageId: "page"))
        for policy in [true, nil] as [Bool?] {
            let model = NotebookViewModel()
            model.restoreNotebook(problemId: problemID, backendURL: backendURL, userID: "student", assignmentAllowReveal: policy)
            XCTAssertEqual(model.selectedMode, .reveal)
        }
    }

    func testRefreshingPolicyPreservesInkAndDoesNotLeakToAnotherNotebook() {
        let model = NotebookViewModel()
        let backendURL = URL(string: "https://policy-test.example/")!
        let problemID = UUID().uuidString
        model.restoreNotebook(problemId: problemID, backendURL: backendURL, userID: "student", assignmentAllowReveal: true)
        model.drawing = makeInk()
        model.selectedMode = .reveal
        model.applyAssignmentPolicy(false, problemId: problemID)
        XCTAssertEqual(model.selectedMode, .hint)
        XCTAssertEqual(model.availableModes, [.hint, .check_solution])
        XCTAssertEqual(model.drawing.strokes.count, 1)
        model.selectedMode = .check_solution
        model.applyAssignmentPolicy(true, problemId: problemID)
        XCTAssertEqual(model.selectedMode, .check_solution)
        XCTAssertTrue(model.availableModes.contains(.reveal))

        model.restoreNotebook(problemId: UUID().uuidString, backendURL: backendURL, userID: "student")
        model.applyAssignmentPolicy(false, problemId: problemID)
        XCTAssertNil(model.assignmentAllowReveal)
        XCTAssertTrue(model.availableModes.contains(.reveal))
    }

    func testDisabledRevealSubmissionIsStoppedBeforeImageEncodingOrNetworking() async {
        let model = NotebookViewModel()
        let problemID = UUID().uuidString
        model.restoreNotebook(problemId: problemID, backendURL: URL(string: "https://policy-test.example/")!, userID: "student", assignmentAllowReveal: false)
        model.drawing = makeInk()
        model.selectedMode = .reveal
        await model.submitQuery(authManager: AuthManager(), problemId: problemID, pipelineMode: nil)
        XCTAssertEqual(model.errorMessage, model.assignmentPolicyExplanation)
        XCTAssertNotNil(model.assignmentPolicyExplanation)
        XCTAssertEqual(model.selectedMode, .hint)
        XCTAssertEqual(model.drawing.strokes.count, 1)
        XCTAssertFalse(model.isSubmitting)
        XCTAssertFalse(model.canRetryLastSubmission)
    }

    func testForbiddenErrorKeepsReadableTeacherMessage() {
        let detail = "Kennarinn hefur slökkt á fullum lausnum í þessu verkefni."
        XCTAssertEqual(AppError.server(statusCode: 403, message: detail).errorDescription, detail)
    }

    func testTeacherPolicyAlsoBlocksRevealAfterACorrectAttemptWithoutChangingHistory() throws {
        let model = NotebookViewModel()
        let problemID = UUID().uuidString
        model.restoreNotebook(problemId: problemID, backendURL: URL(string: "https://policy-test.example/")!, userID: "student", assignmentAllowReveal: true)
        XCTAssertFalse(model.canRevealSolution)
        model.attempts = try JSONDecoder().decode([ProblemAttempt].self, from: Data("""
        [{"id":"attempt","problem_id":"\(problemID)","user_id":"student","mode":"check_solution","verdict":"fully_correct","message_is":"Eldri endurgjöf","created_at":"now"}]
        """.utf8))
        XCTAssertTrue(model.canRevealSolution)
        model.applyAssignmentPolicy(false, problemId: problemID)
        XCTAssertFalse(model.canRevealSolution)
        XCTAssertEqual(model.attempts.first?.message_is, "Eldri endurgjöf")
        model.applyAssignmentPolicy(true, problemId: problemID)
        XCTAssertTrue(model.canRevealSolution)
    }

    private func makeInk() -> PKDrawing {
        let point = PKStrokePoint(location: CGPoint(x: 20, y: 30), timeOffset: 0, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [point], creationDate: Date()))])
    }
}
