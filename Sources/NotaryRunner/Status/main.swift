import AppKit
import Foundation
import NotaryCore

@main
@MainActor
enum NotaryStatusMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = NotaryStatusAppDelegate()

        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.finishLaunching()
        app.run()
    }
}

private extension NotaryPublicComplianceState {
    var userSentence: String {
        switch self {
        case .compliant:
            return "Your Mac is compliant."
        case .attention:
            return "Your Mac needs attention."
        case .nonCompliant:
            return "Your Mac is non-compliant."
        case .unavailable:
            return "Waiting for the first Notary report."
        }
    }

    var statusColor: NSColor {
        switch self {
        case .compliant:
            return .systemGreen
        case .attention:
            return .systemOrange
        case .nonCompliant:
            return .systemRed
        case .unavailable:
            return .systemGray
        }
    }

    var statusMark: StatusMark {
        switch self {
        case .compliant:
            return .check
        case .attention:
            return .warning
        case .nonCompliant:
            return .xmark
        case .unavailable:
            return .question
        }
    }

    var statusSymbolName: String {
        switch self {
        case .compliant:
            return "checkmark.shield.fill"
        case .attention:
            return "exclamationmark.shield.fill"
        case .nonCompliant:
            return "xmark.shield.fill"
        case .unavailable:
            return "questionmark.shield.fill"
        }
    }
}

@MainActor
private final class NotaryStatusAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let reportStore = NotaryPublicReportStore()
    private let telemetrySampler = TelemetrySampler()
    private let bundleVersion = StatusBundleVersion.current()

    private var complianceRefreshTimer: Timer?
    private var telemetryTimer: Timer?
    private var latestState: NotaryPublicComplianceState = .unavailable
    private var latestReport: NotaryPublicReport?
    private var latestTelemetry: TelemetrySnapshot?
    private weak var headerView: NotaryStatusHeaderView?
    private weak var telemetryView: NotaryTelemetryTextView?
    private weak var versionView: NotaryVersionTextView?
    private var userRequestedQuit = false
    private var systemRequestedTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillPowerOff),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
        configureStatusItem()
        refreshCompliance()
        rebuildMenu()
        startComplianceRefreshTimer()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return (userRequestedQuit || systemRequestedTermination) ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopTelemetryTimer()
        complianceRefreshTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshCompliance()
        refreshTelemetry()
        startTelemetryTimer()
    }

    func menuDidClose(_ menu: NSMenu) {
        stopTelemetryTimer()
    }

    private func configureStatusItem() {
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "Notary"
    }

    private func startComplianceRefreshTimer() {
        complianceRefreshTimer?.invalidate()
        complianceRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCompliance()
            }
        }
    }

    private func startTelemetryTimer() {
        telemetryTimer?.invalidate()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshTelemetry()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        telemetryTimer = timer
    }

    private func stopTelemetryTimer() {
        telemetryTimer?.invalidate()
        telemetryTimer = nil
    }

    private func refreshCompliance() {
        let report = (try? reportStore.load()) ?? nil
        latestReport = report
        latestState = NotaryPublicComplianceState(report: report)
        statusItem.button?.image = statusIcon(for: latestState)
        statusItem.button?.toolTip = "Notary: \(latestState.displayTitle)"
        headerView?.state = latestState
        versionView?.text = versionDisplayText()
    }

    private func refreshTelemetry() {
        latestTelemetry = telemetrySampler.sample()
        telemetryView?.lines = telemetryLines(from: latestTelemetry)
    }

    private func updateVisibleViews() {
        headerView?.state = latestState
        telemetryView?.lines = telemetryLines(from: latestTelemetry)
        versionView?.text = versionDisplayText()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let header = NotaryStatusHeaderView(state: latestState)
        let headerItem = NSMenuItem()
        headerItem.view = header
        menu.addItem(headerItem)
        headerView = header

        let version = NotaryVersionTextView(text: versionDisplayText())
        let versionItem = NSMenuItem()
        versionItem.view = version
        menu.addItem(versionItem)
        versionView = version

        let telemetry = NotaryTelemetryTextView(lines: telemetryLines(from: latestTelemetry))
        let telemetryItem = NSMenuItem()
        telemetryItem.view = telemetry
        menu.addItem(telemetryItem)
        telemetryView = telemetry

        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Open Report in App", action: #selector(openReport), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func telemetryLines(from snapshot: TelemetrySnapshot?) -> [String] {
        guard let snapshot else {
            return ["CPU waiting", "Network waiting"]
        }

        let cpuLine: String
        if let cpu = snapshot.cpu, cpu.isPrimed {
            cpuLine = "CPU \(formatPercent(cpu.activeFraction))"
        } else {
            cpuLine = "CPU warming up"
        }

        let networkLine: String
        if let network = snapshot.network, network.isPrimed {
            networkLine = "Network up \(formatBytes(network.uploadBytesPerSecond))/s, down \(formatBytes(network.downloadBytesPerSecond))/s"
        } else {
            networkLine = "Network warming up"
        }

        return [cpuLine, networkLine]
    }

    private func versionDisplayText() -> String {
        if latestReport?.appTokenFeatures.contains("transporter") == true {
            return "\(bundleVersion.displayText) • Transport"
        }
        return bundleVersion.displayText
    }

    private func formatPercent(_ fraction: Double) -> String {
        "\(Int((max(0, min(1, fraction)) * 100).rounded()))%"
    }

    private func formatBytes(_ bytes: Double) -> String {
        if bytes >= 1_000_000 {
            return String(format: "%.1f MB", bytes / 1_000_000)
        }
        if bytes >= 1_000 {
            return String(format: "%.0f KB", bytes / 1_000)
        }
        return "\(Int(bytes.rounded())) B"
    }

    private func statusIcon(for state: NotaryPublicComplianceState) -> NSImage? {
        let image = NSImage(systemSymbolName: state.statusSymbolName, accessibilityDescription: "Notary \(state.displayTitle)")
        image?.isTemplate = true
        return image
    }

    @objc private func openReport() {
        if let app = runningNotaryApp() {
            postReportOpenRequest()
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        } else {
            launchNotaryAppExecutable()
        }
    }

    @objc private func quit() {
        userRequestedQuit = true
        NSApp.terminate(nil)
    }

    @objc private func systemWillPowerOff(_ notification: Notification) {
        systemRequestedTermination = true
    }

    private func runningNotaryApp() -> NSRunningApplication? {
        let executablePath = URL(fileURLWithPath: NotaryReportOpenRequest.appExecutablePath).standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.first { app in
            app.processIdentifier != getpid() &&
            app.executableURL?.standardizedFileURL.path == executablePath
        }
    }

    private func postReportOpenRequest() {
        DistributedNotificationCenter.default().postNotificationName(
            NotaryReportOpenRequest.notificationName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func launchNotaryAppExecutable() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: NotaryReportOpenRequest.appExecutablePath)
        do {
            try task.run()
        } catch {
            NSLog("[NotaryStatus] Failed to launch Notary app executable: %@", String(describing: error))
        }
    }
}

private struct StatusBundleVersion {
    let marketingVersion: String
    let build: String

    var displayText: String {
        "Version \(marketingVersion) (\(build))"
    }

    static func current() -> StatusBundleVersion {
        let bundle = containingAppBundle() ?? Bundle.main
        let info = bundle.infoDictionary ?? [:]
        let marketingVersion = info["CFBundleShortVersionString"] as? String ?? NotaryVersion.marketingVersion
        let build = info["CFBundleVersion"] as? String ?? NotaryVersion.label
        return StatusBundleVersion(marketingVersion: marketingVersion, build: build)
    }

    private static func containingAppBundle() -> Bundle? {
        guard let executableURL = Bundle.main.executableURL else {
            return nil
        }

        let appURL = executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        guard appURL.pathExtension == "app" else {
            return nil
        }

        return Bundle(url: appURL)
    }
}

private enum StatusMark {
    case check
    case warning
    case xmark
    case question
}

@MainActor
private final class NotaryStatusHeaderView: NSView {
    var state: NotaryPublicComplianceState {
        didSet {
            needsDisplay = true
        }
    }

    init(state: NotaryPublicComplianceState) {
        self.state = state
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 336))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        state.statusColor.setFill()
        bounds.fill()

        let shieldWidth: CGFloat = 142
        let shieldHeight: CGFloat = 158
        drawShield(
            in: NSRect(
                x: floor((bounds.width - shieldWidth) / 2),
                y: 104,
                width: shieldWidth,
                height: shieldHeight
            ),
            mark: state.statusMark
        )

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let summaryAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)
        ]

        NSAttributedString(string: state.displayTitle, attributes: titleAttrs)
            .draw(centeredIn: NSRect(x: 20, y: 278, width: bounds.width - 40, height: 38))
        NSAttributedString(string: state.userSentence, attributes: summaryAttrs)
            .draw(centeredIn: NSRect(x: 24, y: 48, width: bounds.width - 48, height: 44))
    }

    private func drawShield(in rect: NSRect, mark: StatusMark) {
        let shield = NSBezierPath()
        shield.move(to: NSPoint(x: rect.midX, y: rect.maxY))
        shield.curve(
            to: NSPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.22),
            controlPoint1: NSPoint(x: rect.midX + rect.width * 0.16, y: rect.maxY - rect.height * 0.02),
            controlPoint2: NSPoint(x: rect.maxX - rect.width * 0.08, y: rect.maxY - rect.height * 0.08)
        )
        shield.curve(
            to: NSPoint(x: rect.midX, y: rect.minY),
            controlPoint1: NSPoint(x: rect.maxX - rect.width * 0.02, y: rect.midY),
            controlPoint2: NSPoint(x: rect.midX + rect.width * 0.28, y: rect.minY + rect.height * 0.1)
        )
        shield.curve(
            to: NSPoint(x: rect.minX, y: rect.maxY - rect.height * 0.22),
            controlPoint1: NSPoint(x: rect.midX - rect.width * 0.28, y: rect.minY + rect.height * 0.1),
            controlPoint2: NSPoint(x: rect.minX + rect.width * 0.02, y: rect.midY)
        )
        shield.curve(
            to: NSPoint(x: rect.midX, y: rect.maxY),
            controlPoint1: NSPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY - rect.height * 0.08),
            controlPoint2: NSPoint(x: rect.midX - rect.width * 0.16, y: rect.maxY - rect.height * 0.02)
        )
        shield.close()

        NSColor.white.withAlphaComponent(0.98).setStroke()
        shield.lineWidth = 6
        shield.stroke()

        NSColor.white.setStroke()
        let markPath = NSBezierPath()
        markPath.lineWidth = 12
        markPath.lineCapStyle = .round
        markPath.lineJoinStyle = .round

        switch mark {
        case .check:
            markPath.move(to: NSPoint(x: rect.minX + rect.width * 0.28, y: rect.midY + rect.height * 0.01))
            markPath.line(to: NSPoint(x: rect.midX - rect.width * 0.06, y: rect.midY - rect.height * 0.2))
            markPath.line(to: NSPoint(x: rect.maxX - rect.width * 0.24, y: rect.midY + rect.height * 0.22))
            markPath.stroke()
        case .warning:
            markPath.move(to: NSPoint(x: rect.midX, y: rect.midY + rect.height * 0.25))
            markPath.line(to: NSPoint(x: rect.midX, y: rect.midY - rect.height * 0.12))
            markPath.stroke()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - 6, y: rect.midY - rect.height * 0.32, width: 12, height: 12)).fill()
        case .xmark:
            markPath.move(to: NSPoint(x: rect.minX + rect.width * 0.3, y: rect.midY + rect.height * 0.22))
            markPath.line(to: NSPoint(x: rect.maxX - rect.width * 0.3, y: rect.midY - rect.height * 0.22))
            markPath.move(to: NSPoint(x: rect.maxX - rect.width * 0.3, y: rect.midY + rect.height * 0.22))
            markPath.line(to: NSPoint(x: rect.minX + rect.width * 0.3, y: rect.midY - rect.height * 0.22))
            markPath.stroke()
        case .question:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 86, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            NSAttributedString(string: "?", attributes: attrs)
                .draw(centeredIn: NSRect(x: rect.minX, y: rect.midY - 52, width: rect.width, height: 104))
        }
    }
}

@MainActor
private final class NotaryVersionTextView: NSView {
    var text: String {
        didSet {
            needsDisplay = true
        }
    }

    init(text: String) {
        self.text = text
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 46))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.533, green: 0.533, blue: 0.533, alpha: 1.0)
        ]

        NSAttributedString(string: text, attributes: attrs)
            .draw(centeredIn: NSRect(x: 16, y: 13, width: bounds.width - 32, height: 20))
    }
}

@MainActor
private final class NotaryTelemetryTextView: NSView {
    var lines: [String] {
        didSet {
            needsDisplay = true
        }
    }

    init(lines: [String]) {
        self.lines = lines
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 54))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        for (index, line) in lines.prefix(2).enumerated() {
            let y = bounds.maxY - 22 - CGFloat(index * 18)
            NSAttributedString(string: line, attributes: attrs)
                .draw(in: NSRect(x: 16, y: y, width: bounds.width - 32, height: 16))
        }
    }
}

private extension NSAttributedString {
    func draw(centeredIn rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let centered = NSMutableAttributedString(attributedString: self)
        centered.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: centered.length))
        let size = self.size()
        let height = min(size.height + 4, rect.height)
        let drawRect = NSRect(
            x: rect.minX,
            y: rect.midY - (height / 2),
            width: rect.width,
            height: height
        )
        centered.draw(in: drawRect)
    }
}
