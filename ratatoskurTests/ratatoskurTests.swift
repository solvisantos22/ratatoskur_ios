import XCTest
@testable import ratatoskur

final class ratatoskurTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testQueryContractFixturesDecode() throws {
        let fixtureNames = [
            "query_check_solution_correct",
            "query_hint",
            "query_reveal",
            "query_confirm_reading",
            "query_ask_clarification"
        ]

        for fixtureName in fixtureNames {
            let response = try decodeQueryFixture(named: fixtureName)
            XCTAssertFalse(response.response_type?.isEmpty ?? true, "\(fixtureName) missing response_type")
            XCTAssertFalse(response.message_is?.isEmpty ?? true, "\(fixtureName) missing message_is")
            XCTAssertNotNil(response.observability?.requestId, "\(fixtureName) missing observability.requestId")
        }
    }

    func testConfirmReadingDecodesEditableFieldsAndAmbiguousRegions() throws {
        let response = try decodeQueryFixture(named: "query_confirm_reading")

        XCTAssertEqual(response.response_type, "confirm_reading")
        XCTAssertEqual(response.reading_confidence, 0.68)
        XCTAssertEqual(response.interpreted_reading?.first?.text, "2x + 3 = 11")
        XCTAssertEqual(response.ambiguous_regions?.first?.page, 1)
        XCTAssertEqual(response.ambiguous_regions?.first?.snippet, "2x + ? = 11")
    }

    func testLegacyAmbiguousStepsDecodesAsAmbiguousRegions() throws {
        let json = """
        {
          "verdict": "unclear",
          "response_type": "ask_clarification",
          "message_is": "Clarify this step.",
          "ambiguous_steps": [
            {
              "page": 2,
              "snippet": "x = ?",
              "reason": "answer is unclear"
            }
          ]
        }
        """

        let response = try decoder.decode(QueryResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.ambiguous_regions?.count, 1)
        XCTAssertEqual(response.ambiguous_regions?.first?.page, 2)
        XCTAssertEqual(response.ambiguous_regions?.first?.reason, "answer is unclear")
    }

    private func decodeQueryFixture(named name: String) throws -> QueryResponse {
        let url = try fixtureURL(named: name)
        let data = try Data(contentsOf: url)
        return try decoder.decode(QueryResponse.self, from: data)
    }

    private func fixtureURL(named name: String) throws -> URL {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot
            .appendingPathComponent("api_contract_examples")
            .appendingPathComponent("\(name).json")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        throw XCTSkip("Fixture not found at \(url.path)")
    }
}
