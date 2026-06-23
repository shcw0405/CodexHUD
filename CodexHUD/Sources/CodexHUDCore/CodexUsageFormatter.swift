import Foundation

public enum CodexUsageFormatter {
    /// `DateFormatter` is expensive to allocate and these are only ever touched
    /// from the main actor during menu/title rendering, so cache them. POSIX
    /// locale keeps `HH:mm:ss` / `EEE` stable regardless of the user's locale.
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    public static func title(
        for state: CodexUsageState,
        settings: CodexHUDSettings,
        now: Date = Date()) -> String
    {
        switch state {
        case .idle, .loading:
            return "Cdx ..."
        case .stale:
            return "Cdx stale"
        case .failed:
            return "Cdx ?"
        case let .fresh(snapshot):
            return self.title(for: snapshot, settings: settings)
        }
    }

    public static func detailLine(
        label: String,
        window: CodexUsageWindow?,
        basis: PercentBasis,
        now: Date = Date()) -> String
    {
        guard let window else {
            return "\(label)     ? \(self.basisLabel(for: basis))"
        }
        let percent = self.percentText(for: window, basis: basis)
        let reset = window.resetsAt.map { self.resetDescription(from: $0, now: now) } ?? "reset unknown"
        return "\(label)     \(percent) \(self.basisLabel(for: basis))   \(reset)"
    }

    public static func updatedTime(_ date: Date) -> String {
        self.clockFormatter.string(from: date)
    }

    public static func resetDescription(from resetsAt: Date, now: Date = Date()) -> String {
        let seconds = Int(resetsAt.timeIntervalSince(now).rounded())
        if seconds <= 0 {
            return "reset now"
        }
        let minutes = max(1, seconds / 60)
        if minutes < 60 {
            return "reset in \(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 24 {
            return remainingMinutes == 0
                ? "reset in \(hours)h"
                : "reset in \(hours)h\(remainingMinutes)m"
        }
        let days = hours / 24
        let remainingHours = hours % 24
        if days < 7 {
            return remainingHours == 0
                ? "reset in \(days)d"
                : "reset in \(days)d\(remainingHours)h"
        }
        return "reset on \(self.weekdayFormatter.string(from: resetsAt))"
    }

    private static func title(for snapshot: CodexUsageSnapshot, settings: CodexHUDSettings) -> String {
        let primary = self.percentText(for: snapshot.primary, basis: settings.percentBasis, compact: true)
        let weekly = self.percentText(for: snapshot.secondary, basis: settings.percentBasis, compact: true)
        let warning = self.warningPrefix(for: snapshot)

        switch settings.displayMode {
        case .full:
            if warning.isEmpty {
                return "Codex 5H \(primary)% · W \(weekly)%"
            }
            return "Codex \(warning)5H \(primary)% · W \(weekly)%"
        case .compact:
            return "Cdx \(warning)\(primary)/\(weekly)"
        case .minimal:
            let symbol = self.isCritical(snapshot) ? "⚠" : "⚡"
            return "\(symbol)\(primary)"
        }
    }

    private static func percentText(
        for window: CodexUsageWindow?,
        basis: PercentBasis,
        compact: Bool = false) -> String
    {
        guard let window else { return "?" }
        return compact ? "\(self.percentValue(for: window, basis: basis))" : "\(self.percentValue(for: window, basis: basis))%"
    }

    private static func percentText(for window: CodexUsageWindow, basis: PercentBasis) -> String {
        "\(self.percentValue(for: window, basis: basis))%"
    }

    private static func percentValue(for window: CodexUsageWindow, basis: PercentBasis) -> Int {
        let used = min(100, max(0, window.usedPercent))
        let value: Double = switch basis {
        case .used: used
        case .remaining: 100 - used
        }
        return Int(value.rounded())
    }

    private static func basisLabel(for basis: PercentBasis) -> String {
        switch basis {
        case .used:
            return "used"
        case .remaining:
            return "remaining"
        }
    }

    private static func warningPrefix(for snapshot: CodexUsageSnapshot) -> String {
        let value = max(snapshot.primary?.usedPercent ?? 0, snapshot.secondary?.usedPercent ?? 0)
        if value >= 95 { return "⚠ " }
        if value >= 85 { return "! " }
        return ""
    }

    private static func isCritical(_ snapshot: CodexUsageSnapshot) -> Bool {
        max(snapshot.primary?.usedPercent ?? 0, snapshot.secondary?.usedPercent ?? 0) >= 95
    }
}
