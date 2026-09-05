import XCTest
import PencilKit
import UIKit
@testable import ratatoskur

@MainActor
final class ProblemDraftIsolationTests: XCTestCase {
    func testClonedBackendsKeepDistinctInkImagesAndModesForSameProblem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let backendA = URL(string: "https://school.example/api-a/")!
        let backendB = URL(string: "https://school.example/api-b/")!
        let storeA = ProblemDraftStore(backendURL: backendA, userID: "same-student", baseDirectory: root)
        let storeB = ProblemDraftStore(backendURL: backendB, userID: "same-student", baseDirectory: root)
        let draftA = draft(x: 20, mode: .hint, imageMarker: 1)
        let draftB = draft(x: 70, mode: .check_solution, imageMarker: 2)
        try storeA.save(problemId: "same-problem", draft: draftA)
        XCTAssertNil(storeB.load(problemId: "same-problem"))
        try storeB.save(problemId: "same-problem", draft: draftB)
        let restoredA = try XCTUnwrap(storeA.load(problemId: "same-problem"))
        let restoredB = try XCTUnwrap(storeB.load(problemId: "same-problem"))
        XCTAssertEqual(try PKDrawing(data: restoredA.pages[0].drawingData).strokes[0].path[0].location.x, 20)
        XCTAssertEqual(try PKDrawing(data: restoredB.pages[0].drawingData).strokes[0].path[0].location.x, 70)
        XCTAssertEqual(restoredA.problemImageData, draftA.problemImageData)
        XCTAssertEqual(restoredB.problemImageData, draftB.problemImageData)
        XCTAssertEqual(restoredA.selectedMode, .hint)
        XCTAssertEqual(restoredB.selectedMode, .check_solution)
        storeB.delete(problemId: "same-problem")
        XCTAssertNotNil(storeA.load(problemId: "same-problem"))
        XCTAssertNil(storeB.load(problemId: "same-problem"))
    }

    func testCapturedStoreDoesNotFollowChangedBackendAndUsersStayIsolated() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previousAddress = UserDefaults.standard.string(forKey: AppConfig.backendOverrideKey)
        defer {
            try? FileManager.default.removeItem(at: root)
            if let previousAddress { UserDefaults.standard.set(previousAddress, forKey: AppConfig.backendOverrideKey) }
            else { UserDefaults.standard.removeObject(forKey: AppConfig.backendOverrideKey) }
        }
        UserDefaults.standard.set("https://first.example/", forKey: AppConfig.backendOverrideKey)
        let capturedStore = ProblemDraftStore(backendURL: AppConfig.baseURL, userID: "student-a", baseDirectory: root)
        UserDefaults.standard.set("https://second.example/", forKey: AppConfig.backendOverrideKey)
        try capturedStore.save(problemId: "same-problem", draft: draft(x: 10, mode: .hint, imageMarker: 1))
        let newBackendStore = ProblemDraftStore(backendURL: AppConfig.baseURL, userID: "student-a", baseDirectory: root)
        let newUserStore = ProblemDraftStore(backendURL: URL(string: "https://first.example/")!, userID: "student-b", baseDirectory: root)
        XCTAssertNil(newBackendStore.load(problemId: "same-problem"))
        XCTAssertNil(newUserStore.load(problemId: "same-problem"))
        XCTAssertNotNil(capturedStore.load(problemId: "same-problem"))
    }

    func testUnknownLegacyDraftIsRetainedAndNeverAdoptedByAnotherScope() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("same-problem")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let legacyDrawing = PKDrawing().dataRepresentation()
        try legacyDrawing.write(to: legacy.appendingPathComponent("drawing.data"))
        let metadata = Data("{\"selectedMode\":\"hint\",\"updatedAt\":0}".utf8)
        try metadata.write(to: legacy.appendingPathComponent("metadata.json"))
        let store = ProblemDraftStore(backendURL: URL(string: "https://new.example/")!, userID: "student", baseDirectory: root)
        XCTAssertNil(store.load(problemId: "same-problem"))
        XCTAssertTrue(store.hasUnscopedLegacyDraft(problemId: "same-problem"))
        try store.save(problemId: "same-problem", draft: draft(x: 90, mode: .check_solution, imageMarker: 3))
        store.delete(problemId: "same-problem")
        XCTAssertEqual(try Data(contentsOf: legacy.appendingPathComponent("drawing.data")), legacyDrawing)
        XCTAssertEqual(try Data(contentsOf: legacy.appendingPathComponent("metadata.json")), metadata)
    }

    func testRebindingNotebookDoesNotCarryUnsavedImageOrModeIntoAnotherServer() {
        let problemID = UUID().uuidString
        let model = NotebookViewModel()
        let firstURL = URL(string: "https://first.example/")!
        let secondURL = URL(string: "https://second.example/")!
        model.restoreNotebook(problemId: problemID, backendURL: firstURL, userID: "same-user", assignedImage: UIImage())
        model.selectedMode = .check_solution
        model.restoreNotebook(problemId: problemID, backendURL: secondURL, userID: "same-user")
        XCTAssertNil(model.problemImage)
        XCTAssertEqual(model.selectedMode, .hint)
        XCTAssertTrue(model.drawing.strokes.isEmpty)
    }

    private func draft(x: CGFloat, mode: QueryMode, imageMarker: UInt8) -> ProblemDraft {
        let point = PKStrokePoint(location: CGPoint(x: x, y: 30), timeOffset: 0, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        let ink = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [point], creationDate: Date()))])
        return ProblemDraft(pages: [ProblemDraftPage(id: "page-1", drawingData: ink.dataRepresentation(), order: 0, createdAt: Date(), updatedAt: Date())], problemImageData: Data([imageMarker]), selectedMode: mode, selectedExpertMode: .off, selectedPageId: "page-1")
    }
}
