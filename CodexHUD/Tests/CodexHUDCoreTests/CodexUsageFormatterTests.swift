import XCTest
@testable import CodexHUDCore

final class CodexUsageFormatterTests: XCTestCase {
    func testCompactTitleShowsUsedPrimaryAndWeeklyPercentages() {
        let snapshot = CodexUsageSnapshot(
            primary: CodexUsageWindow(usedPercent: 42, windowMinutes: 300, resetsAt: nil),
            secondary: CodexUsageWindow(usedPercent: 18, windowMinutes: 10_080, resetsAt: nil),
            updatedAt: Date(timeIntervalSince1970: 1_782_000_000),
            accountEmail: nil,
            planType: "plus",
            creditsBalance: nil,
            source: "codex-cli")
        let settings = CodexHUDSettings(displayMode: .compact, percentBasis: .used, refreshInterval: .thirtySeconds)

        XCTAssertEqual(CodexUsageFormatter.title(for: .fresh(snapshot), settings: settings, now: snapshot.updatedAt), "Cdx 42/18")
    }

    func testFullTitleCanShowRemainingPercentages() {
        let snapshot = CodexUsageSnapshot(
            primary: CodexUsageWindow(usedPercent: 42, windowMinutes: 300, resetsAt: nil),
            secondary: CodexUsageWindow(usedPercent: 18, windowMinutes: 10_080, resetsAt: nil),
            updatedAt: Date(timeIntervalSince1970: 1_782_000_000),
            accountEmail: nil,
            planType: nil,
            creditsBalance: nil,
            source: "codex-cli")
        let settings = CodexHUDSettings(displayMode: .full, percentBasis: .remaining, refreshInterval: .thirtySeconds)

        XCTAssertEqual(CodexUsageFormatter.title(for: .fresh(snapshot), settings: settings, now: snapshot.updatedAt), "Codex 5H 58% · W 82%")
    }

    func testMinimalTitleUsesPrimaryWindow() {
        let snapshot = CodexUsageSnapshot(
            primary: CodexUsageWindow(usedPercent: 37, windowMinutes: 300, resetsAt: nil),
            secondary: CodexUsageWindow(usedPercent: 36, windowMinutes: 10_080, resetsAt: nil),
            updatedAt: Date(timeIntervalSince1970: 1_782_000_000),
            accountEmail: nil,
            planType: nil,
            creditsBalance: nil,
            source: "codex-cli")
        let settings = CodexHUDSettings(displayMode: .minimal, percentBasis: .used, refreshInterval: .thirtySeconds)

        XCTAssertEqual(CodexUsageFormatter.title(for: .fresh(snapshot), settings: settings, now: snapshot.updatedAt), "⚡37")
    }

    func testErrorAndStaleTitlesAreExplicit() {
        let settings = CodexHUDSettings(displayMode: .compact, percentBasis: .used, refreshInterval: .thirtySeconds)

        XCTAssertEqual(CodexUsageFormatter.title(for: .failed("boom"), settings: settings, now: Date()), "Cdx ?")
        XCTAssertEqual(CodexUsageFormatter.title(for: .stale, settings: settings, now: Date()), "Cdx stale")
    }

    func testIdleAndLoadingTitlesShowEllipsis() {
        let settings = CodexHUDSettings(displayMode: .compact, percentBasis: .used, refreshInterval: .thirtySeconds)

        XCTAssertEqual(CodexUsageFormatter.title(for: .idle, settings: settings, now: Date()), "Cdx ...")
        XCTAssertEqual(CodexUsageFormatter.title(for: .loading, settings: settings, now: Date()), "Cdx ...")
    }

    func testWarningPrefixEscalatesWithUsage() {
        let high = Self.snapshot(primaryUsed: 96, secondaryUsed: 10)
        let elevated = Self.snapshot(primaryUsed: 88, secondaryUsed: 10)
        let calm = Self.snapshot(primaryUsed: 50, secondaryUsed: 10)
        let settings = CodexHUDSettings(displayMode: .full, percentBasis: .used, refreshInterval: .thirtySeconds)

        XCTAssertEqual(CodexUsageFormatter.title(for: .fresh(high), settings: settings), "Codex ⚠ 5H 96% · W 10%")
        XCTAssertEqual(CodexUsageFormatter.title(for: .fresh(elevated), settings: settings), "Codex ! 5H 88% · W 10%")
        XCTAssertEqual(CodexUsageFormatter.title(for: .fresh(calm), settings: settings), "Codex 5H 50% · W 10%")
    }

    func testMinimalTitleUsesCriticalSymbolAtNinetyFive() {
        let critical = Self.snapshot(primaryUsed: 96, secondaryUsed: 10)
        let normal = Self.snapshot(primaryUsed: 60, secondaryUsed: 10)
        let settings = CodexHUDSettings(displayMode: .minimal, percentBasis: .used, refreshInterval: .thirtySeconds)

        XCTAssertEqual(CodexUsageFormatter.title(for: .fresh(critical), settings: settings), "⚠96")
        XCTAssertEqual(CodexUsageFormatter.title(for: .fresh(normal), settings: settings), "⚡60")
    }

    func testPercentValueIsClampedToZeroAndOneHundred() {
        let overflow = Self.snapshot(primaryUsed: 120, secondaryUsed: 0)
        let usedSettings = CodexHUDSettings(displayMode: .minimal, percentBasis: .used, refreshInterval: .thirtySeconds)
        let remainingSettings = CodexHUDSettings(displayMode: .compact, percentBasis: .remaining, refreshInterval: .thirtySeconds)

        XCTAssertEqual(CodexUsageFormatter.title(for: .fresh(overflow), settings: usedSettings), "⚠100")
        XCTAssertEqual(CodexUsageFormatter.title(for: .fresh(overflow), settings: remainingSettings), "Cdx ⚠ 0/100")
    }

    func testMissingWindowsRenderQuestionMarks() {
        let snapshot = CodexUsageSnapshot(
            primary: nil,
            secondary: CodexUsageWindow(usedPercent: 18, windowMinutes: 10_080, resetsAt: nil),
            updatedAt: Date(timeIntervalSince1970: 1_782_000_000),
            accountEmail: nil,
            planType: nil,
            creditsBalance: nil,
            source: "codex-cli")
        let settings = CodexHUDSettings(displayMode: .full, percentBasis: .used, refreshInterval: .thirtySeconds)

        XCTAssertEqual(CodexUsageFormatter.title(for: .fresh(snapshot), settings: settings), "Codex 5H ?% · W 18%")
    }

    func testResetDescriptionFormatsEachWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(CodexUsageFormatter.resetDescription(from: now.addingTimeInterval(-60), now: now), "reset now")
        XCTAssertEqual(CodexUsageFormatter.resetDescription(from: now.addingTimeInterval(5 * 60), now: now), "reset in 5m")
        XCTAssertEqual(CodexUsageFormatter.resetDescription(from: now.addingTimeInterval(90 * 60), now: now), "reset in 1h30m")
        XCTAssertEqual(CodexUsageFormatter.resetDescription(from: now.addingTimeInterval(2 * 3600), now: now), "reset in 2h")
        XCTAssertEqual(CodexUsageFormatter.resetDescription(from: now.addingTimeInterval(26 * 3600), now: now), "reset in 1d2h")
        XCTAssertEqual(CodexUsageFormatter.resetDescription(from: now.addingTimeInterval(3 * 86_400), now: now), "reset in 3d")
        XCTAssertTrue(CodexUsageFormatter.resetDescription(from: now.addingTimeInterval(8 * 86_400), now: now).hasPrefix("reset on "))
    }

    private static func snapshot(primaryUsed: Double, secondaryUsed: Double) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            primary: CodexUsageWindow(usedPercent: primaryUsed, windowMinutes: 300, resetsAt: nil),
            secondary: CodexUsageWindow(usedPercent: secondaryUsed, windowMinutes: 10_080, resetsAt: nil),
            updatedAt: Date(timeIntervalSince1970: 1_782_000_000),
            accountEmail: nil,
            planType: nil,
            creditsBalance: nil,
            source: "codex-cli")
    }
}
