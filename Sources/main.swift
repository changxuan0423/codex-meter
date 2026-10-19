import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class MeterModel: ObservableObject {
    @Published var snapshot: QuotaSnapshot?
    @Published var updatedAt: Date?
    @Published var error: String?
    @Published var refreshing = false
    @Published var now = Date()
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var showResetTime = UserDefaults.standard.object(forKey: "showResetTime") as? Bool ?? true
    var changed: (() -> Void)?
    var attemptedAt: Date?
    var isStale: Bool { error != nil || updatedAt.map { now.timeIntervalSince($0) > 300 } ?? false }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        attemptedAt = Date()
        changed?()
        Task {
            let result = await Task.detached(priority: .utility) { () -> Result<QuotaSnapshot, Error> in
                Result { try CodexClient.fetch() }
            }.value
            switch result {
            case .success(let snapshot):
                self.snapshot = snapshot
                updatedAt = Date()
                error = nil
            case .failure(let failure): error = failure.localizedDescription
            }
            now = Date()
            refreshing = false
            changed?()
        }
    }

    func tick() {
        now = Date()
        let sinceAttempt = attemptedAt.map { now.timeIntervalSince($0) } ?? .infinity
        let expired = snapshot?.fiveHour?.isExpired(at: now) ?? false
        // A passed reset is not proof of replenishment; fetch again before showing a percentage.
        if sinceAttempt >= 120 || (expired && sinceAttempt >= 30) { refresh() }
        changed?()
    }

    func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { self.error = "开机启动设置失败，请将应用移至「应用程序」后重试。" }
        changed?()
    }
}

struct MeterPanel: View {
    @ObservedObject var model: MeterModel
    let close: () -> Void
    private let accent = Color(red: 0.87, green: 0.74, blue: 0.17)
    private var window: QuotaWindow? { model.snapshot?.fiveHour }
    private var remaining: Int? {
        guard let window, !window.isExpired(at: model.now) else { return nil }
        return window.remaining
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(nsImage: MeterIcon.make(size: 30)).resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex Meter").font(.system(size: 15, weight: .semibold))
                    Text("账户额度 · 每 2 分钟更新").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.refreshing { ProgressView().controlSize(.small).scaleEffect(0.75).frame(width: 18) }
                else { Circle().fill(model.isStale ? Color.orange : (model.updatedAt == nil ? Color.gray : Color.green)).frame(width: 6, height: 6) }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(remaining.map(String.init) ?? "—").font(.system(size: 48, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("%").font(.system(size: 22)).foregroundStyle(.secondary)
                    Spacer()
                    Text("5 小时剩余").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill((remaining ?? 100) <= 10 ? Color.orange : accent)
                            .frame(width: geometry.size.width * CGFloat(remaining ?? 0) / 100)
                    }
                }.frame(height: 6)
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .medium))
                    Text(window == nil ? "账户暂未提供 5 小时额度" : MeterFormat.resetDescription(window?.resetDate, now: model.now))
                    Spacer()
                    if let date = window?.resetDate, date > model.now {
                        Text(countdown(date)).monospacedDigit()
                    }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let weekly = model.snapshot?.weekly {
                HStack {
                    Text("每周剩余")
                    Spacer()
                    Text(weekly.isExpired(at: model.now) ? "等待更新" : "\(weekly.remaining)%").monospacedDigit()
                }.font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 11))
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                if model.snapshot != nil { Text("当前保留上次结果，暂非最新额度。").font(.system(size: 11)).foregroundStyle(.secondary) }
            } else if model.updatedAt == nil {
                Text("正在连接本机 Codex…").font(.system(size: 11)).foregroundStyle(.secondary)
            } else if model.isStale {
                Text("数据超过 5 分钟未更新，请刷新。").font(.system(size: 11)).foregroundStyle(.orange)
            }
            Divider()
            VStack(spacing: 12) {
                Toggle(isOn: $model.showResetTime) {
                    Text("菜单栏显示重置时间").frame(maxWidth: .infinity, alignment: .leading)
                }
                    .onChange(of: model.showResetTime) { value in
                        UserDefaults.standard.set(value, forKey: "showResetTime")
                        model.changed?()
                    }
                Toggle(isOn: Binding(get: { model.launchAtLogin }, set: { _ in model.toggleLogin() })) {
                    Text("开机启动").frame(maxWidth: .infinity, alignment: .leading)
                }
            }.toggleStyle(.switch).controlSize(.mini).font(.system(size: 12))
            HStack(spacing: 8) {
                Button { model.refresh() } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(model.refreshing)
                Button("打开 Codex") { openCodex(); close() }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }.controlSize(.small)
            HStack {
                Text(model.updatedAt.map { "更新于 " + MeterFormat.resetTime($0) } ?? "尚未读取到额度")
                Spacer()
                Text("本地时间").help(TimeZone.current.identifier)
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(22)
        .frame(width: 330)
    }
    private func countdown(_ date: Date) -> String {
        let minutes = max(1, Int(ceil(date.timeIntervalSince(model.now) / 60)))
        if minutes >= 60 { return "\(minutes / 60)时\(minutes % 60)分后" }
        return "\(minutes)分后"
    }
    private func openCodex() {
        let paths = ["/Applications/Codex.app", "/Applications/ChatGPT.app"]
        if let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
        }
    }
}

@MainActor
final class MeterWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let panel = MeterWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let model = MeterModel()
    private var timer: Timer?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let siblings = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.xavier.CodexMeter")
        if siblings.count > 1 { NSApp.terminate(nil); return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusAppearance.icon()
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.imageScaling = .scaleNone
        statusItem.button?.font = StatusAppearance.font
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.panel.isVisible else { return false }
                if event.type == .keyDown {
                    if event.keyCode == 53 { self.panel.orderOut(nil); return true }
                } else if event.window !== self.panel && event.window !== self.statusItem.button?.window {
                    self.panel.orderOut(nil)
                }
                return false
            }
            return consumed ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.orderOut(nil) }
        }
        model.changed = { [weak self] in self?.renderStatus() }
        renderStatus()
        timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(closePanel), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        model.refresh()
    }

    private func renderStatus() {
        let quota = model.snapshot?.fiveHour
        let valid = quota.map { !$0.isExpired(at: model.now) } ?? false
        let percentage = valid ? "\(quota!.remaining)%" : "--%"
        statusItem.button?.attributedTitle = StatusAppearance.title(
            percentage: percentage,
            resetTime: model.showResetTime ? MeterFormat.resetTime(valid ? quota?.resetDate : nil) : nil,
            stale: model.isStale
        )
        statusItem.button?.setAccessibilityLabel("Codex 5 小时剩余 " + percentage)
        var tooltip = "Codex · 5 小时剩余 " + percentage
        if valid { tooltip += "\n" + MeterFormat.resetDescription(quota?.resetDate, now: model.now) }
        if let error = model.error { tooltip += "\n" + error }
        if let date = model.updatedAt { tooltip += "\n更新于 " + MeterFormat.resetTime(date) }
        statusItem.button?.toolTip = tooltip
        if panel.isVisible { positionPanel() }
    }

    @objc private func woke() { model.refresh() }
    @objc private func closePanel() { panel.orderOut(nil) }

    private func positionPanel() {
        guard let button = statusItem.button, let window = button.window,
              let screen = window.screen else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let content = MeterPanel(model: model, close: { [weak self] in self?.panel.orderOut(nil) })
        let measured = NSHostingView(rootView: content.fixedSize(horizontal: false, vertical: true)).fittingSize
        let frame = PanelPlacement.frame(anchor: anchor, visible: screen.visibleFrame,
                                         content: NSSize(width: 330, height: ceil(measured.height)))
        // Explicit height and a scroll container keep all content reachable on short displays.
        if panel.contentView == nil || panel.frame.size != frame.size {
            panel.contentView = NSHostingView(rootView:
                ScrollView(.vertical) { content.fixedSize(horizontal: false, vertical: true) }
                    .frame(width: frame.width, height: frame.height, alignment: .top)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            )
        }
        panel.setFrame(frame, display: true)
    }

    @objc private func togglePopover() {
        if panel.isVisible { panel.orderOut(nil); return }
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        model.tick()
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
    }
}

// A child process can exit between poll and write; surface a recoverable error.
signal(SIGPIPE, SIG_IGN)
if CommandLine.arguments.contains("--diagnose") {
    do {
        let snapshot = try CodexClient.fetch()
        let quota = snapshot.fiveHour
        let report: [String: Any] = [
            "fiveHourRemainingPercent": quota.map { $0.remaining as Any } ?? NSNull(),
            "resetsAt": quota?.resetsAt.map { $0 as Any } ?? NSNull(),
            "weeklyRemainingPercent": snapshot.weekly.map { $0.remaining as Any } ?? NSNull(),
            "cliFound": CodexClient.executable() != nil
        ]
        print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else {
    MainActor.assumeIsolated {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
