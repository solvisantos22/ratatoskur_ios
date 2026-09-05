import XCTest
import PencilKit
import UIKit
@testable import ratatoskur

@MainActor
final class ClassroomTests: XCTestCase {
    func testAssignmentsDecodeUnstartedAndStartedItems() throws {
        let data = Data("""
        [{"id":"set-1","class_id":"class-1","class_name":"8. bekkur","title":"Brot","item_count":2,"created_at":"2026-09-05T12:00:00Z","items":[{"id":"item-1","title":"Fyrsta dæmi","position":0,"image_url":"https://example.com/1?token=abc","problem_id":null},{"id":"item-2","title":"Annað dæmi","position":1,"image_url":"https://example.com/2","problem_id":"problem-2"}]}]
        """.utf8)
        let assignments = try JSONDecoder().decode([StudentAssignment].self, from: data)
        XCTAssertEqual(assignments.first?.class_name, "8. bekkur")
        XCTAssertEqual(assignments.first?.items.count, 2)
        XCTAssertNil(assignments.first?.items.first?.problem_id)
        XCTAssertEqual(assignments.first?.items.last?.problem_id, "problem-2")
        XCTAssertEqual(assignments.first?.items.first?.position, 0)
    }

    func testStartResponseUsesPersistentProblemAndSignedImage() throws {
        let data = Data("""
        {"problem":{"id":"problem-2","user_id":"student-1","folder_id":null,"folder_name":null,"title":"Annað dæmi","created_at":"2026-09-05T12:00:00Z","updated_at":"2026-09-05T12:00:00Z","assignment_id":"set-1","assignment_item_id":"item-2","assignment_image_url":"https://example.com/image?fresh=1"},"image_url":"https://example.com/image?fresh=1"}
        """.utf8)
        let response = try JSONDecoder().decode(StudentAssignmentStartResponse.self, from: data)
        XCTAssertEqual(response.problem.id, "problem-2")
        XCTAssertTrue(response.problem.isAssigned)
        XCTAssertEqual(response.problem.assignment_item_id, "item-2")
        XCTAssertEqual(response.image_url.query, "fresh=1")
    }

    func testPersonalProblemRemainsPersonalWithoutAssignmentFields() throws {
        let data = Data("""
        {"id":"personal","user_id":"student-1","title":"Mitt dæmi","created_at":"now","updated_at":"now"}
        """.utf8)
        let problem = try JSONDecoder().decode(ProblemSummary.self, from: data)
        XCTAssertFalse(problem.isAssigned)
    }

    func testClassJoinDecodesCountsAndEncodesCode() throws {
        let classroom = try JSONDecoder().decode(StudentClass.self, from: Data("""
        {"id":"class-1","name":"8. bekkur","join_code":"ABC123","student_count":12}
        """.utf8))
        XCTAssertEqual(classroom.student_count, 12)
        let request = try JSONEncoder().encode(StudentClassJoinRequest(join_code: "ABC123"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: request) as? [String: String], ["join_code": "ABC123"])
    }

    func testBackendURLValidationRejectsEmbeddedCredentialsAndNonHTTPURLs() throws {
        XCTAssertEqual(try AppConfig.validatedBackendURL("  https://example.com/api  ").absoluteString, "https://example.com/api/")
        for invalid in ["", "192.168.1.3:8000", "file:///etc/passwd", "https://user:secret@example.com", "https://example.com/?token=secret", "https://example.com/#test"] {
            XCTAssertThrowsError(try AppConfig.validatedBackendURL(invalid), invalid)
        }
        #if DEBUG
        XCTAssertEqual(try AppConfig.validatedBackendURL("http://192.168.1.3:8000").host, "192.168.1.3")
        #endif
    }

    func testAssignedImageRestorationPreservesHandwritingPagesAndMode() throws {
        let problemID = UUID().uuidString
        let backendURL = URL(string: "https://draft-test.example/")!
        let userID = "draft-test-student"
        let store = ProblemDraftStore(backendURL: backendURL, userID: userID)
        defer { store.delete(problemId: problemID) }
        let point = PKStrokePoint(location: CGPoint(x: 20, y: 30), timeOffset: 0, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        let path = PKStrokePath(controlPoints: [point], creationDate: Date())
        let ink = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
        let draft = ProblemDraft(pages: [ProblemDraftPage(id: "page-1", drawingData: ink.dataRepresentation(), order: 0, createdAt: Date(), updatedAt: Date())], problemImageData: nil, selectedMode: .check_solution, selectedExpertMode: .off, selectedPageId: "page-1")
        try store.save(problemId: problemID, draft: draft)
        let originalImage = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 80)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        }
        let model = NotebookViewModel()
        model.restoreNotebook(problemId: problemID, backendURL: backendURL, userID: userID, assignedImage: originalImage)
        XCTAssertEqual(model.pages.map(\.id), ["page-1"])
        XCTAssertEqual(model.drawing.strokes.count, 1)
        XCTAssertEqual(model.drawing.strokes.first?.path.first?.location, point.location)
        XCTAssertEqual(model.selectedMode, .check_solution)
        XCTAssertTrue(model.problemImage === originalImage)
        model.flushAutosaveNow(problemId: problemID)
        let reopened = NotebookViewModel()
        reopened.restoreNotebook(problemId: problemID, backendURL: backendURL, userID: userID, assignedImage: originalImage)
        XCTAssertEqual(reopened.drawing.strokes.count, 1)
        XCTAssertEqual(reopened.pages.first?.id, "page-1")
    }
}
