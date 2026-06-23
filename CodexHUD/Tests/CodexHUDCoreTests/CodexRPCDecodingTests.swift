import XCTest
@testable import CodexHUDCore

final class CodexRPCDecodingTests: XCTestCase {
    func testMapsCodexAppServerRateLimitsIntoUsageSnapshot() throws {
        let rateLimitsJSON = """
        {
          "rateLimitResetCredits": { "availableCount": 1 },
          "rateLimits": {
            "credits": { "balance": "0", "hasCredits": false, "unlimited": false },
            "planType": "plus",
            "primary": { "resetsAt": 1782155126, "usedPercent": 37, "windowDurationMins": 300 },
            "secondary": { "resetsAt": 1782713648, "usedPercent": 36, "windowDurationMins": 10080 }
          }
        }
        """
        let accountJSON = """
        {
          "account": {
            "email": "office@example.com",
            "planType": "plus",
            "type": "chatgpt"
          },
          "requiresOpenaiAuth": true
        }
        """
        let decoder = JSONDecoder()
        let rateLimits = try decoder.decode(CodexRateLimitsRPCResult.self, from: Data(rateLimitsJSON.utf8))
        let account = try decoder.decode(CodexAccountRPCResult.self, from: Data(accountJSON.utf8))

        let snapshot = CodexRPCMapper.snapshot(
            rateLimits: rateLimits,
            account: account,
            updatedAt: Date(timeIntervalSince1970: 1_782_100_000))

        XCTAssertEqual(snapshot.primary?.usedPercent, 37)
        XCTAssertEqual(snapshot.primary?.windowMinutes, 300)
        XCTAssertEqual(snapshot.primary?.resetsAt, Date(timeIntervalSince1970: 1_782_155_126))
        XCTAssertEqual(snapshot.secondary?.usedPercent, 36)
        XCTAssertEqual(snapshot.secondary?.windowMinutes, 10_080)
        XCTAssertEqual(snapshot.accountEmail, "office@example.com")
        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.creditsBalance, 0)
        XCTAssertEqual(snapshot.source, "codex-cli")
    }
}
