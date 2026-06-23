import Foundation
import CodexHUDCore

enum CodexHUDSettingsStore {
    private static let displayModeKey = "displayMode"
    private static let percentBasisKey = "percentBasis"
    private static let refreshIntervalKey = "refreshInterval"
    private static let floatingDisplayKey = "floatingDisplay"
    private static let floatingSizeKey = "floatingSize"
    private static let backgroundToneKey = "backgroundTone"
    private static let textToneKey = "textTone"

    static func load(defaults: UserDefaults = .standard) -> CodexHUDSettings {
        let displayMode = defaults.string(forKey: self.displayModeKey)
            .flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .compact
        let percentBasis = defaults.string(forKey: self.percentBasisKey)
            .flatMap(PercentBasis.init(rawValue:)) ?? .remaining
        let refreshInterval = RefreshInterval(rawValue: defaults.integer(forKey: self.refreshIntervalKey))
            ?? .thirtySeconds
        let floatingDisplay = defaults.string(forKey: self.floatingDisplayKey)
            .flatMap(FloatingUsageDisplay.init(rawValue:)) ?? .fiveHour
        let floatingSize = defaults.string(forKey: self.floatingSizeKey)
            .flatMap(FloatingWindowSize.init(rawValue:)) ?? .medium
        let backgroundTone = defaults.string(forKey: self.backgroundToneKey)
            .flatMap(FloatingTone.init(rawValue:)) ?? .medium
        let textTone = defaults.string(forKey: self.textToneKey)
            .flatMap(FloatingTone.init(rawValue:)) ?? .light
        return CodexHUDSettings(
            displayMode: displayMode,
            percentBasis: percentBasis,
            refreshInterval: refreshInterval,
            floatingDisplay: floatingDisplay,
            floatingSize: floatingSize,
            backgroundTone: backgroundTone,
            textTone: textTone)
    }

    static func save(_ settings: CodexHUDSettings, defaults: UserDefaults = .standard) {
        defaults.set(settings.displayMode.rawValue, forKey: self.displayModeKey)
        defaults.set(settings.percentBasis.rawValue, forKey: self.percentBasisKey)
        defaults.set(settings.refreshInterval.rawValue, forKey: self.refreshIntervalKey)
        defaults.set(settings.floatingDisplay.rawValue, forKey: self.floatingDisplayKey)
        defaults.set(settings.floatingSize.rawValue, forKey: self.floatingSizeKey)
        defaults.set(settings.backgroundTone.rawValue, forKey: self.backgroundToneKey)
        defaults.set(settings.textTone.rawValue, forKey: self.textToneKey)
    }
}
