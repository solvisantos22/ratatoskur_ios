import XCTest
import PencilKit
import UIKit
@testable import ratatoskur

@MainActor
final class ClassroomAPITests: XCTestCase {
    func testTeacherDisablingRevealDuringOpenNotebookPreservesInkAndStopsRetry() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClassroomStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); ClassroomStubURLProtocol.handler = nil }
        let detail = "Kennarinn hefur slökkt á fullum lausnum í þessu verkefni."
        var queryCount = 0
        ClassroomStubURLProtocol.handler = { request in
            if request.url?.path == "/auth/me" {
                return (200, "{\"id\":\"student\",\"email\":\"student@example.com\"}")
            }
            XCTAssertEqual(request.url?.path, "/query")
            queryCount += 1
            return (403, "{\"detail\":\"\(detail)\"}")
        }
        let keychain = MemoryTokenStore()
        keychain.set("student-token", for: "mathcoach.access_token")
        let backendURL = URL(string: "https://policy-test.example/")!
        let auth = AuthManager(api: APIClient(baseURL: backendURL, session: session), keychain: keychain)
        await auth.bootstrap()
        for initialPolicy in [true, nil] as [Bool?] {
            queryCount = 0
            let problemID = UUID().uuidString
            let model = NotebookViewModel()
            model.restoreNotebook(problemId: problemID, backendURL: backendURL, userID: "student", assignmentAllowReveal: initialPolicy)
            let point = PKStrokePoint(location: CGPoint(x: 20, y: 30), timeOffset: 0, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            model.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [point], creationDate: Date()))])
            model.problemImage = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            }
            model.selectedMode = .reveal
            await model.submitQuery(authManager: auth, problemId: problemID, pipelineMode: nil)
            XCTAssertEqual(queryCount, 1)
            XCTAssertEqual(model.errorMessage, detail)
            XCTAssertEqual(model.assignmentAllowReveal, false)
            XCTAssertEqual(model.selectedMode, .hint)
            XCTAssertEqual(model.drawing.strokes.first?.path.first?.location, point.location)
            XCTAssertFalse(model.canRetryLastSubmission)
            await model.retryLastSubmission(authManager: auth)
            XCTAssertEqual(queryCount, 1)
        }
    }

    func testStudentRequestsUseBearerAuthAndExpectedRoutes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClassroomStubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = APIClient(baseURL: URL(string: "https://school.example/api/")!, session: session)
        ClassroomStubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer student-token")
            switch request.url!.path {
            case "/api/student/classes":
                XCTAssertEqual(request.httpMethod, "GET")
                return (200, "[]")
            case "/api/student/classes/join":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
                return (200, "{\"id\":\"class\",\"name\":\"Bekkur\",\"join_code\":\"ABC123\",\"student_count\":1}")
            case "/api/student/assignments":
                XCTAssertEqual(request.httpMethod, "GET")
                return (200, "[]")
            case "/api/student/assignments/set/items/item/start":
                XCTAssertEqual(request.httpMethod, "POST")
                return (200, "{\"problem\":{\"id\":\"same-problem\",\"user_id\":\"student\",\"title\":\"Dæmi\",\"created_at\":\"now\",\"updated_at\":\"now\",\"assignment_id\":\"set\",\"assignment_item_id\":\"item\"},\"image_url\":\"https://storage.example/image?fresh=1\"}")
            default:
                XCTFail("Unexpected route: \(request.url!.path)")
                return (404, "{}")
            }
        }
        let classes = try await api.listStudentClasses(accessToken: "student-token")
        XCTAssertTrue(classes.isEmpty)
        let joined = try await api.joinStudentClass(code: "ABC123", accessToken: "student-token")
        XCTAssertEqual(joined.id, "class")
        let assignments = try await api.listStudentAssignments(accessToken: "student-token")
        XCTAssertTrue(assignments.isEmpty)
        let first = try await api.startStudentAssignment(assignmentId: "set", itemId: "item", accessToken: "student-token")
        let reopened = try await api.startStudentAssignment(assignmentId: "set", itemId: "item", accessToken: "student-token")
        XCTAssertEqual(first.problem.id, reopened.problem.id)
        XCTAssertTrue(reopened.problem.isAssigned)
    }

    func testChangingBackendClearsOldCredentialsAndCookies() async throws {
        let keychain = MemoryTokenStore()
        let draftRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: draftRoot) }
        let oldDrafts = ProblemDraftStore(backendURL: URL(string: "https://old.example/")!, userID: "student", baseDirectory: draftRoot)
        let newDrafts = ProblemDraftStore(backendURL: URL(string: "https://new.example/")!, userID: "student", baseDirectory: draftRoot)
        let page = ProblemDraftPage(id: "page", drawingData: PKDrawing().dataRepresentation(), order: 0, createdAt: Date(), updatedAt: Date())
        try oldDrafts.save(problemId: "same-problem", draft: ProblemDraft(pages: [page], problemImageData: Data([1]), selectedMode: .hint, selectedExpertMode: .off, selectedPageId: "page"))
        try newDrafts.save(problemId: "same-problem", draft: ProblemDraft(pages: [page], problemImageData: Data([2]), selectedMode: .check_solution, selectedExpertMode: .off, selectedPageId: "page"))
        let tokenKey = "mathcoach.access_token"
        let previousToken = keychain.get(tokenKey)
        let previousAddress = UserDefaults.standard.string(forKey: AppConfig.backendOverrideKey)
        defer {
            if let previousToken { keychain.set(previousToken, for: tokenKey) } else { keychain.delete(tokenKey) }
            if let previousAddress { UserDefaults.standard.set(previousAddress, forKey: AppConfig.backendOverrideKey) }
            else { UserDefaults.standard.removeObject(forKey: AppConfig.backendOverrideKey) }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClassroomStubURLProtocol.self]
        let storage = try XCTUnwrap(configuration.httpCookieStorage)
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "old.example", .path: "/", .name: "refresh_token", .value: "old-refresh"]))
        storage.setCookie(cookie)
        ClassroomStubURLProtocol.handler = { _ in (401, "{}") }
        let api = APIClient(baseURL: URL(string: "https://old.example/")!, session: URLSession(configuration: configuration))
        let auth = AuthManager(api: api, keychain: keychain)
        await auth.bootstrap()
        keychain.set("old-bearer", for: tokenKey)
        XCTAssertEqual(keychain.get(tokenKey), "old-bearer")
        try auth.changeBackend(to: "https://new.example/")
        XCTAssertNil(keychain.get(tokenKey))
        XCTAssertFalse(storage.cookies?.contains { $0.name == "refresh_token" } ?? false)
        XCTAssertEqual(AppConfig.baseURL.absoluteString, "https://new.example/")
        XCTAssertEqual(oldDrafts.load(problemId: "same-problem")?.problemImageData, Data([1]))
        XCTAssertEqual(newDrafts.load(problemId: "same-problem")?.problemImageData, Data([2]))
        XCTAssertEqual(oldDrafts.load(problemId: "same-problem")?.selectedMode, .hint)
        XCTAssertEqual(newDrafts.load(problemId: "same-problem")?.selectedMode, .check_solution)
        guard case .unauthenticated = auth.status else { return XCTFail("Expected fresh login") }
    }

    func testBackendChangeCannotInterruptAnAuthenticatedSession() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClassroomStubURLProtocol.self]
        let keychain = MemoryTokenStore()
        let previousToken = keychain.get("mathcoach.access_token")
        defer {
            if let previousToken { keychain.set(previousToken, for: "mathcoach.access_token") }
            else { keychain.delete("mathcoach.access_token") }
        }
        ClassroomStubURLProtocol.handler = { request in
            if request.url?.path == "/auth/login" {
                return (200, "{\"access_token\":\"new-token\",\"token_type\":\"bearer\"}")
            }
            return (200, "{\"id\":\"student\",\"email\":\"student@example.com\"}")
        }
        let api = APIClient(baseURL: URL(string: "https://school.example/")!, session: URLSession(configuration: configuration))
        let auth = AuthManager(api: api, keychain: keychain)
        await auth.login(email: "student@example.com", password: "example")
        XCTAssertNotNil(auth.currentUser)
        XCTAssertThrowsError(try auth.changeBackend(to: "https://other.example/"))
        XCTAssertEqual(keychain.get("mathcoach.access_token"), "new-token")
    }
}

private final class ClassroomStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private final class MemoryTokenStore: TokenStore {
    private var values: [String: String] = [:]
    func set(_ value: String, for key: String) { values[key] = value }
    func get(_ key: String) -> String? { values[key] }
    func delete(_ key: String) { values.removeValue(forKey: key) }
}
