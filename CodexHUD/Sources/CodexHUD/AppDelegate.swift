import AppKit
import CodexHUDCore
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenu = NSMenu()
    private let fetcher = CodexRPCConnectionFetcher()
    private let floatingPanel = FloatingUsagePanelController()
    private var settings = CodexHUDSettingsStore.load()
    private var snapshot: CodexUsageSnapshot?
    private var lastError: String?
    private var refreshTimer: Timer?
    private var isRefreshing = false
    private var floatingDismissed = UserDefaults.standard.bool(forKey: "floatingDismissed")

    /// Tags identifying which setting a segmented control drives.
    private enum SettingTag {
        static let menuBarStyle = 1
        static let percentage = 2
        static let refreshInterval = 3
        static let floatingData = 4
        static let windowSize = 5
        static let background = 6
        static let textOpacity = 7
    }

    /// A snapshot older than this is reported as stale. Tied to the refresh
    /// interval so a couple of missed refreshes flips the indicator.
    private var staleThreshold: TimeInterval {
        max(90, TimeInterval(self.settings.refreshInterval.rawValue) * 3)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        self.statusItem.button?.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)

        // The menu is rebuilt lazily right before it opens (menuNeedsUpdate), so
        // it always shows fresh usage without us reassigning it while it's open.
        self.statusMenu.delegate = self
        self.statusMenu.autoenablesItems = false
        self.statusItem.menu = self.statusMenu
        self.floatingPanel.setMenu(self.statusMenu)

        self.floatingPanel.onUserClose = { [weak self] in
            self?.floatingDismissed = true
            UserDefaults.standard.set(true, forKey: "floatingDismissed")
            self?.refreshStatusViews()
        }
        self.refreshStatusViews()
        self.scheduleRefreshTimer()
        self.refreshNow(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await self.fetcher.disconnect() }
    }

    /// Derives the display state from the latest fetch result and its age.
    private func currentState(now: Date = Date()) -> CodexUsageState {
        if let snapshot = self.snapshot {
            if now.timeIntervalSince(snapshot.updatedAt) > self.staleThreshold {
                return .stale
            }
            return .fresh(snapshot)
        }
        if self.isRefreshing {
            return .loading
        }
        if let lastError = self.lastError {
            return .failed(lastError)
        }
        return .idle
    }

    /// Updates the always-visible surfaces (menu bar title + floating panel).
    /// Deliberately does NOT rebuild the dropdown menu, so changing a setting
    /// from an open menu refreshes these live without dismissing it.
    private func refreshStatusViews() {
        let state = self.currentState()
        self.statusItem.button?.title = CodexUsageFormatter.title(for: state, settings: self.settings)
        self.updateFloatingPanel(state: state)
    }

    @objc private func refreshNow(_ sender: Any?) {
        guard !self.isRefreshing else { return }
        self.isRefreshing = true
        self.refreshStatusViews()

        Task {
            do {
                let snapshot = try await self.fetcher.fetchSnapshot()
                await MainActor.run {
                    self.snapshot = snapshot
                    self.lastError = nil
                    self.isRefreshing = false
                    self.refreshStatusViews()
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isRefreshing = false
                    self.refreshStatusViews()
                }
            }
        }
    }

    @objc private func toggleFloatingPanel(_ sender: Any?) {
        self.floatingDismissed.toggle()
        UserDefaults.standard.set(self.floatingDismissed, forKey: "floatingDismissed")
        self.refreshStatusViews()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    /// One handler for every settings segmented control; the sender's tag says
    /// which setting and its selected segment indexes into that enum's allCases.
    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard index >= 0 else { return }
        switch sender.tag {
        case SettingTag.menuBarStyle:
            if index < MenuBarDisplayMode.allCases.count {
                self.settings.displayMode = MenuBarDisplayMode.allCases[index]
            }
        case SettingTag.percentage:
            if index < PercentBasis.allCases.count {
                self.settings.percentBasis = PercentBasis.allCases[index]
            }
        case SettingTag.refreshInterval:
            if index < RefreshInterval.allCases.count {
                self.settings.refreshInterval = RefreshInterval.allCases[index]
                self.scheduleRefreshTimer()
            }
        case SettingTag.floatingData:
            if index < FloatingUsageDisplay.allCases.count {
                self.settings.floatingDisplay = FloatingUsageDisplay.allCases[index]
            }
        case SettingTag.windowSize:
            if index < FloatingWindowSize.allCases.count {
                self.settings.floatingSize = FloatingWindowSize.allCases[index]
            }
        case SettingTag.background:
            if index < FloatingTone.allCases.count {
                self.settings.backgroundTone = FloatingTone.allCases[index]
            }
        case SettingTag.textOpacity:
            if index < FloatingTone.allCases.count {
                self.settings.textTone = FloatingTone.allCases[index]
            }
        default:
            return
        }
        CodexHUDSettingsStore.save(self.settings)
        self.refreshStatusViews()
    }

    private func scheduleRefreshTimer() {
        self.refreshTimer?.invalidate()
        self.refreshTimer = Timer(
            timeInterval: TimeInterval(self.settings.refreshInterval.rawValue),
            repeats: true)
        { [weak self] _ in
            self?.refreshNow(nil)
        }
        if let timer = self.refreshTimer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func updateFloatingPanel(state: CodexUsageState) {
        let appearance = FloatingUsageAppearance(
            size: self.settings.floatingSize,
            backgroundTone: self.settings.backgroundTone,
            textTone: self.settings.textTone)

        self.floatingPanel.update(entries: self.floatingEntries(for: state), appearance: appearance)
        if self.floatingDismissed {
            self.floatingPanel.hide()
        } else {
            self.floatingPanel.show()
        }
    }

    private func floatingEntries(for state: CodexUsageState) -> [FloatingUsageEntry] {
        switch state {
        case let .fresh(snapshot):
            return self.entries(for: snapshot, stale: false)
        case .stale:
            if let snapshot = self.snapshot {
                return self.entries(for: snapshot, stale: true)
            }
            return [FloatingUsageEntry(label: "Cdx", value: "?", suffix: "", subtitle: "数据已过期")]
        case .loading:
            return [FloatingUsageEntry(label: "5H", value: "...", suffix: "", subtitle: "刷新中")]
        case .failed:
            return [FloatingUsageEntry(label: "Cdx", value: "?", suffix: "", subtitle: "读取失败")]
        case .idle:
            return [FloatingUsageEntry(label: "5H", value: "...", suffix: "", subtitle: "等待刷新")]
        }
    }

    private func entries(for snapshot: CodexUsageSnapshot, stale: Bool) -> [FloatingUsageEntry] {
        switch self.settings.floatingDisplay {
        case .fiveHour:
            return [self.entry(label: "5H", window: snapshot.primary, stale: stale)]
        case .weekly:
            return [self.entry(label: "W", window: snapshot.secondary, stale: stale)]
        case .both:
            return [
                self.entry(label: "5H", window: snapshot.primary, stale: stale),
                self.entry(label: "W", window: snapshot.secondary, stale: stale)
            ]
        }
    }

    private func entry(label: String, window: CodexUsageWindow?, stale: Bool) -> FloatingUsageEntry {
        guard let window else {
            return FloatingUsageEntry(label: label, value: "?", suffix: "", subtitle: "暂无数据")
        }
        let remaining = CodexUsageFormatter.percentValue(for: window, basis: self.settings.percentBasis)
        let subtitle = stale
            ? "数据已过期"
            : (window.resetsAt.map { CodexUsageFormatter.resetDescription(from: $0) } ?? "重置时间未知")
        return FloatingUsageEntry(label: "\(label) \(self.settings.percentBasis.title)", value: String(remaining), suffix: "%", subtitle: subtitle)
    }

    private func populateMenu(_ menu: NSMenu, state: CodexUsageState) {
        menu.removeAllItems()

        // Settings first as inline segmented controls. Picking an option keeps the
        // menu open (custom-view items don't dismiss it), so the change lands live.
        menu.addItem(self.segmentRow(
            title: "菜单栏样式",
            labels: MenuBarDisplayMode.allCases.map(\.title),
            selectedIndex: MenuBarDisplayMode.allCases.firstIndex(of: self.settings.displayMode) ?? 0,
            tag: SettingTag.menuBarStyle))
        menu.addItem(self.segmentRow(
            title: "用量显示",
            labels: PercentBasis.allCases.map(\.title),
            selectedIndex: PercentBasis.allCases.firstIndex(of: self.settings.percentBasis) ?? 0,
            tag: SettingTag.percentage))
        menu.addItem(self.segmentRow(
            title: "刷新间隔",
            labels: RefreshInterval.allCases.map(\.title),
            selectedIndex: RefreshInterval.allCases.firstIndex(of: self.settings.refreshInterval) ?? 0,
            tag: SettingTag.refreshInterval))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(self.segmentRow(
            title: "悬浮窗内容",
            labels: FloatingUsageDisplay.allCases.map(\.title),
            selectedIndex: FloatingUsageDisplay.allCases.firstIndex(of: self.settings.floatingDisplay) ?? 0,
            tag: SettingTag.floatingData))
        menu.addItem(self.segmentRow(
            title: "悬浮窗大小",
            labels: FloatingWindowSize.allCases.map(\.title),
            selectedIndex: FloatingWindowSize.allCases.firstIndex(of: self.settings.floatingSize) ?? 0,
            tag: SettingTag.windowSize))
        menu.addItem(self.segmentRow(
            title: "背景深浅",
            labels: FloatingTone.allCases.map(\.title),
            selectedIndex: FloatingTone.allCases.firstIndex(of: self.settings.backgroundTone) ?? 0,
            tag: SettingTag.background))
        menu.addItem(self.segmentRow(
            title: "文字亮度",
            labels: FloatingTone.allCases.map(\.title),
            selectedIndex: FloatingTone.allCases.firstIndex(of: self.settings.textTone) ?? 0,
            tag: SettingTag.textOpacity))

        menu.addItem(NSMenuItem.separator())
        let refresh = NSMenuItem(title: self.isRefreshing ? "正在刷新…" : "立即刷新", action: #selector(self.refreshNow(_:)), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = !self.isRefreshing
        menu.addItem(refresh)

        let toggle = NSMenuItem(
            title: self.floatingDismissed ? "显示悬浮窗" : "隐藏悬浮窗",
            action: #selector(self.toggleFloatingPanel(_:)),
            keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        // Usage detail last — read-only, glanced at, never clicked.
        menu.addItem(NSMenuItem.separator())
        self.addStatusRows(to: menu, state: state)

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "退出 CodexHUD", action: #selector(self.quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func addStatusRows(to menu: NSMenu, state: CodexUsageState) {
        switch state {
        case let .fresh(snapshot):
            self.addSnapshotRows(to: menu, snapshot: snapshot)
        case .stale:
            menu.addItem(self.disabledItem("⚠ 数据已过期"))
            if let lastError { menu.addItem(self.disabledItem("刷新失败：\(lastError)")) }
            if let snapshot = self.snapshot {
                self.addSnapshotRows(to: menu, snapshot: snapshot)
            }
        case let .failed(message):
            menu.addItem(self.disabledItem("无法读取用量"))
            menu.addItem(self.disabledItem(message))
        case .loading, .idle:
            menu.addItem(self.disabledItem("等待首次刷新"))
        }
    }

    private func addSnapshotRows(to menu: NSMenu, snapshot: CodexUsageSnapshot) {
        menu.addItem(self.disabledItem(CodexUsageFormatter.detailLine(
            label: "5 小时",
            window: snapshot.primary,
            basis: self.settings.percentBasis)))
        menu.addItem(self.disabledItem(CodexUsageFormatter.detailLine(
            label: "每周",
            window: snapshot.secondary,
            basis: self.settings.percentBasis)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(self.disabledItem("更新时间    \(CodexUsageFormatter.updatedTime(snapshot.updatedAt))"))
        if let email = snapshot.accountEmail {
            menu.addItem(self.disabledItem("账号    \(email)"))
        }
        if let plan = snapshot.planType {
            menu.addItem(self.disabledItem("套餐    \(plan)"))
        }
    }

    /// A settings row: a left-aligned label plus an inline segmented control.
    /// Because it lives in the menu item's `view`, clicking a segment does not
    /// dismiss the menu.
    private func segmentRow(title: String, labels: [String], selectedIndex: Int, tag: Int) -> NSMenuItem {
        let leftPad: CGFloat = 14
        let labelWidth: CGFloat = 88
        let gap: CGFloat = 10
        let rightPad: CGFloat = 14
        let rowHeight: CGFloat = 30

        let segmented = NSSegmentedControl(
            labels: labels,
            trackingMode: .selectOne,
            target: self,
            action: #selector(self.segmentChanged(_:)))
        segmented.controlSize = .small
        segmented.segmentDistribution = .fillEqually
        segmented.tag = tag
        segmented.sizeToFit()
        if selectedIndex >= 0, selectedIndex < labels.count {
            segmented.selectedSegment = selectedIndex
        }
        let segSize = NSSize(width: 204, height: segmented.frame.height)

        let totalWidth = leftPad + labelWidth + gap + segSize.width + rightPad
        let container = NSView(frame: NSRect(x: 0, y: 0, width: totalWidth, height: rowHeight))

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.menuFont(ofSize: 0)
        label.textColor = .labelColor
        label.frame = NSRect(x: leftPad, y: (rowHeight - 17) / 2, width: labelWidth, height: 17)
        container.addSubview(label)

        segmented.frame = NSRect(
            x: leftPad + labelWidth + gap,
            y: (rowHeight - segSize.height) / 2,
            width: segSize.width,
            height: segSize.height)
        container.addSubview(segmented)

        let item = NSMenuItem()
        item.view = container
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        self.populateMenu(menu, state: self.currentState())
    }
}
