import XCTest
import PencilKit
import UIKit
@testable import ratatoskur

@MainActor
final class ClassroomSubmissionTests: XCTestCase {
    private let receipt = ClassroomSubmissionReceipt(id: "receipt", created_at: "2026-09-06T14:00:00Z", page_count: 1)

    func testServerReceiptRestoresAndOlderRefreshCannotReplaceIt() throws {
        let model = ClassroomSubmissionModel()
        let decoded = try JSONDecoder().decode(ClassroomSubmissionReceipt.self, from: Data("{\"id\":\"new\",\"created_at\":\"2026-09-06T14:01:00.123456+00:00\",\"page_count\":2}".utf8))
        XCTAssertNotNil(decoded.submittedDate)
        model.restoreReceipt(decoded)
        model.restoreReceipt(receipt)
        model.restoreReceipt(nil)
        XCTAssertEqual(model.receipt, decoded)
    }

    func testCancelledSendDoesNotShowAnUnconfirmedReceipt() async {
        let model = ClassroomSubmissionModel()
        let task = Task {
            await model.submit(pages: [Data([1])]) { _, _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return self.receipt
            }
        }
        await task.value
        XCTAssertNil(model.receipt)
        XCTAssertFalse(model.isSubmitting)
    }

    func testFailedSubmissionKeepsRetryIdentityAndDoesNotClaimSuccess() async {
        let model = ClassroomSubmissionModel()
        let pages = [Data("page".utf8)]
        var ids: [String] = []
        await model.submit(pages: pages) { id, _ in
            ids.append(id)
            throw AppError.message("Tenging rofnaði")
        }
        XCTAssertNil(model.receipt)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isSubmitting)
        await model.submit(pages: pages) { id, sent in
            ids.append(id)
            XCTAssertEqual(sent, pages)
            return self.receipt
        }
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(ids.first, ids.last)
        XCTAssertEqual(model.receipt, receipt)
        XCTAssertNil(model.errorMessage)
    }

    func testChangedPagesUseNewIdentityAfterFailure() async {
        let model = ClassroomSubmissionModel()
        var ids: [String] = []
        for text in ["first", "changed"] {
            await model.submit(pages: [Data(text.utf8)]) { id, _ in
                ids.append(id)
                throw AppError.message("Tenging rofnaði")
            }
        }
        XCTAssertNotEqual(ids.first, ids.last)
    }

    func testIntentionalResubmissionHasNewIdentityAndKeepsPriorReceiptOnFailure() async {
        let model = ClassroomSubmissionModel()
        var firstID: String?
        await model.submit(pages: [Data([1])]) { id, _ in
            firstID = id
            return self.receipt
        }
        await model.submit(pages: [Data([1])]) { id, _ in
            XCTAssertNotEqual(id, firstID)
            throw AppError.message("Tenging rofnaði")
        }
        XCTAssertEqual(model.receipt, receipt)
        XCTAssertNotNil(model.errorMessage)
    }

    func testConcurrentTapDoesNotSendAnotherSnapshot() async {
        let model = ClassroomSubmissionModel()
        await model.submit(pages: [Data([1])]) { _, _ in
            XCTAssertTrue(model.isSubmitting)
            await model.submit(pages: [Data([2])]) { _, _ in
                XCTFail("Duplicate submission")
                return self.receipt
            }
            return self.receipt
        }
        XCTAssertEqual(model.receipt, receipt)
    }

    func testEmptyPagesCannotCreateReceipt() async {
        let model = ClassroomSubmissionModel()
        await model.submit(pages: []) { _, _ in
            XCTFail("Empty submission must not reach network")
            return self.receipt
        }
        XCTAssertNil(model.receipt)
        XCTAssertNotNil(model.errorMessage)
    }

    func testClassroomCaptureRejectsEmptyRevealAndPreservesInkAcrossAllPages() throws {
        let model = NotebookViewModel()
        model.selectedMode = .reveal
        XCTAssertThrowsError(try model.makeClassroomSubmissionPages())
        let points = [CGPoint(x: 20, y: 20), CGPoint(x: 90, y: 80)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index), size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        model.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
        model.addPage()
        let before = model.pages.map { $0.drawing.dataRepresentation() }
        let captured = try model.makeClassroomSubmissionPages()
        XCTAssertEqual(captured.count, 2)
        XCTAssertTrue(captured.allSatisfy { UIImage(data: $0) != nil })
        XCTAssertEqual(model.pages.map { $0.drawing.dataRepresentation() }, before)
        XCTAssertEqual(model.selectedMode, .reveal)
    }

    func testAuthorizedMultipartSubmissionUsesClassEndpointAndOrderedPages() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SubmissionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); SubmissionURLProtocol.handler = nil }
        SubmissionURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/student/assignments/set/items/item/submissions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer student-token")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data;") == true)
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(buffer, count: count)
                }
            }
            let body = String(decoding: data, as: UTF8.self)
            for value in ["name=\"problem_id\"", "problem", "name=\"submission_id\"", "retry-id", "name=\"solution_pages\"", "first-page", "second-page"] {
                XCTAssertTrue(body.contains(value), value)
            }
            XCTAssertLessThan(body.range(of: "first-page")!.lowerBound, body.range(of: "second-page")!.lowerBound)
            XCTAssertFalse(body.contains("name=\"mode\""))
            return "{\"id\":\"receipt\",\"created_at\":\"2026-09-06T14:00:00Z\",\"page_count\":2}"
        }
        let store = SubmissionTokenStore()
        store.set("student-token", for: "mathcoach.access_token")
        let auth = AuthManager(api: APIClient(baseURL: URL(string: "https://submission.example/api/")!, session: session), keychain: store)
        let result = try await auth.submitClassroomWork(assignmentId: "set", itemId: "item", problemId: "problem", submissionId: "retry-id", pages: [Data("first-page".utf8), Data("second-page".utf8)])
        XCTAssertEqual(result.page_count, 2)
    }
}

private final class SubmissionURLProtocol: URLProtocol, @unchecked Sendable {
    @MainActor static var handler: ((URLRequest) -> String)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task { @MainActor in
            let body = Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@MainActor
private final class SubmissionTokenStore: TokenStore {
    private var values: [String: String] = [:]
    func set(_ value: String, for key: String) { values[key] = value }
    func get(_ key: String) -> String? { values[key] }
    func delete(_ key: String) { values.removeValue(forKey: key) }
}
