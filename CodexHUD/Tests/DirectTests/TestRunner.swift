import Foundation

@main
struct TestRunner {
    static func main() async throws {
        try self.testCompactTitleShowsUsedPrimaryAndWeeklyPercentages()
        try self.testFullTitleCanShowRemainingPercentages()
        try self.testMinimalTitleUsesPrimaryWindow()
        try self.testErrorAndStaleTitlesAreExplicit()
        try self.testIdleAndLoadingTitlesShowEllipsis()
        try self.testWarningPrefixEscalatesWithUsage()
        try self.testMinimalTitleUsesCriticalSymbolAtNinetyFive()
        try self.testPercentValueIsClampedToZeroAndOneHundred()
        try self.testMissingWindowsRenderQuestionMarks()
        try self.testResetDescriptionFormatsEachWindow()
        try self.testMapsCodexAppServerRateLimitsIntoUsageSnapshot()
        try self.testRPCPayloadIncludesExpectedMethod()
        if CommandLine.arguments.contains("--live") {
            let fetcher = CodexRPCConnectionFetcher()
            do {
                for _ in 0..<2 {
                    let snapshot = try await fetcher.fetchSnapshot()
                    try expect(snapshot.primary != nil && snapshot.secondary != nil, "live usage windows")
                    print(CodexUsageFormatter.title(for: .fresh(snapshot), settings: CodexHUDSettings()))
                }
                await fetcher.disconnect()
            } catch {
                await fetcher.disconnect()
                throw error
            }
        }
        print("CodexHUD direct tests passed")
    }

    private static func testCompactTitleShowsUsedPrimaryAndWeeklyPercentages() throws {
        let snapshot = self.snapshot(primary: 42, secondary: 18)
        let settings = CodexHUDSettings(displayMode: .compact, percentBasis: .used, refreshInterval: .thirtySeconds)
        try expect(
            CodexUsageFormatter.title(for: .fresh(snapshot), settings: settings, now: snapshot.updatedAt) == "Cdx 42/18",
            "compact title should show used percentages")
    }

    private static func testFullTitleCanShowRemainingPercentages() throws {
        let snapshot = self.snapshot(primary: 42, secondary: 18)
        let settings = CodexHUDSettings(displayMode: .full, percentBasis: .remaining, refreshInterval: .thirtySeconds)
        try expect(
            CodexUsageFormatter.title(for: .fresh(snapshot), settings: settings, now: snapshot.updatedAt) == "Codex 5H 58% · W 82%",
            "full title should show remaining percentages")
    }

    private static func testMinimalTitleUsesPrimaryWindow() throws {
        let snapshot = self.snapshot(primary: 37, secondary: 36)
        let settings = CodexHUDSettings(displayMode: .minimal, percentBasis: .used, refreshInterval: .thirtySeconds)
        try expect(
            CodexUsageFormatter.title(for: .fresh(snapshot), settings: settings, now: snapshot.updatedAt) == "⚡37",
            "minimal title should use primary window")
    }

    private static func testErrorAndStaleTitlesAreExplicit() throws {
        let settings = CodexHUDSettings(displayMode: .compact, percentBasis: .used, refreshInterval: .thirtySeconds)
        try expect(CodexUsageFormatter.title(for: .failed("boom"), settings: settings) == "Cdx ?", "error title")
        try expect(CodexUsageFormatter.title(for: .stale, settings: settings) == "Cdx stale", "stale title")
    }

    private static func testIdleAndLoadingTitlesShowEllipsis() throws {
        let settings = CodexHUDSettings(displayMode: .compact, percentBasis: .used, refreshInterval: .thirtySeconds)
        try expect(CodexUsageFormatter.title(for: .idle, settings: settings) == "Cdx ...", "idle title")
        try expect(CodexUsageFormatter.title(for: .loading, settings: settings) == "Cdx ...", "loading title")
    }

    private static func testWarningPrefixEscalatesWithUsage() throws {
        let settings = CodexHUDSettings(displayMode: .full, percentBasis: .used, refreshInterval: .thirtySeconds)
        try expect(
            CodexUsageFormatter.title(for: .fresh(self.snapshot(primary: 96, secondary: 10)), settings: settings) == "Codex ⚠ 5H 96% · W 10%",
            "critical warning prefix")
        try expect(
            CodexUsageFormatter.title(for: .fresh(self.snapshot(primary: 88, secondary: 10)), settings: settings) == "Codex ! 5H 88% · W 10%",
            "elevated warning prefix")
        try expect(
            CodexUsageFormatter.title(for: .fresh(self.snapshot(primary: 50, secondary: 10)), settings: settings) == "Codex 5H 50% · W 10%",
            "no warning prefix when calm")
    }

    private static func testMinimalTitleUsesCriticalSymbolAtNinetyFive() throws {
        let settings = CodexHUDSettings(displayMode: .minimal, percentBasis: .used, refreshInterval: .thirtySeconds)
        try expect(
            CodexUsageFormatter.title(for: .fresh(self.snapshot(primary: 96, secondary: 10)), settings: settings) == "⚠96",
            "minimal critical symbol")
        try expect(
            CodexUsageFormatter.title(for: .fresh(self.snapshot(primary: 60, secondary: 10)), settings: settings) == "⚡60",
            "minimal normal symbol")
    }

    private static func testPercentValueIsClampedToZeroAndOneHundred() throws {
        let overflow = self.snapshot(primary: 120, secondary: 0)
        let usedSettings = CodexHUDSettings(displayMode: .minimal, percentBasis: .used, refreshInterval: .thirtySeconds)
        let remainingSettings = CodexHUDSettings(displayMode: .compact, percentBasis: .remaining, refreshInterval: .thirtySeconds)
        try expect(CodexUsageFormatter.title(for: .fresh(overflow), settings: usedSettings) == "⚠100", "used clamps to 100")
        try expect(CodexUsageFormatter.title(for: .fresh(overflow), settings: remainingSettings) == "Cdx ⚠ 0/100", "remaining clamps to 0")
    }

    private static func testMissingWindowsRenderQuestionMarks() throws {
        let snapshot = CodexUsageSnapshot(
            primary: nil,
            secondary: CodexUsageWindow(usedPercent: 18, windowMinutes: 10_080, resetsAt: nil),
            updatedAt: Date(timeIntervalSince1970: 1_782_000_000),
            accountEmail: nil,
            planType: nil,
            creditsBalance: nil,
            source: "codex-cli")
        let settings = CodexHUDSettings(displayMode: .full, percentBasis: .used, refreshInterval: .thirtySeconds)
        try expect(
            CodexUsageFormatter.title(for: .fresh(snapshot), settings: settings) == "Codex 5H ?% · W 18%",
            "missing primary renders ?")
    }

    private static func testResetDescriptionFormatsEachWindow() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        try expect(CodexUsageFormatter.resetDescription(from: now.addingTimeInterval(-60), now: now) == "reset now", "reset now")
        try expect(CodexUsageFormatter.resetDescription(from: now.addingTimeInterval(5 * 60), now: now) == "reset in 5m", "reset minutes")
        try expect(CodexUsageFormatter.resetDescription(from: now.addingTimeInterval(90 * 60), now: now) == "reset in 1h30m", "reset hours and minutes")
        try expect(CodexUsageFormatter.resetDescription(from: now.addingTimeInterval(2 * 3600), now: now) == "reset in 2h", "reset whole hours")
        try expect(CodexUsageFormatter.resetDescription(from: now.addingTimeInterval(26 * 3600), now: now) == "reset in 1d2h", "reset days and hours")
        try expect(CodexUsageFormatter.resetDescription(from: now.addingTimeInterval(3 * 86_400), now: now) == "reset in 3d", "reset whole days")
        try expect(CodexUsageFormatter.resetDescription(from: now.addingTimeInterval(8 * 86_400), now: now).hasPrefix("reset on "), "reset weekday")
    }

    private static func testMapsCodexAppServerRateLimitsIntoUsageSnapshot() throws {
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

        try expect(snapshot.primary?.usedPercent == 37, "primary used percent")
        try expect(snapshot.primary?.windowMinutes == 300, "primary window minutes")
        try expect(snapshot.primary?.resetsAt == Date(timeIntervalSince1970: 1_782_155_126), "primary reset")
        try expect(snapshot.secondary?.usedPercent == 36, "secondary used percent")
        try expect(snapshot.secondary?.windowMinutes == 10_080, "weekly window minutes")
        try expect(snapshot.accountEmail == "office@example.com", "account email")
        try expect(snapshot.planType == "plus", "plan type")
        try expect(snapshot.creditsBalance == 0, "credits balance")
        try expect(snapshot.source == "codex-cli", "source")
    }

    private static func testRPCPayloadIncludesExpectedMethod() throws {
        let data = try CodexRPCPayload.request(id: 7, method: "account/rateLimits/read")
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        try expect(object?["id"] as? Int == 7, "rpc id")
        try expect(object?["method"] as? String == "account/rateLimits/read", "rpc method")
    }

    private static func snapshot(primary: Double, secondary: Double) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            primary: CodexUsageWindow(usedPercent: primary, windowMinutes: 300, resetsAt: nil),
            secondary: CodexUsageWindow(usedPercent: secondary, windowMinutes: 10_080, resetsAt: nil),
            updatedAt: Date(timeIntervalSince1970: 1_782_000_000),
            accountEmail: nil,
            planType: nil,
            creditsBalance: nil,
            source: "codex-cli")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw TestFailure(message)
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
