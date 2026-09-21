import Foundation

public enum MenuBarDisplayMode: String, CaseIterable, Codable, Equatable {
    case full
    case compact
    case minimal

    public var title: String {
        switch self {
        case .full: "完整"
        case .compact: "紧凑"
        case .minimal: "极简"
        }
    }
}

public enum PercentBasis: String, CaseIterable, Codable, Equatable {
    case used
    case remaining

    public var title: String {
        switch self {
        case .used: "已用"
        case .remaining: "剩余"
        }
    }
}

public enum FloatingUsageDisplay: String, CaseIterable, Codable, Equatable {
    case fiveHour
    case weekly
    case both

    public var title: String {
        switch self {
        case .fiveHour: "5 小时"
        case .weekly: "每周"
        case .both: "全部"
        }
    }
}

public enum FloatingWindowSize: String, CaseIterable, Codable, Equatable {
    case small
    case medium
    case large

    public var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }
}

public enum FloatingTone: String, CaseIterable, Codable, Equatable {
    case light
    case medium
    case dark

    public var title: String {
        switch self {
        case .light: "低"
        case .medium: "中"
        case .dark: "高"
        }
    }
}

public enum RefreshInterval: Int, CaseIterable, Codable, Equatable {
    case tenSeconds = 10
    case thirtySeconds = 30
    case sixtySeconds = 60
    case fiveMinutes = 300

    public var title: String {
        switch self {
        case .tenSeconds: "10 秒"
        case .thirtySeconds: "30 秒"
        case .sixtySeconds: "60 秒"
        case .fiveMinutes: "5 分钟"
        }
    }
}

public struct CodexHUDSettings: Codable, Equatable {
    public var displayMode: MenuBarDisplayMode
    public var percentBasis: PercentBasis
    public var refreshInterval: RefreshInterval
    public var floatingDisplay: FloatingUsageDisplay
    public var floatingSize: FloatingWindowSize
    public var backgroundTone: FloatingTone
    public var textTone: FloatingTone

    public init(
        displayMode: MenuBarDisplayMode = .compact,
        percentBasis: PercentBasis = .remaining,
        refreshInterval: RefreshInterval = .thirtySeconds,
        floatingDisplay: FloatingUsageDisplay = .fiveHour,
        floatingSize: FloatingWindowSize = .medium,
        backgroundTone: FloatingTone = .medium,
        textTone: FloatingTone = .light)
    {
        self.displayMode = displayMode
        self.percentBasis = percentBasis
        self.refreshInterval = refreshInterval
        self.floatingDisplay = floatingDisplay
        self.floatingSize = floatingSize
        self.backgroundTone = backgroundTone
        self.textTone = textTone
    }
}

public struct CodexUsageWindow: Equatable, Sendable {
    public let usedPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?

    public init(usedPercent: Double, windowMinutes: Int?, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }
}

public struct CodexUsageSnapshot: Equatable, Sendable {
    public let primary: CodexUsageWindow?
    public let secondary: CodexUsageWindow?
    public let updatedAt: Date
    public let accountEmail: String?
    public let planType: String?
    public let creditsBalance: Double?
    public let source: String

    public init(
        primary: CodexUsageWindow?,
        secondary: CodexUsageWindow?,
        updatedAt: Date,
        accountEmail: String?,
        planType: String?,
        creditsBalance: Double?,
        source: String)
    {
        self.primary = primary
        self.secondary = secondary
        self.updatedAt = updatedAt
        self.accountEmail = accountEmail
        self.planType = planType
        self.creditsBalance = creditsBalance
        self.source = source
    }
}

public enum CodexUsageState: Equatable {
    case idle
    case loading
    case fresh(CodexUsageSnapshot)
    case stale
    case failed(String)
}

public struct CodexRateLimitsRPCResult: Decodable, Equatable {
    public let rateLimits: CodexRPCRateLimitSnapshot
}

public struct CodexRPCRateLimitSnapshot: Decodable, Equatable {
    public let primary: CodexRPCRateLimitWindow?
    public let secondary: CodexRPCRateLimitWindow?
    public let credits: CodexRPCCreditsSnapshot?
    public let planType: String?
}

public struct CodexRPCRateLimitWindow: Decodable, Equatable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: Int?
}

public struct CodexRPCCreditsSnapshot: Decodable, Equatable {
    public let hasCredits: Bool?
    public let unlimited: Bool?
    public let balance: String?

    public var balanceValue: Double? {
        guard let balance else { return nil }
        return Double(balance)
    }
}

public struct CodexAccountRPCResult: Decodable, Equatable {
    public let account: CodexRPCAccount?
    public let requiresOpenaiAuth: Bool?
}

public struct CodexRPCAccount: Decodable, Equatable {
    public let type: String?
    public let email: String?
    public let planType: String?
}

public enum CodexRPCMapper {
    public static func snapshot(
        rateLimits: CodexRateLimitsRPCResult,
        account: CodexAccountRPCResult?,
        updatedAt: Date = Date()) -> CodexUsageSnapshot
    {
        CodexUsageSnapshot(
            primary: self.window(from: rateLimits.rateLimits.primary),
            secondary: self.window(from: rateLimits.rateLimits.secondary),
            updatedAt: updatedAt,
            accountEmail: self.normalized(account?.account?.email),
            planType: self.normalized(account?.account?.planType) ?? self.normalized(rateLimits.rateLimits.planType),
            creditsBalance: rateLimits.rateLimits.credits?.balanceValue,
            source: "codex-cli")
    }

    private static func window(from rpc: CodexRPCRateLimitWindow?) -> CodexUsageWindow? {
        guard let rpc else { return nil }
        return CodexUsageWindow(
            usedPercent: rpc.usedPercent,
            windowMinutes: rpc.windowDurationMins,
            resetsAt: rpc.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
