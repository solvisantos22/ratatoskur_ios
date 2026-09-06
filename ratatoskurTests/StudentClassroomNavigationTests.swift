import XCTest
@testable import ratatoskur

@MainActor
final class StudentClassroomNavigationTests: XCTestCase {
    func testLoadLeavesCourseChoiceToStudent() async throws {
        let fixture = NavigationFixture()
        defer { fixture.close() }
        let model = StudentClassroomModel()

        await model.load(auth: fixture.auth)

        XCTAssertEqual(model.classes.count, 2)
        XCTAssertNil(model.selectedClassID)
        XCTAssertTrue(model.selectedAssignments.isEmpty)
    }

    func testSwitchingCourseDropsDelayedExerciseResponse() async throws {
        let fixture = NavigationFixture()
        defer { fixture.close() }
        let model = StudentClassroomModel()
        await model.load(auth: fixture.auth)
        model.selectClass("class-a")
        model.navigationPath = [.assignment("assignment-a")]
        let assignment = try XCTUnwrap(model.selectedAssignments.first)
        let item = try XCTUnwrap(assignment.items.first)
        let started = expectation(description: "Exercise request started")
        fixture.delay(itemID: item.id, until: started)
        let opening = Task { await model.open(assignment: assignment, item: item, auth: fixture.auth) }
        await fulfillment(of: [started], timeout: 2)

        model.selectClass("class-b")
        fixture.complete(itemID: item.id)
        let result = await opening.value

        XCTAssertNil(result)
        XCTAssertEqual(model.selectedClassID, "class-b")
        XCTAssertNil(model.openingItemID)
        XCTAssertNil(model.errorMessage)
    }

    func testRefreshPreservesExistingCourseAndAssignment() async {
        let fixture = NavigationFixture()
        defer { fixture.close() }
        let model = await fixture.loadedAssignment()

        await model.load(auth: fixture.auth)

        XCTAssertEqual(model.selectedClass?.name, "Algebra")
        XCTAssertEqual(model.selectedAssignments.map(\.id), ["assignment-a"])
        XCTAssertEqual(model.navigationPath, [.assignment("assignment-a")])
    }

    func testRefreshReturnsToOverviewWhenSelectedCourseDisappears() async {
        let fixture = NavigationFixture()
        defer { fixture.close() }
        let model = await fixture.loadedAssignment()
        fixture.classesJSON = "[{\"id\":\"class-b\",\"name\":\"Geometry\",\"join_code\":\"BBBBBB\",\"student_count\":3}]"

        await model.load(auth: fixture.auth)

        XCTAssertNil(model.selectedClassID)
        XCTAssertNil(model.selectedClass)
        XCTAssertTrue(model.navigationPath.isEmpty)
        XCTAssertTrue(model.selectedAssignments.isEmpty)
    }

    func testPoppingAssignmentDropsDelayedExerciseResponse() async throws {
        let fixture = NavigationFixture()
        defer { fixture.close() }
        let model = await fixture.loadedAssignment()
        let assignment = try XCTUnwrap(model.selectedAssignments.first)
        let item = try XCTUnwrap(assignment.items.first)
        let started = expectation(description: "Exercise request started")
        fixture.delay(itemID: item.id, until: started)
        let opening = Task { await model.open(assignment: assignment, item: item, auth: fixture.auth) }
        await fulfillment(of: [started], timeout: 2)

        model.navigationPath.removeLast()
        fixture.complete(itemID: item.id)
        let result = await opening.value

        XCTAssertNil(result)
        XCTAssertEqual(model.selectedClassID, "class-a")
        XCTAssertTrue(model.navigationPath.isEmpty)
        XCTAssertNil(model.openingItemID)
    }

    func testSelectingSameCourseResetsPathErrorAndPendingOpen() async throws {
        let fixture = NavigationFixture()
        defer { fixture.close() }
        let model = await fixture.loadedAssignment()
        let assignment = try XCTUnwrap(model.selectedAssignments.first)
        let item = try XCTUnwrap(assignment.items.first)
        let started = expectation(description: "Exercise request started")
        fixture.delay(itemID: item.id, until: started)
        let opening = Task { await model.open(assignment: assignment, item: item, auth: fixture.auth) }
        await fulfillment(of: [started], timeout: 2)
        model.errorMessage = "Previous error"

        model.selectClass("class-a")

        XCTAssertEqual(model.selectedClassID, "class-a")
        XCTAssertTrue(model.navigationPath.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.openingItemID)
        fixture.complete(itemID: item.id)
        let result = await opening.value
        XCTAssertNil(result)

        model.errorMessage = "Another error"
        model.selectClass("class-a")
        XCTAssertNil(model.errorMessage)
    }

    func testReturningToOverviewDropsDelayedError() async throws {
        let fixture = NavigationFixture()
        defer { fixture.close() }
        let model = await fixture.loadedAssignment()
        let assignment = try XCTUnwrap(model.selectedAssignments.first)
        let item = try XCTUnwrap(assignment.items.first)
        let started = expectation(description: "Exercise request started")
        fixture.delay(itemID: item.id, until: started)
        let opening = Task { await model.open(assignment: assignment, item: item, auth: fixture.auth) }
        await fulfillment(of: [started], timeout: 2)

        model.selectClass(nil)
        fixture.complete(itemID: item.id, status: 500)
        let result = await opening.value

        XCTAssertNil(result)
        XCTAssertNil(model.selectedClass)
        XCTAssertTrue(model.navigationPath.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testOldCompletionCannotClearNewCourseOpeningIndicator() async throws {
        let fixture = NavigationFixture()
        defer { fixture.close() }
        let model = await fixture.loadedAssignment()
        let assignmentA = try XCTUnwrap(model.selectedAssignments.first)
        let itemA = try XCTUnwrap(assignmentA.items.first)
        let startedA = expectation(description: "Course A exercise request started")
        fixture.delay(itemID: itemA.id, until: startedA)
        let openingA = Task { await model.open(assignment: assignmentA, item: itemA, auth: fixture.auth) }
        await fulfillment(of: [startedA], timeout: 2)

        model.selectClass("class-b")
        model.navigationPath = [.assignment("assignment-b")]
        let assignmentB = try XCTUnwrap(model.selectedAssignments.first)
        let itemB = try XCTUnwrap(assignmentB.items.first)
        let startedB = expectation(description: "Course B exercise request started")
        fixture.delay(itemID: itemB.id, until: startedB)
        let openingB = Task { await model.open(assignment: assignmentB, item: itemB, auth: fixture.auth) }
        await fulfillment(of: [startedB], timeout: 2)

        fixture.complete(itemID: itemA.id)
        let resultA = await openingA.value
        XCTAssertNil(resultA)
        XCTAssertEqual(model.openingItemID, itemB.id)

        fixture.complete(itemID: itemB.id)
        let resultB = await openingB.value
        XCTAssertEqual(resultB?.problem.id, "problem-b")
        XCTAssertNil(model.openingItemID)
    }

    func testCurrentAssignmentExerciseOpensSuccessfully() async throws {
        let fixture = NavigationFixture()
        defer { fixture.close() }
        let model = await fixture.loadedAssignment()
        let assignment = try XCTUnwrap(model.selectedAssignments.first)
        let item = try XCTUnwrap(assignment.items.first)

        let result = await model.open(assignment: assignment, item: item, auth: fixture.auth)

        XCTAssertEqual(result?.problem.id, "problem-a")
        XCTAssertEqual(model.navigationPath, [.assignment(assignment.id)])
        XCTAssertNil(model.openingItemID)
        XCTAssertNil(model.errorMessage)
    }

    func testOpenRequiresSelectedCourseAndCurrentAssignment() async throws {
        let fixture = NavigationFixture()
        defer { fixture.close() }
        let model = await fixture.loadedAssignment()
        let assignment = try XCTUnwrap(model.selectedAssignments.first)
        let item = try XCTUnwrap(assignment.items.first)
        model.selectClass(nil)
        let overviewResult = await model.open(assignment: assignment, item: item, auth: fixture.auth)
        XCTAssertNil(overviewResult)

        model.selectClass("class-b")
        model.navigationPath = [.assignment(assignment.id)]
        let wrongCourseResult = await model.open(assignment: assignment, item: item, auth: fixture.auth)
        XCTAssertNil(wrongCourseResult)

        model.selectClass("class-a")
        let courseRootResult = await model.open(assignment: assignment, item: item, auth: fixture.auth)
        XCTAssertNil(courseRootResult)
        XCTAssertEqual(fixture.startRequestCount, 0)
    }

    func testCancelledOpenDoesNotShowError() async throws {
        let fixture = NavigationFixture()
        defer { fixture.close() }
        let model = await fixture.loadedAssignment()
        let assignment = try XCTUnwrap(model.selectedAssignments.first)
        let item = try XCTUnwrap(assignment.items.first)
        let started = expectation(description: "Exercise request started")
        fixture.delay(itemID: item.id, until: started)
        let opening = Task { await model.open(assignment: assignment, item: item, auth: fixture.auth) }
        await fulfillment(of: [started], timeout: 2)

        opening.cancel()
        let result = await opening.value

        XCTAssertNil(result)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.openingItemID)
    }

    func testJoiningCourseSelectsItAndResetsNavigation() async {
        let fixture = NavigationFixture()
        defer { fixture.close() }
        let model = await fixture.loadedAssignment()
        model.joinCode = "  bbbbbb  "

        let joined = await model.join(auth: fixture.auth)

        XCTAssertTrue(joined)
        XCTAssertEqual(model.selectedClass?.id, "class-b")
        XCTAssertTrue(model.navigationPath.isEmpty)
        XCTAssertTrue(model.joinCode.isEmpty)
    }

    func testJoinedCourseAndRefreshErrorRemainAvailableUntilReloadSucceeds() async {
        let fixture = NavigationFixture()
        defer { fixture.close() }
        let refreshedClasses = fixture.classesJSON
        fixture.classesJSON = "[{\"id\":\"class-a\",\"name\":\"Algebra\",\"join_code\":\"AAAAAA\",\"student_count\":2}]"
        let model = await fixture.loadedAssignment()
        model.joinCode = "BBBBBB"
        fixture.classesJSON = refreshedClasses
        fixture.classesStatus = 503

        let joined = await model.join(auth: fixture.auth)

        XCTAssertTrue(joined)
        XCTAssertEqual(model.selectedClass?.id, "class-b")
        XCTAssertEqual(model.errorMessage, "Villa í netþjóni (503). Reyndu aftur eftir smá stund.")
        XCTAssertTrue(model.navigationPath.isEmpty)
        XCTAssertTrue(model.joinCode.isEmpty)

        fixture.classesStatus = 200
        await model.load(auth: fixture.auth)

        XCTAssertEqual(model.selectedClass?.id, "class-b")
        XCTAssertEqual(model.selectedAssignments.map(\.id), ["assignment-b"])
        XCTAssertNil(model.errorMessage)
    }
}

@MainActor
private final class NavigationFixture {
    let auth: AuthManager
    private let session: URLSession
    var classesJSON = """
    [{"id":"class-a","name":"Algebra","join_code":"AAAAAA","student_count":2},
     {"id":"class-b","name":"Geometry","join_code":"BBBBBB","student_count":3}]
    """
    var classesStatus = 200
    private var expectedStarts: [String: XCTestExpectation] = [:]
    private var pending: [String: NavigationURLProtocol] = [:]
    private(set) var startRequestCount = 0

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NavigationURLProtocol.self]
        session = URLSession(configuration: configuration)
        let tokenStore = NavigationTokenStore()
        tokenStore.set("student-token", for: "mathcoach.access_token")
        auth = AuthManager(api: APIClient(baseURL: URL(string: "https://navigation.example/")!, session: session), keychain: tokenStore)
        NavigationURLProtocol.handler = { [weak self] request in self?.handle(request) }
    }

    func delay(itemID: String, until expectation: XCTestExpectation) {
        expectedStarts[itemID] = expectation
    }

    func loadedAssignment() async -> StudentClassroomModel {
        let model = StudentClassroomModel()
        await model.load(auth: auth)
        model.selectClass("class-a")
        model.navigationPath = [.assignment("assignment-a")]
        return model
    }

    func complete(itemID: String, status: Int = 200) {
        guard let request = pending.removeValue(forKey: itemID) else {
            return XCTFail("No pending exercise request for \(itemID)")
        }
        request.respond(status: status, body: status == 200 ? Self.startJSON(itemID: itemID) : "{\"detail\":\"Could not open exercise\"}")
    }

    func close() {
        session.invalidateAndCancel()
        NavigationURLProtocol.handler = nil
    }

    private func handle(_ request: NavigationURLProtocol) {
        switch request.request.url!.path {
        case "/student/classes":
            request.respond(status: classesStatus, body: classesStatus == 200 ? classesJSON : "{\"detail\":\"Course refresh unavailable\"}")
        case "/student/classes/join":
            request.respond(body: "{\"id\":\"class-b\",\"name\":\"Geometry\",\"join_code\":\"BBBBBB\",\"student_count\":3}")
        case "/student/assignments":
            request.respond(body: """
            [{"id":"assignment-a","class_id":"class-a","class_name":"Algebra","title":"Fractions","item_count":1,"created_at":"now","items":[{"id":"item-a","title":"First exercise","position":0,"image_url":"https://images.example/a","problem_id":null}]},
             {"id":"assignment-b","class_id":"class-b","class_name":"Geometry","title":"Shapes","item_count":1,"created_at":"now","items":[{"id":"item-b","title":"Second exercise","position":0,"image_url":"https://images.example/b","problem_id":null}]}]
            """)
        case let path where path.hasSuffix("/start"):
            startRequestCount += 1
            let itemID = request.request.url!.pathComponents.dropLast().last!
            if let started = expectedStarts.removeValue(forKey: itemID) {
                pending[itemID] = request
                started.fulfill()
            } else {
                request.respond(body: Self.startJSON(itemID: itemID))
            }
        default:
            XCTFail("Unexpected navigation request: \(request.request.url!.path)")
            request.respond(status: 404, body: "{}")
        }
    }

    private static func startJSON(itemID: String) -> String {
        let suffix = itemID == "item-a" ? "a" : "b"
        return """
        {"problem":{"id":"problem-\(suffix)","user_id":"student","title":"Exercise","created_at":"now","updated_at":"now","assignment_id":"assignment-\(suffix)","assignment_item_id":"\(itemID)"},"image_url":"https://images.example/\(suffix)"}
        """
    }
}

private final class NavigationURLProtocol: URLProtocol, @unchecked Sendable {
    @MainActor static var handler: ((NavigationURLProtocol) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task { @MainActor in Self.handler?(self) }
    }
    override func stopLoading() {}

    func respond(status: Int = 200, body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
private final class NavigationTokenStore: TokenStore {
    private var values: [String: String] = [:]
    func set(_ value: String, for key: String) { values[key] = value }
    func get(_ key: String) -> String? { values[key] }
    func delete(_ key: String) { values.removeValue(forKey: key) }
}
