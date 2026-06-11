import Foundation
import AppKit
import ApplicationServices
import UniformTypeIdentifiers
import NotaryCore

@MainActor
enum NotaryGUI {
    static let appName = "Notary"
    private static var retainedUptimeAlertDelegate: NotaryUptimeAlertWindowDelegate?

    static func showReportWindow(logger: HardenLogger) {
        let app = NSApplication.shared
        let delegate = NotaryReportWindowDelegate(logger: logger, includeConfigurator: isCurrentUserAdmin())

        promoteProcessToForegroundApp()
        app.setActivationPolicy(.regular)
        app.mainMenu = makeMainMenu(delegate: delegate, includeConfigurator: delegate.includeConfigurator)
        app.delegate = delegate
        app.finishLaunching()
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    static func showConfiguratorPlaceholder() {
        let app = NSApplication.shared
        let delegate = NotaryConfiguratorWindowDelegate()

        promoteProcessToForegroundApp()
        app.setActivationPolicy(.regular)
        app.mainMenu = makeConfiguratorMenu(delegate: delegate)
        app.delegate = delegate
        app.finishLaunching()
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    static func showJamfReporterWindow(logger: HardenLogger) {
        let app = NSApplication.shared
        let delegate = NotaryJamfReporterWindowDelegate(logger: logger)

        promoteProcessToForegroundApp()
        app.setActivationPolicy(.regular)
        app.mainMenu = makeJamfReporterMenu(delegate: delegate)
        app.delegate = delegate
        app.finishLaunching()
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    static func showUptimeAlertWindow(logger: HardenLogger, payload: UptimeAlertPayload) {
        let app = NSApplication.shared
        let delegate = NotaryUptimeAlertWindowDelegate(logger: logger, payload: payload)
        retainedUptimeAlertDelegate = delegate

        promoteProcessToForegroundApp()
        app.setActivationPolicy(.regular)
        app.mainMenu = makePlaceholderMenu(delegate: delegate)
        app.delegate = delegate
        app.finishLaunching()
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    static func releaseRetainedUptimeAlertDelegate() {
        retainedUptimeAlertDelegate = nil
    }

    static func format(_ date: Date?) -> String {
        guard let date else { return "n/a" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    static func launchedVersionSummary() -> (marketing: String, build: String) {
        let info = Bundle.main.infoDictionary ?? [:]
        let marketing = (info["CFBundleShortVersionString"] as? String) ?? NotaryVersion.marketingVersion
        let build = (info["CFBundleVersion"] as? String) ?? NotaryVersion.label
        return (marketing, build)
    }

    private static func promoteProcessToForegroundApp() {
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
        TransformProcessType(&psn, ProcessApplicationTransformState(kProcessTransformToForegroundApplication))
    }

    fileprivate static func resolvedCGColor(_ color: NSColor, for view: NSView?) -> CGColor {
        var resolved = color.cgColor
        (view?.effectiveAppearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        return resolved
    }

    fileprivate static func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    fileprivate static func isDarkAppearance(for view: NSView?) -> Bool {
        isDarkAppearance(view?.effectiveAppearance ?? NSApp.effectiveAppearance)
    }

    static func adaptiveCGColor(light: NSColor, dark: NSColor, for view: NSView?) -> CGColor {
        (isDarkAppearance(for: view) ? dark : light).cgColor
    }

    static func applyPrimaryTextColor(in view: NSView) {
        if let textField = view as? NSTextField {
            textField.textColor = .labelColor
            textField.needsDisplay = true
        } else if let textView = view as? NSTextView {
            textView.textColor = .labelColor
            textView.insertionPointColor = .labelColor
            textView.needsDisplay = true
        }

        view.subviews.forEach { applyPrimaryTextColor(in: $0) }
    }

    fileprivate static func configuratorPlaceholderText() -> String {
        """
        NotaryConfigurator

        This window is the future home of the mobileconfig builder.

        Planned workflow:
        - open an existing `.mobileconfig` or managed preferences `.plist` and prefill known values
        - start with empty values and safe defaults (`Prüfen (Informativ)`)
        - export a new profile for managed deployment

        Planned payloads:
        - managed preferences for `de.twocent.notary`
        - PPPC / Full Disk Access for the runner service
        - managed login item
        - notification settings for `com.apple.btmnotificationsagent`

        Current state:
        - placeholder only
        - no write operations yet
        """
    }

    fileprivate static func bundledSchemaURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "Config-Schema-1.2", withExtension: "json") {
            return bundled
        }

        let fallback = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Config-Schema-1.2.json")
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }
        return nil
    }

    fileprivate static func makeMainMenu(delegate: NotaryReportWindowDelegate, includeConfigurator: Bool) -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        mainMenu.addItem(appItem)

        let appMenu = NSMenu(title: appName)
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NotaryReportWindowDelegate.showAboutPanel), keyEquivalent: "").target = delegate
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Refresh Report", action: #selector(NotaryReportWindowDelegate.refreshContent), keyEquivalent: "r").target = delegate

        if includeConfigurator {
            let reporterItem = NSMenuItem(title: "Open Jamf Reporter (BETA)", action: #selector(NotaryReportWindowDelegate.openJamfReporter), keyEquivalent: "j")
            reporterItem.target = delegate
            appMenu.addItem(reporterItem)

            let item = NSMenuItem(title: "Open Configurator", action: #selector(NotaryReportWindowDelegate.openConfiguratorPlaceholder), keyEquivalent: ",")
            item.target = delegate
            appMenu.addItem(item)
        }

        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Close", action: #selector(NotaryReportWindowDelegate.closeWindow), keyEquivalent: "w").target = delegate
        appMenu.addItem(withTitle: "Quit Notary", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Refresh Report", action: #selector(NotaryReportWindowDelegate.refreshContent), keyEquivalent: "").target = delegate
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    static func makeJamfReporterMenu(delegate: NotaryJamfReporterWindowDelegate) -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        mainMenu.addItem(appItem)

        let appMenu = NSMenu(title: appName)
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NotaryJamfReporterWindowDelegate.showAboutPanel), keyEquivalent: "").target = delegate
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Reload Devices", action: #selector(NotaryJamfReporterWindowDelegate.reloadDevices), keyEquivalent: "r").target = delegate
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Close", action: #selector(NotaryJamfReporterWindowDelegate.closeWindow), keyEquivalent: "w").target = delegate
        appMenu.addItem(withTitle: "Quit Notary", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Reload Devices", action: #selector(NotaryJamfReporterWindowDelegate.reloadDevices), keyEquivalent: "").target = delegate
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    static func makePlaceholderMenu(delegate: NSObject) -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        mainMenu.addItem(appItem)

        let appMenu = NSMenu(title: appName)
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NotaryWindowDelegate.showAboutPanel), keyEquivalent: "").target = delegate
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Close", action: #selector(NotaryWindowDelegate.closeWindow), keyEquivalent: "w").target = delegate
        appMenu.addItem(withTitle: "Quit Notary", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        return mainMenu
    }

    fileprivate static func makeConfiguratorMenu(delegate: NotaryConfiguratorWindowDelegate) -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        mainMenu.addItem(appItem)

        let appMenu = NSMenu(title: appName)
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NotaryConfiguratorWindowDelegate.showAboutPanel), keyEquivalent: "").target = delegate
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Reload Schema", action: #selector(NotaryConfiguratorWindowDelegate.reloadSchema), keyEquivalent: "r").target = delegate
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Close", action: #selector(NotaryConfiguratorWindowDelegate.closeWindow), keyEquivalent: "w").target = delegate
        appMenu.addItem(withTitle: "Quit Notary", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Reload Schema", action: #selector(NotaryConfiguratorWindowDelegate.reloadSchema), keyEquivalent: "").target = delegate
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    private static func isCurrentUserAdmin() -> Bool {
        guard let user = ManagedPrefs.consoleUser() else { return false }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/dseditgroup")
        task.arguments = ["-o", "checkmember", "-m", user, "admin"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}

@MainActor
private final class NotaryWindowDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let title: String
    private let refreshTitle: String?
    private let includeConfigurator: Bool
    private let contentProvider: () -> String

    private var window: NSWindow?
    private var textView: NSTextView?

    init(title: String, refreshTitle: String?, includeConfigurator: Bool = false, contentProvider: @escaping () -> String) {
        self.title = title
        self.refreshTitle = refreshTitle
        self.includeConfigurator = includeConfigurator
        self.contentProvider = contentProvider
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = buildWindow(frame: NSRect(x: 0, y: 0, width: 720, height: 520))
        refreshContent()

        window.makeKeyAndOrderFront(nil)
        ensureAppPresentation()
    }

    func buildWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.delegate = self

        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 70, width: frame.width - 40, height: frame.height - 100))
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.autoresizingMask = [.width, .height]
        scrollView.documentView = textView

        contentView.addSubview(scrollView)

        if let refreshTitle {
            let refreshButton = NSButton(frame: NSRect(x: 20, y: 20, width: 120, height: 32))
            refreshButton.title = refreshTitle
            refreshButton.target = self
            refreshButton.action = #selector(refreshContent)
            contentView.addSubview(refreshButton)
        }

        let closeButton = NSButton(frame: NSRect(x: frame.width - 140, y: 20, width: 120, height: 32))
        closeButton.title = "Close"
        closeButton.target = self
        closeButton.action = #selector(closeWindow)
        closeButton.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(closeButton)

        self.window = window
        self.textView = textView
        return window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        ensureAppPresentation()
    }

    @objc private func refreshContent() {
        textView?.string = contentProvider()
    }

    @objc func closeWindow() {
        window?.close()
    }

    @objc func showAboutPanel() {
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: NotaryGUI.appName,
            .applicationVersion: NotaryVersion.marketingVersion,
            .version: NotaryVersion.label,
            .credits: NSAttributedString(string: "Released under Apache-2.0 License. All rights reserved.")
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
        ensureAppPresentation()
    }

    private func ensureAppPresentation() {
        NSApp.setActivationPolicy(.regular)
        if includeConfigurator {
            // reserved for a later shared admin menu model
        }
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
}

@MainActor
final class AppearanceObservingView: NSView {
    var appearanceDidChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChange?()
    }
}

@MainActor
private final class NotaryReportWindowDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let logger: HardenLogger
    private let store = NotaryPublicReportStore()
    let includeConfigurator: Bool

    private var window: NSWindow?
    private var contentView: NSView?
    private var headerCard: NSView?
    private var deviceIconCard: NSView?
    private var deviceIconView: NSImageView?
    private var headerTitleField: NSTextField?
    private var headerSubtitleField: NSTextField?
    private var headerMetricsDivider: NSBox?
    private var runnerMetric: ReportMetricView?
    private var complianceMetric: ReportMetricView?
    private var lastUpdateMetric: ReportMetricView?
    private var serialMetric: ReportMetricView?
    private var modelMetric: ReportMetricView?
    private var managementMetric: ReportMetricView?
    private var issuesCard: NSView?
    private var issuesView: NSTextView?
    private var detailsCard: NSView?
    private var detailView: NSTextView?
    private var footerField: NSTextField?
    private var aboutButton: NSButton?
    private var refreshButton: NSButton?
    private var closeButton: NSButton?
    // Auxiliary window delegates must outlive AppKit's close animations. We
    // intentionally retain them until the main app exits to avoid late releases
    // while Reporter/Configurator windows are being torn down.
    private var auxiliaryDelegates: [AnyObject] = []

    private var reportPollTimer: Timer?
    private var lastObservedReportStamp: Date?
    private var isShuttingDown = false
    private let issueSectionByValue = CheckIssueCatalog.sectionByIssueValue()

    init(logger: HardenLogger, includeConfigurator: Bool) {
        self.logger = logger
        self.includeConfigurator = includeConfigurator
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1260, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NotaryGUI.appName
        window.center()
        window.delegate = self
        window.minSize = NSSize(width: 1080, height: 760)

        let contentView = AppearanceObservingView(frame: window.contentView?.bounds ?? .zero)
        contentView.appearanceDidChange = { [weak self] in
            self?.applyAppearanceColors()
        }
        contentView.wantsLayer = true
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView
        self.contentView = contentView

        let headerCard = makeSurfaceCard()
        contentView.addSubview(headerCard)
        self.headerCard = headerCard

        let deviceIconCard = makeSurfaceCard()
        headerCard.addSubview(deviceIconCard)
        self.deviceIconCard = deviceIconCard

        let deviceIconView = NSImageView(frame: .zero)
        deviceIconView.imageScaling = .scaleProportionallyUpOrDown
        deviceIconView.contentTintColor = NSColor.systemBlue.withAlphaComponent(0.9)
        deviceIconView.image = NSImage(
            systemSymbolName: HardwareInfo.isDesktopMac() ? "desktopcomputer" : "laptopcomputer",
            accessibilityDescription: "Device"
        )
        deviceIconCard.addSubview(deviceIconView)
        self.deviceIconView = deviceIconView

        let headerTitleField = NSTextField(labelWithString: Host.current().localizedName ?? "This Mac")
        headerTitleField.font = NSFont.systemFont(ofSize: 30, weight: .bold)
        headerTitleField.lineBreakMode = .byTruncatingTail
        headerCard.addSubview(headerTitleField)
        self.headerTitleField = headerTitleField

        let headerSubtitleField = NSTextField(labelWithString: "macOS overview for local proof and transport state")
        headerSubtitleField.textColor = .secondaryLabelColor
        headerSubtitleField.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        headerCard.addSubview(headerSubtitleField)
        self.headerSubtitleField = headerSubtitleField

        let headerMetricsDivider = NSBox(frame: .zero)
        headerMetricsDivider.boxType = .separator
        headerMetricsDivider.borderColor = NSColor.separatorColor.withAlphaComponent(0.65)
        headerCard.addSubview(headerMetricsDivider)
        self.headerMetricsDivider = headerMetricsDivider

        let runnerMetric = ReportMetricView(title: "Runner")
        let complianceMetric = ReportMetricView(title: "Compliance")
        let lastUpdateMetric = ReportMetricView(title: "Last Update")
        let serialMetric = ReportMetricView(title: "Serial Number")
        let modelMetric = ReportMetricView(title: "Model")
        let managementMetric = ReportMetricView(title: "Management")
        [runnerMetric, complianceMetric, lastUpdateMetric, serialMetric, modelMetric, managementMetric].forEach {
            headerCard.addSubview($0)
        }
        self.runnerMetric = runnerMetric
        self.complianceMetric = complianceMetric
        self.lastUpdateMetric = lastUpdateMetric
        self.serialMetric = serialMetric
        self.modelMetric = modelMetric
        self.managementMetric = managementMetric

        let issuesSection = makeTextSection(title: "Issues")
        contentView.addSubview(issuesSection.container)
        self.issuesCard = issuesSection.container
        self.issuesView = issuesSection.textView

        let detailsSection = makeTextSection(title: "Details")
        contentView.addSubview(detailsSection.container)
        self.detailsCard = detailsSection.container
        self.detailView = detailsSection.textView

        let footerField = NSTextField(labelWithString: "The GUI reacts to report changes and stays read-only by design.")
        footerField.textColor = .secondaryLabelColor
        footerField.autoresizingMask = [.maxXMargin, .minYMargin]
        contentView.addSubview(footerField)
        self.footerField = footerField

        let aboutButton = NSButton(frame: .zero)
        aboutButton.title = "About"
        aboutButton.target = self
        aboutButton.action = #selector(showAboutPanel)
        aboutButton.autoresizingMask = [.minXMargin, .minYMargin]
        contentView.addSubview(aboutButton)
        self.aboutButton = aboutButton

        let refreshButton = NSButton(frame: .zero)
        refreshButton.title = "Refresh"
        refreshButton.target = self
        refreshButton.action = #selector(refreshContent)
        refreshButton.autoresizingMask = [.minXMargin, .minYMargin]
        contentView.addSubview(refreshButton)
        self.refreshButton = refreshButton

        let closeButton = NSButton(frame: .zero)
        closeButton.title = "Close"
        closeButton.target = self
        closeButton.action = #selector(closeWindow)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        contentView.addSubview(closeButton)
        self.closeButton = closeButton

        self.window = window
        applyAppearanceColors()
        layoutReportWindow()
        refreshContent()
        startMonitoringReportFile()
        window.makeKeyAndOrderFront(nil)
        ensureAppPresentation()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        beginShutdown()
    }

    func windowWillClose(_ notification: Notification) {
        beginShutdown()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        ensureAppPresentation()
    }

    func windowDidResize(_ notification: Notification) {
        layoutReportWindow()
    }

    @objc func refreshContent() {
        guard !isShuttingDown else { return }

        do {
            guard let report = try store.load() else {
                headerTitleField?.stringValue = Host.current().localizedName ?? "This Mac"
                headerSubtitleField?.stringValue = systemVersionSummary()
                runnerMetric?.value = "Waiting"
                complianceMetric?.value = "No report yet"
                lastUpdateMetric?.value = "n/a"
                serialMetric?.value = "n/a"
                modelMetric?.value = "n/a"
                managementMetric?.value = "Standalone"
                issuesView?.string = """
                No public Notary report is available yet.

                Expected sources:
                - `notary --run`
                - `notary --engagement`
                """
                detailView?.string = """
                This GUI is report-only.

                It reads a sanitized public report and does not access the protected internal state.
                """
                return
            }

            let launchedVersion = NotaryGUI.launchedVersionSummary()
            let versionMismatch = launchedVersion.marketing != report.marketingVersion || launchedVersion.build != report.versionLabel
            let versionNote = versionMismatch ? "\n\nVersion note:\n- this app bundle differs from the last reported runner build" : ""

            headerTitleField?.stringValue = Host.current().localizedName ?? "This Mac"
            headerSubtitleField?.stringValue = systemVersionSummary()
            runnerMetric?.value = formattedMetricValue(report.runnerStatus)
            complianceMetric?.value = formattedMetricValue(report.complianceValue)
            lastUpdateMetric?.value = NotaryGUI.format(report.lastTransportUpdateAt ?? report.generatedAt)
            serialMetric?.value = report.serialNumber ?? "n/a"
            modelMetric?.value = report.hardwareModel ?? "n/a"
            managementMetric?.value = formattedManagementValue(report)
            issuesView?.string = formatIssuesForDisplay(report.issuesValue)
            detailView?.string = """
            \(formatProofSummary(report))

            Generated: \(NotaryGUI.format(report.generatedAt))
            Last run: \(NotaryGUI.format(report.lastRunAt))
            Last transport: \(NotaryGUI.format(report.lastTransportUpdateAt))

            Device context:
            - serial number: \(report.serialNumber ?? "n/a")
            - model: \(report.hardwareModel ?? "n/a")
            - management: \(formattedManagementValue(report))

            Reported runner version: \(report.marketingVersion) (\(report.versionLabel))
            Started app version: \(launchedVersion.marketing) (\(launchedVersion.build))\(versionNote)

            Source of truth:
            - protected internal state remains private
            - this window only reflects the public report output
            """
        } catch {
            logger.error("[NotaryGUI] Failed to read public report: \(error)")
            headerSubtitleField?.stringValue = systemVersionSummary()
            runnerMetric?.value = "Read error"
            complianceMetric?.value = "Unavailable"
            lastUpdateMetric?.value = "n/a"
            serialMetric?.value = "n/a"
            modelMetric?.value = "n/a"
            managementMetric?.value = "Unknown"
            issuesView?.string = "Failed to load report."
            detailView?.string = "\(error)"
        }
    }

    @objc func openConfiguratorPlaceholder() {
        let delegate = NotaryConfiguratorWindowDelegate(terminatesApplicationOnClose: false)
        delegate.onClose = { [weak self] in
            self?.ensureAppPresentation()
        }
        auxiliaryDelegates.append(delegate)
        let window = delegate.buildWindow(frame: NSRect(x: 0, y: 0, width: 1520, height: 920))
        delegate.reloadSchema()
        window.makeKeyAndOrderFront(nil)
        ensureAppPresentation()
    }

    @objc func openJamfReporter() {
        let delegate = NotaryJamfReporterWindowDelegate(logger: logger, terminatesApplicationOnClose: false)
        delegate.onClose = { [weak self] in
            self?.ensureAppPresentation()
        }
        auxiliaryDelegates.append(delegate)
        let window = delegate.buildWindow(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        window.makeKeyAndOrderFront(nil)
        delegate.reloadDevices()
        ensureAppPresentation()
    }

    @objc func showAboutPanel() {
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: NotaryGUI.appName,
            .applicationVersion: NotaryVersion.marketingVersion,
            .version: NotaryVersion.label,
            .credits: NSAttributedString(string: "Released under Apache-2.0 License. All rights reserved.")
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
        ensureAppPresentation()
    }

    @objc func closeWindow() {
        window?.close()
    }

    private func startMonitoringReportFile() {
        guard !isShuttingDown, reportPollTimer == nil else { return }
        lastObservedReportStamp = currentReportStamp()
        reportPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollReportFile()
            }
        }
    }

    private func stopMonitoringReportFile() {
        reportPollTimer?.invalidate()
        reportPollTimer = nil
    }

    private func pollReportFile() {
        guard !isShuttingDown else { return }
        let currentStamp = currentReportStamp()
        guard currentStamp != lastObservedReportStamp else { return }
        lastObservedReportStamp = currentStamp
        refreshContent()
    }

    private func currentReportStamp() -> Date? {
        let url = store.preferredReadURL
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    private func beginShutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        stopMonitoringReportFile()
    }

    private func ensureAppPresentation() {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = NotaryGUI.makeMainMenu(delegate: self, includeConfigurator: includeConfigurator)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    private func applyAppearanceColors() {
        guard let contentView else { return }
        let windowColor = NotaryGUI.adaptiveCGColor(
            light: NSColor(calibratedWhite: 0.955, alpha: 1.0),
            dark: NSColor(calibratedWhite: 0.10, alpha: 1.0),
            for: contentView
        )
        let surfaceColor = NotaryGUI.adaptiveCGColor(
            light: .white,
            dark: NSColor(calibratedWhite: 0.16, alpha: 1.0),
            for: contentView
        )
        let borderColor = NotaryGUI.adaptiveCGColor(
            light: NSColor.separatorColor.withAlphaComponent(0.55),
            dark: NSColor.white.withAlphaComponent(0.10),
            for: contentView
        )

        contentView.layer?.backgroundColor = windowColor
        NotaryGUI.applyPrimaryTextColor(in: contentView)
        [headerCard, issuesCard, detailsCard].forEach { card in
            card?.layer?.backgroundColor = surfaceColor
            card?.layer?.borderColor = borderColor
            card?.layer?.borderWidth = 1.0
            card?.layer?.shadowColor = NotaryGUI.adaptiveCGColor(
                light: NSColor.shadowColor.withAlphaComponent(0.18),
                dark: NSColor.black.withAlphaComponent(0.55),
                for: contentView
            )
        }
        deviceIconCard?.layer?.backgroundColor = NotaryGUI.adaptiveCGColor(
            light: NSColor(calibratedWhite: 0.96, alpha: 1.0),
            dark: NSColor(calibratedWhite: 0.20, alpha: 1.0),
            for: contentView
        )
        deviceIconCard?.layer?.borderColor = borderColor
        deviceIconCard?.layer?.borderWidth = 1.0
        deviceIconView?.contentTintColor = .systemBlue
        deviceIconView?.needsDisplay = true

        [headerTitleField].forEach { $0?.textColor = .labelColor }
        [headerSubtitleField, footerField].forEach { $0?.textColor = .secondaryLabelColor }
        [issuesView, detailView].forEach { textView in
            textView?.textColor = .labelColor
            textView?.insertionPointColor = .labelColor
            textView?.needsDisplay = true
        }
        [runnerMetric, complianceMetric, lastUpdateMetric, serialMetric, modelMetric, managementMetric].forEach {
            $0?.applyAppearanceColors()
        }
    }

    private func layoutReportWindow() {
        guard let contentView else { return }

        let bounds = contentView.bounds
        let margin: CGFloat = 28
        let interSection: CGFloat = 22
        let footerHeight: CGFloat = 40
        let buttonWidth: CGFloat = 110
        let buttonHeight: CGFloat = 34
        let buttonGap: CGFloat = 12
        let headerHeight: CGFloat = min(220, max(180, bounds.height * 0.27))

        let closeX = bounds.width - margin - buttonWidth
        closeButton?.frame = NSRect(x: closeX, y: margin, width: buttonWidth, height: buttonHeight)
        refreshButton?.frame = NSRect(x: closeX - buttonGap - buttonWidth, y: margin, width: buttonWidth, height: buttonHeight)
        let aboutX = closeX - (buttonGap * 2) - (buttonWidth * 2)
        aboutButton?.frame = NSRect(x: aboutX, y: margin, width: buttonWidth, height: buttonHeight)
        footerField?.frame = NSRect(x: margin, y: margin + 6, width: max(280, aboutButton?.frame.minX ?? bounds.width - margin - 280), height: 24)

        let headerY = bounds.height - margin - headerHeight
        headerCard?.frame = NSRect(x: margin, y: headerY, width: bounds.width - (margin * 2), height: headerHeight)

        if let headerCard {
            let iconOuterSize: CGFloat = 118
            deviceIconCard?.frame = NSRect(x: 26, y: headerCard.bounds.height - 42 - iconOuterSize, width: iconOuterSize, height: iconOuterSize)
            deviceIconCard?.layer?.cornerRadius = 24
            deviceIconView?.frame = deviceIconCard?.bounds.insetBy(dx: 18, dy: 18) ?? .zero

            let textStartX = 26 + iconOuterSize + 24
            let metricsStartY = headerCard.bounds.height - 152
            let metricsWidth = headerCard.bounds.width - textStartX - 26
            let metricGap: CGFloat = 18
            let metricWidth = max(180, floor((metricsWidth - (metricGap * 2)) / 3))
            let metricHeight: CGFloat = 54

            headerTitleField?.frame = NSRect(x: textStartX, y: headerCard.bounds.height - 62, width: metricsWidth, height: 34)
            headerSubtitleField?.frame = NSRect(x: textStartX, y: headerCard.bounds.height - 94, width: metricsWidth, height: 20)

            let metricFrames = [
                NSRect(x: textStartX, y: metricsStartY, width: metricWidth, height: metricHeight),
                NSRect(x: textStartX + metricWidth + metricGap, y: metricsStartY, width: metricWidth, height: metricHeight),
                NSRect(x: textStartX + ((metricWidth + metricGap) * 2), y: metricsStartY, width: metricWidth, height: metricHeight),
                NSRect(x: textStartX, y: metricsStartY - metricHeight - 8, width: metricWidth, height: metricHeight),
                NSRect(x: textStartX + metricWidth + metricGap, y: metricsStartY - metricHeight - 8, width: metricWidth, height: metricHeight),
                NSRect(x: textStartX + ((metricWidth + metricGap) * 2), y: metricsStartY - metricHeight - 8, width: metricWidth, height: metricHeight)
            ]

            [runnerMetric, complianceMetric, lastUpdateMetric, serialMetric, modelMetric, managementMetric]
                .enumerated()
                .forEach { index, metric in
                    metric?.frame = metricFrames[index]
                }

            let dividerY = metricsStartY - 5
            headerMetricsDivider?.frame = NSRect(
                x: textStartX,
                y: dividerY,
                width: (metricWidth * 3) + (metricGap * 2),
                height: 1
            )
        }

        let cardsTop = headerY - interSection
        let cardsBottom = margin + footerHeight + interSection
        let cardsHeight = max(260, cardsTop - cardsBottom)
        let leftWidth = floor((bounds.width - (margin * 2) - interSection) * 0.52)
        let rightWidth = bounds.width - (margin * 2) - interSection - leftWidth

        issuesCard?.frame = NSRect(x: margin, y: cardsBottom, width: leftWidth, height: cardsHeight)
        detailsCard?.frame = NSRect(x: margin + leftWidth + interSection, y: cardsBottom, width: rightWidth, height: cardsHeight)
        layoutTextSection(issuesCard)
        layoutTextSection(detailsCard)
    }

    private func makeSurfaceCard() -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.cornerRadius = 20
        container.layer?.shadowOpacity = 1.0
        container.layer?.shadowRadius = 14
        container.layer?.shadowOffset = CGSize(width: 0, height: -1)
        return container
    }

    private func formattedMetricValue(_ value: String) -> String {
        value.replacingOccurrences(of: " – ", with: "\n")
    }

    private func makeTextSection(title: String) -> (container: NSView, textView: NSTextView) {
        let container = makeSurfaceCard()
        let titleField = NSTextField(labelWithString: title)
        titleField.identifier = NSUserInterfaceItemIdentifier("sectionTitle")
        titleField.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        container.addSubview(titleField)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.identifier = NSUserInterfaceItemIdentifier("sectionScroll")
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 0, height: 4)
        scrollView.documentView = textView
        container.addSubview(scrollView)

        return (container, textView)
    }

    private func layoutTextSection(_ container: NSView?) {
        guard let container else { return }
        let titleField = container.subviews.compactMap { $0 as? NSTextField }.first
        let scrollView = container.subviews.compactMap { $0 as? NSScrollView }.first
        titleField?.frame = NSRect(x: 20, y: container.bounds.height - 36, width: container.bounds.width - 40, height: 24)
        scrollView?.frame = NSRect(x: 20, y: 18, width: container.bounds.width - 40, height: container.bounds.height - 64)
    }

    private func systemVersionSummary() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion) • local proof and transport overview (\(NotaryVersion.label))"
    }

    private func formattedManagementValue(_ report: NotaryPublicReport) -> String {
        guard let host = report.managementHost, !host.isEmpty else { return "Standalone" }
        if let id = report.managementComputerID {
            return "\(host) (\(id))"
        }
        return host
    }

    private func formatIssuesForDisplay(_ issues: String) -> String {
        if issues == "EMPTY" {
            return "No current findings."
        }

        let entries = issues
            .components(separatedBy: " • ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !entries.isEmpty else { return "No current findings." }

        var grouped: [String: [String]] = [:]
        for entry in entries {
            let lookupValue = entry
                .replacingOccurrences(of: "UNKNOWN: ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let section = issueSectionByValue[lookupValue] ?? "Other"
            grouped[section, default: []].append(entry)
        }

        return grouped
            .keys
            .sorted()
            .map { section in
                let items = (grouped[section] ?? []).sorted()
                return """
                \(section)
                \(items.map { "- \($0)" }.joined(separator: "\n"))
                """
            }
            .joined(separator: "\n\n")
    }

    private func formatProofSummary(_ report: NotaryPublicReport) -> String {
        let percent = report.compliancePercent.map { "\($0)%" } ?? percentageFromComplianceValue(report.complianceValue)
        var lines = [
            "Proof summary:",
            "- compliance percentage: \(percent)"
        ]
        appendProofCount("passed", report.passedCount, to: &lines, includeZero: true)
        appendProofCount("failed", report.failedCount, to: &lines)
        appendProofCount("unknown", report.unknownCount, to: &lines)
        appendProofCount("timed out", report.timedOutCount, to: &lines)
        appendProofCount("skipped", report.skippedCount, to: &lines)
        return lines.joined(separator: "\n")
    }

    private func appendProofCount(_ label: String, _ value: Int?, to lines: inout [String], includeZero: Bool = false) {
        guard let value else {
            lines.append("- \(label): n/a")
            return
        }
        if value != 0 || includeZero {
            lines.append("- \(label): \(value)")
        }
    }

    private func percentageFromComplianceValue(_ value: String) -> String {
        guard let start = value.lastIndex(of: "("),
              let end = value.lastIndex(of: ")"),
              start < end else {
            return "n/a"
        }
        return String(value[value.index(after: start)..<end])
    }
}

@MainActor
private final class NotaryConfiguratorWindowDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSSearchFieldDelegate {
    private let terminatesApplicationOnClose: Bool
    var onClose: (() -> Void)?
    private var window: NSWindow?
    private var outlineView: NSOutlineView?
    private var nodes: [ConfigNode] = []
    private var selectedNode: ConfigNode?

    private var headerTitleField: NSTextField?
    private var headerSubtitleField: NSTextField?
    private var leftPane: NSView?
    private var leftCardContainer: NSView?
    private var rightPane: NSView?
    private var verticalDivider: NSBox?
    private var outlineScrollView: NSScrollView?
    private var searchField: NSSearchField?
    private var rightCardContainer: NSView?
    private var editorSectionContainer: NSView?
    private var infoSectionContainer: NSView?
    private var titleField: NSTextField?
    private var summaryField: NSTextField?
    private var keyField: NSTextField?
    private var typeField: NSTextField?
    private var defaultField: NSTextField?
    private var currentValueField: NSTextField?
    private var editorContainer: NSView?
    private var infoView: NSTextView?
    private var debugDetailsButton: NSButton?
    private var configState: [String: String] = [:]
    private var visibleNodes: [ConfigNode] = []
    private var showsDebugDetails = false
    private let issueReferencesByKeyPath = CheckIssueCatalog.referenceByKeyPath()
    private var openButton: NSButton?
    private var exportButton: NSButton?
    private var importStatusField: NSTextField?

    init(terminatesApplicationOnClose: Bool = true, onClose: (() -> Void)? = nil) {
        self.terminatesApplicationOnClose = terminatesApplicationOnClose
        self.onClose = onClose
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = buildWindow(frame: NSRect(x: 0, y: 0, width: 1520, height: 920))
        reloadSchema()
        window.makeKeyAndOrderFront(nil)
        ensureAppPresentation()
    }

    func buildWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NotaryConfigurator"
        window.minSize = NSSize(width: 1400, height: 860)
        window.center()
        window.delegate = self

        let contentView = AppearanceObservingView(frame: window.contentView?.bounds ?? .zero)
        contentView.appearanceDidChange = { [weak self] in
            self?.applyAppearanceColors()
        }
        contentView.wantsLayer = true
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        let title = NSTextField(labelWithString: "NotaryConfigurator")
        title.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        contentView.addSubview(title)
        self.headerTitleField = title

        let subtitle = NSTextField(labelWithString: "Schema-driven configurator for the future mobileconfig builder")
        subtitle.textColor = .secondaryLabelColor
        contentView.addSubview(subtitle)
        self.headerSubtitleField = subtitle

        let leftPane = NSView(frame: .zero)
        contentView.addSubview(leftPane)
        self.leftPane = leftPane

        let divider = NSBox(frame: .zero)
        divider.boxType = .separator
        contentView.addSubview(divider)
        self.verticalDivider = divider

        let rightPane = NSView(frame: .zero)
        contentView.addSubview(rightPane)
        self.rightPane = rightPane

        let leftCard = makeCard(frame: leftPane.bounds, title: "Configuration Tree")
        leftCard.container.autoresizingMask = [.width, .height]
        leftPane.addSubview(leftCard.container)
        self.leftCardContainer = leftCard.container

        let outlineScroll = NSScrollView(frame: .zero)
        outlineScroll.autoresizingMask = [.width, .height]
        outlineScroll.hasVerticalScroller = true
        outlineScroll.autohidesScrollers = true
        outlineScroll.drawsBackground = false

        let outline = NSOutlineView(frame: outlineScroll.bounds)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.title = "Entry"
        column.width = 360
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .medium
        outline.delegate = self
        outline.dataSource = self
        outlineScroll.documentView = outline
        leftCard.container.addSubview(outlineScroll)
        self.outlineView = outline
        self.outlineScrollView = outlineScroll

        let searchField = NSSearchField(frame: .zero)
        searchField.placeholderString = "Filter settings"
        searchField.target = self
        searchField.action = #selector(filterTreeChanged(_:))
        searchField.delegate = self
        leftCard.container.addSubview(searchField)
        self.searchField = searchField

        let rightCard = makeCard(frame: rightPane.bounds, title: "Details")
        rightCard.container.autoresizingMask = [.width, .height]
        rightPane.addSubview(rightCard.container)
        self.rightCardContainer = rightCard.container

        let titleField = NSTextField(wrappingLabelWithString: "Select a field")
        titleField.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleField.autoresizingMask = [.width, .minYMargin]
        rightCard.container.addSubview(titleField)
        self.titleField = titleField

        let summaryField = NSTextField(wrappingLabelWithString: "Select a schema entry to inspect its default value, allowed states and current editor behavior.")
        summaryField.textColor = .secondaryLabelColor
        summaryField.autoresizingMask = [.width, .minYMargin]
        rightCard.container.addSubview(summaryField)
        self.summaryField = summaryField

        let keyField = NSTextField(labelWithString: "Key path: –")
        keyField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        keyField.textColor = .secondaryLabelColor
        keyField.lineBreakMode = .byTruncatingMiddle
        keyField.autoresizingMask = [.width, .minYMargin]
        rightCard.container.addSubview(keyField)
        self.keyField = keyField

        let typeField = NSTextField(labelWithString: "Type: –")
        typeField.autoresizingMask = [.width, .minYMargin]
        rightCard.container.addSubview(typeField)
        self.typeField = typeField

        let defaultField = NSTextField(labelWithString: "Default: –")
        defaultField.autoresizingMask = [.width, .minYMargin]
        rightCard.container.addSubview(defaultField)
        self.defaultField = defaultField

        let currentValueField = NSTextField(labelWithString: "Current: –")
        currentValueField.textColor = .secondaryLabelColor
        currentValueField.autoresizingMask = [.width, .minYMargin]
        rightCard.container.addSubview(currentValueField)
        self.currentValueField = currentValueField

        let editorCard = makeEmbeddedEditorSection(
            parentBounds: rightPane.bounds,
            y: 0,
            height: 148,
            title: "Bearbeiten"
        )
        rightCard.container.addSubview(editorCard.container)
        self.editorContainer = editorCard.editorHost
        self.editorSectionContainer = editorCard.container

        let infoSection = makeEmbeddedTextSection(
            parentBounds: rightPane.bounds,
            y: 0,
            height: 220,
            title: "Reference & Notes"
        )
        rightCard.container.addSubview(infoSection.container)
        self.infoView = infoSection.textView
        self.infoSectionContainer = infoSection.container

        let debugDetailsButton = NSButton(checkboxWithTitle: "Debug details", target: self, action: #selector(toggleDebugDetails(_:)))
        debugDetailsButton.toolTip = "Show the previous technical schema notes for troubleshooting."
        infoSection.container.addSubview(debugDetailsButton)
        self.debugDetailsButton = debugDetailsButton

        let payloadFootnote = NSTextField(wrappingLabelWithString: "Import reads `.mobileconfig` exports or managed preference `.plist` files. Embedded operational payloads remain automatic.")
        payloadFootnote.textColor = .secondaryLabelColor
        payloadFootnote.maximumNumberOfLines = 2
        contentView.addSubview(payloadFootnote)
        self.importStatusField = payloadFootnote

        let openButton = NSButton(frame: .zero)
        openButton.title = "Import Config"
        openButton.target = self
        openButton.action = #selector(openExistingProfile)
        contentView.addSubview(openButton)
        self.openButton = openButton

        let exportButton = NSButton(frame: .zero)
        exportButton.title = "Export Profile"
        exportButton.isEnabled = true
        exportButton.target = self
        exportButton.action = #selector(exportProfile)
        contentView.addSubview(exportButton)
        self.exportButton = exportButton

        self.window = window
        applyAppearanceColors()
        layoutConfiguratorWindow()
        return window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        terminatesApplicationOnClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        if terminatesApplicationOnClose {
            NSApp.terminate(nil)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        ensureAppPresentation()
    }

    func windowDidResize(_ notification: Notification) {
        layoutConfiguratorWindow()
    }

    @objc func reloadSchema() {
        do {
            nodes = try ConfigSchemaLoader.loadNodes()
            visibleNodes = nodes
            configState = [:]
            seedDefaults(from: nodes)
            applyTreeFilter(selectFirst: true)
            exportButton?.isEnabled = true
        } catch {
            exportButton?.isEnabled = false
            updateDetails(for: nil, error: error.localizedDescription)
        }
    }

    @objc func showAboutPanel() {
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: NotaryGUI.appName,
            .applicationVersion: NotaryVersion.marketingVersion,
            .version: NotaryVersion.label,
            .credits: NSAttributedString(string: "Released under Apache-2.0 License. All rights reserved.")
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
        ensureAppPresentation()
    }

    @objc func closeWindow() {
        window?.close()
    }

    @objc func openExistingProfile() {
        let panel = NSOpenPanel()
        panel.title = "Import Notary configuration"
        var allowedTypes: [UTType] = []
        if let mobileconfigType = UTType(filenameExtension: "mobileconfig") {
            allowedTypes.append(mobileconfigType)
        }
        if let plistType = UTType(filenameExtension: "plist") {
            allowedTypes.append(plistType)
        }
        panel.allowedContentTypes = allowedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let imported = try MobileConfigImport.importNotaryValues(from: url)
            for (key, value) in imported {
                configState[key] = value
            }
            importStatusField?.stringValue = "Imported \(imported.count) values from \(url.lastPathComponent). Embedded operational payloads remain untouched."
            importStatusField?.textColor = .secondaryLabelColor
            updateDetails(for: selectedNode, error: nil)
        } catch {
            importStatusField?.stringValue = "Import failed: \(error.localizedDescription)"
            importStatusField?.textColor = .systemRed
        }
    }

    @objc func exportProfile() {
        let panel = NSSavePanel()
        panel.title = "Export Notary mobileconfig"
        panel.nameFieldStringValue = "Notary Compliance Reporting.mobileconfig"
        if let mobileconfigType = UTType(filenameExtension: "mobileconfig") {
            panel.allowedContentTypes = [mobileconfigType]
        }
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let fieldCount = try MobileConfigExport.exportProfile(configState: configState, nodes: nodes, to: url)
            importStatusField?.stringValue = "Exported \(fieldCount) schema-backed values to \(url.lastPathComponent). Operational payloads were embedded automatically."
            importStatusField?.textColor = .secondaryLabelColor
        } catch {
            importStatusField?.stringValue = "Export failed: \(error.localizedDescription)"
            importStatusField?.textColor = .systemRed
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let node = item as? ConfigNode
        return (node?.children ?? visibleNodes).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let node = item as? ConfigNode
        return (node?.children ?? visibleNodes)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? ConfigNode else { return false }
        return !node.children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? ConfigNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("ConfigNodeCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        let textField = cell.textField ?? NSTextField(labelWithString: "")
        textField.frame = NSRect(x: 4, y: 2, width: (tableColumn?.width ?? 240) - 8, height: 18)
        textField.font = node.kind == .section
            ? NSFont.systemFont(ofSize: 13, weight: .semibold)
            : NSFont.systemFont(ofSize: 12.5, weight: .regular)
        textField.lineBreakMode = .byTruncatingTail
        textField.textColor = .labelColor
        textField.toolTip = node.title
        textField.stringValue = node.title
        if cell.textField == nil {
            cell.addSubview(textField)
            cell.textField = textField
        }
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outlineView, outlineView.selectedRow >= 0,
              let node = outlineView.item(atRow: outlineView.selectedRow) as? ConfigNode else {
            return
        }
        select(node: node)
    }

    private func select(node: ConfigNode) {
        selectedNode = node
        updateDetails(for: node, error: nil)
    }

    private func updateDetails(for node: ConfigNode?, error: String?) {
        if let error {
            titleField?.stringValue = "Schema unavailable"
            summaryField?.stringValue = "The bundled read-only schema could not be loaded."
            keyField?.stringValue = "Key path: –"
            typeField?.stringValue = "Type: –"
            defaultField?.stringValue = "Default: –"
            currentValueField?.stringValue = "Current: –"
            infoView?.string = "No schema values available.\n\n\(error)"
            renderEditor(for: nil)
            return
        }

        guard let node else {
            titleField?.stringValue = "Select a field"
            summaryField?.stringValue = "Choose a schema entry on the left to inspect defaults, allowed values and future configurator behavior."
            keyField?.stringValue = "Key path: –"
            typeField?.stringValue = "Type: –"
            defaultField?.stringValue = "Default: –"
            currentValueField?.stringValue = "Current: –"
            infoView?.string = ""
            renderEditor(for: nil)
            return
        }

        titleField?.stringValue = node.title
        summaryField?.stringValue = node.kind == .section ? friendlySummary(for: node) : ""
        keyField?.stringValue = "Pfad: \(node.keyPath)"
        typeField?.stringValue = allowedValuesText(for: node)
        defaultField?.stringValue = "Standard: \(displayTitle(for: node.defaultValue, in: node) ?? "–")"
        currentValueField?.stringValue = ""

        infoView?.string = showsDebugDetails
            ? debugReferenceText(for: node)
            : friendlyReferenceText(for: node)
        infoView?.font = showsDebugDetails
            ? NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            : NSFont.systemFont(ofSize: 15, weight: .regular)
        renderEditor(for: node)
    }

    private func debugReferenceText(for node: ConfigNode) -> String {
        let schemaReference: String
        if node.allowedValues.isEmpty {
            schemaReference = node.kind == .section
                ? "This section groups related configuration fields."
                : "No enumerated value list in schema."
        } else {
            let lines = node.allowedValues.enumerated().map { index, value in
                let label = index < node.allowedValueTitles.count ? node.allowedValueTitles[index] : value
                return "\(value)  ->  \(label)"
            }
            schemaReference = lines.joined(separator: "\n")
        }
        let issueReference = issueReferenceText(for: node)
        let notes: String
        if node.kind == .section {
            notes = """
            \(node.summary)

            Children: \(node.children.count)

            This section can later drive both:
            - the editor tree in NotaryConfigurator
            - the grouped report view in NotaryGUI

            Import / export note:
            - only `de.twocent.notary` values are meant to vary per customer
            - operational payloads stay bundled and mostly invisible
            """
        } else {
            notes = """
            \(node.summary)

            Planned editor behavior:
            - schema default prefilled on a fresh configuration
            - imported mobileconfig values override the defaults
            - current GUI remains read-only until the export flow lands

            Planned import scope:
            - only the managed preferences payload for `de.twocent.notary`
            - fixed PPPC / login item payloads remain embedded automatically
            """
        }
        return """
        \(issueReference)

        Schema Reference
        \(schemaReference)

        Behavior Notes
        \(notes)
        """
    }

    private func friendlyReferenceText(for node: ConfigNode) -> String {
        guard node.kind == .field else {
            return """
            \(friendlySummary(for: node))

            Enthaltene Einstellungen: \(node.children.count)
            """
        }

        var lines: [String] = []

        let summary = friendlySummary(for: node)
        if !summary.isEmpty {
            lines.append(summary)
        }

        if !node.allowedValues.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("Werte:")
            for value in node.allowedValues {
                let label = displayTitle(for: value, in: node) ?? value
                lines.append("- \(label): \(valueExplanation(for: value, in: node))")
            }
        } else if lines.isEmpty {
            lines.append(friendlySummary(for: node))
        }

        if let compatibility = compatibilityText(for: node) {
            lines.append("")
            lines.append("Kompatibilität:")
            lines.append(compatibility)
        }

        lines.append("")
        lines.append(issueReferenceText(for: node))
        return lines.joined(separator: "\n")
    }

    private func friendlySummary(for node: ConfigNode) -> String {
        if let help = ConfigFieldHelp.lookup(node.keyPath) {
            return help.summary
        }

        if !node.summary.isEmpty, !node.summary.hasPrefix("Allowed values:") {
            return node.summary
        }

        if node.kind == .section {
            return "Diese Gruppe bündelt zusammengehörige Notary-Einstellungen."
        }

        return ""
    }

    private func allowedValuesText(for node: ConfigNode) -> String {
        guard !node.allowedValues.isEmpty else { return "Erlaubte Werte: –" }
        let labels = node.allowedValues.compactMap { displayTitle(for: $0, in: node) }
        return "Erlaubte Werte: \(labels.joined(separator: ", "))"
    }

    private func displayTitle(for value: String?, in node: ConfigNode) -> String? {
        guard let value, !value.isEmpty else { return nil }
        guard let index = node.allowedValues.firstIndex(of: value),
              index < node.allowedValueTitles.count else {
            return value
        }
        return node.allowedValueTitles[index]
    }

    private func valueExplanation(for value: String, in node: ConfigNode) -> String {
        switch value {
        case "hard-check":
            return "meldet Abweichungen als kritischen Befund."
        case "check":
            return "meldet Abweichungen informativ, ohne sie als kritisch zu werten."
        case "off":
            return "nimmt diese Einstellung nicht in die Bewertung auf."
        case "hard-enforce":
            return "versucht die Einstellung zu setzen und wertet verbleibende Abweichungen kritisch."
        case "enforce":
            return "versucht die Einstellung zu setzen und meldet verbleibende Abweichungen informativ."
        default:
            if node.type == "boolean" {
                return value == "true" ? "aktiviert diese Option." : "deaktiviert diese Option."
            }
            return "setzt den exportierten Wert auf `\(value)`."
        }
    }

    private func compatibilityText(for node: ConfigNode) -> String? {
        ConfigFieldHelp.lookup(node.keyPath)?.compatibility
    }

    private func issueReferenceText(for node: ConfigNode) -> String {
        guard node.kind == .field else {
            return "ⓘ Issues Export: konkreten Wert auswählen, um den Smart-Group-Wert zu sehen"
        }

        guard let reference = issueReferencesByKeyPath[node.keyPath] else {
            return "ⓘ Issues Export: kein direkter Notary-Issues-Wert"
        }

        return "ⓘ Issues Export: \(reference.issueValue)"
    }

    @objc private func toggleDebugDetails(_ sender: NSButton) {
        showsDebugDetails = sender.state == .on
        updateDetails(for: selectedNode, error: nil)
    }

    @objc private func enumEditorChanged(_ sender: NSPopUpButton) {
        guard let node = selectedNode else { return }
        let values = node.allowedValues
        let index = sender.indexOfSelectedItem
        guard index >= 0, index < values.count else { return }
        configState[node.keyPath] = values[index]
        currentValueField?.stringValue = "Current: \(values[index])"
    }

    @objc private func booleanEditorChanged(_ sender: NSButton) {
        guard let node = selectedNode else { return }
        let value = sender.state == .on ? "true" : "false"
        configState[node.keyPath] = value
        currentValueField?.stringValue = "Current: \(value)"
    }

    @objc private func textEditorChanged(_ sender: NSTextField) {
        let keyPath = sender.identifier?.rawValue ?? selectedNode?.keyPath
        commitTextValue(sender.stringValue, forKeyPath: keyPath)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let sender = obj.object as? NSTextField else { return }
        if sender === searchField {
            applyTreeFilter(selectFirst: false)
            return
        }
        let keyPath = sender.identifier?.rawValue ?? selectedNode?.keyPath
        commitTextValue(sender.stringValue, forKeyPath: keyPath)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let sender = obj.object as? NSTextField else { return }
        if sender === searchField { return }
        let keyPath = sender.identifier?.rawValue ?? selectedNode?.keyPath
        commitTextValue(sender.stringValue, forKeyPath: keyPath)
    }

    @objc private func filterTreeChanged(_ sender: NSSearchField) {
        applyTreeFilter(selectFirst: false)
    }

    private func ensureAppPresentation() {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = NotaryGUI.makeConfiguratorMenu(delegate: self)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    private func applyAppearanceColors() {
        guard let contentView = window?.contentView else { return }
        let windowColor = NotaryGUI.adaptiveCGColor(
            light: NSColor(calibratedWhite: 0.955, alpha: 1.0),
            dark: NSColor(calibratedWhite: 0.10, alpha: 1.0),
            for: contentView
        )
        let cardColor = NotaryGUI.adaptiveCGColor(
            light: .white,
            dark: NSColor(calibratedWhite: 0.16, alpha: 1.0),
            for: contentView
        )
        let embeddedColor = NotaryGUI.adaptiveCGColor(
            light: NSColor(calibratedWhite: 0.975, alpha: 1.0),
            dark: NSColor(calibratedWhite: 0.13, alpha: 1.0),
            for: contentView
        )
        let borderColor = NotaryGUI.adaptiveCGColor(
            light: NSColor.separatorColor.withAlphaComponent(0.55),
            dark: NSColor.white.withAlphaComponent(0.10),
            for: contentView
        )

        contentView.layer?.backgroundColor = windowColor
        NotaryGUI.applyPrimaryTextColor(in: contentView)
        [leftCardContainer, rightCardContainer].forEach { card in
            card?.layer?.backgroundColor = cardColor
            card?.layer?.borderColor = borderColor
            card?.layer?.borderWidth = 1.0
        }
        [editorSectionContainer, infoSectionContainer].forEach { section in
            section?.layer?.backgroundColor = embeddedColor
            section?.layer?.borderColor = borderColor
            section?.layer?.borderWidth = 1.0
        }

        [headerTitleField, titleField, typeField, defaultField].forEach { $0?.textColor = .labelColor }
        [headerSubtitleField, summaryField, keyField, currentValueField, importStatusField].forEach { $0?.textColor = .secondaryLabelColor }
        infoView?.textColor = .labelColor
        infoView?.needsDisplay = true
        outlineView?.reloadData()
        if let selectedNode {
            renderEditor(for: selectedNode)
            if let editorContainer {
                NotaryGUI.applyPrimaryTextColor(in: editorContainer)
            }
        }
    }

    private func layoutConfiguratorWindow() {
        guard
            let window,
            let contentView = window.contentView,
            let headerTitleField,
            let headerSubtitleField,
            let leftPane,
            let rightPane,
            let verticalDivider,
            let outlineScrollView,
            let searchField,
            let rightCardContainer,
            let titleField,
            let summaryField,
            let keyField,
            let typeField,
            let defaultField,
            let currentValueField,
            let editorSectionContainer,
            let infoSectionContainer,
            let importStatusField,
            let openButton,
            let exportButton
        else { return }

        let bounds = contentView.bounds
        let margin: CGFloat = 24
        let headerTop: CGFloat = 26
        let subtitleGap: CGFloat = 8
        let paneTop: CGFloat = 88
        let footerY: CGFloat = 20
        let footerHeight: CGFloat = 40
        let paneBottom = footerY + footerHeight + 18
        let paneHeight = max(420, bounds.height - paneTop - paneBottom)
        let leftWidth: CGFloat = 420
        let interPaneGap: CGFloat = 16
        let dividerX = margin + leftWidth + (interPaneGap / 2)
        let rightPaneX = margin + leftWidth + interPaneGap
        let rightPaneWidth = max(520, bounds.width - rightPaneX - margin)

        headerTitleField.frame = NSRect(x: margin, y: bounds.height - headerTop - 34, width: 420, height: 34)
        headerSubtitleField.frame = NSRect(x: margin, y: headerTitleField.frame.minY - subtitleGap - 20, width: 560, height: 20)

        leftPane.frame = NSRect(x: margin, y: paneBottom, width: leftWidth, height: paneHeight)
        verticalDivider.frame = NSRect(x: dividerX, y: paneBottom, width: 1, height: paneHeight)
        rightPane.frame = NSRect(x: rightPaneX, y: paneBottom, width: rightPaneWidth, height: paneHeight)

        if let leftCard = leftPane.subviews.first {
            leftCard.frame = leftPane.bounds
            if leftCard.subviews.count >= 2 {
                leftCard.subviews[0].frame = NSRect(x: 14, y: leftPane.bounds.height - 28, width: leftPane.bounds.width - 28, height: 18)
            }
        }
        searchField.frame = NSRect(x: 14, y: leftPane.bounds.height - 68, width: leftPane.bounds.width - 28, height: 28)
        outlineScrollView.frame = NSRect(x: 14, y: 14, width: leftPane.bounds.width - 28, height: leftPane.bounds.height - 92)
        outlineView?.frame = outlineScrollView.bounds
        outlineView?.tableColumns.first?.width = outlineScrollView.bounds.width

        rightCardContainer.frame = rightPane.bounds
        if let cardTitle = rightCardContainer.subviews.first {
            cardTitle.frame = NSRect(x: 14, y: rightPane.bounds.height - 28, width: rightPane.bounds.width - 28, height: 18)
        }

        titleField.frame = NSRect(x: 18, y: rightPane.bounds.height - 82, width: rightPane.bounds.width - 36, height: 40)
        summaryField.frame = .zero
        keyField.frame = NSRect(x: 18, y: rightPane.bounds.height - 116, width: rightPane.bounds.width - 36, height: 20)

        let metaWidth = (rightPane.bounds.width - 42) / 2
        typeField.frame = NSRect(x: 18, y: rightPane.bounds.height - 148, width: rightPane.bounds.width - 36, height: 22)
        defaultField.frame = NSRect(x: 18, y: rightPane.bounds.height - 180, width: metaWidth, height: 22)
        currentValueField.frame = .zero

        let editorHeight: CGFloat = 122
        let editorY = rightPane.bounds.height - 304
        editorSectionContainer.frame = NSRect(x: 18, y: editorY, width: rightPane.bounds.width - 36, height: editorHeight)

        let infoTopGap: CGFloat = 14
        let infoBottom: CGFloat = 18
        let infoY = infoBottom
        let infoHeight = max(120, editorY - infoY - infoTopGap)
        infoSectionContainer.frame = NSRect(x: 18, y: infoY, width: rightPane.bounds.width - 36, height: infoHeight)
        if infoSectionContainer.subviews.count >= 2 {
            let title = infoSectionContainer.subviews[0]
            let maybeScroll = infoSectionContainer.subviews[1]
            title.frame = NSRect(x: 12, y: infoHeight - 24, width: infoSectionContainer.bounds.width - 24, height: 16)
            maybeScroll.frame = NSRect(x: 12, y: 12, width: infoSectionContainer.bounds.width - 24, height: infoHeight - 50)
        }
        debugDetailsButton?.frame = NSRect(x: infoSectionContainer.bounds.width - 128, y: infoHeight - 28, width: 116, height: 22)

        let buttonWidth: CGFloat = 140
        let buttonHeight: CGFloat = 32
        let buttonGap: CGFloat = 16
        exportButton.frame = NSRect(x: bounds.width - margin - buttonWidth, y: footerY, width: buttonWidth, height: buttonHeight)
        openButton.frame = NSRect(x: exportButton.frame.minX - buttonGap - buttonWidth, y: footerY, width: buttonWidth, height: buttonHeight)

        let footnoteRight = openButton.frame.minX - 16
        importStatusField.frame = NSRect(
            x: margin,
            y: footerY,
            width: max(280, footnoteRight - margin),
            height: 40
        )
    }

    private func makeCard(frame: NSRect, title: String) -> (container: NSView, titleField: NSTextField) {
        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.cornerRadius = 12

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        titleField.frame = NSRect(x: 14, y: frame.height - 28, width: frame.width - 28, height: 18)
        titleField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(titleField)
        return (container, titleField)
    }

    private func makeEmbeddedTextSection(parentBounds: NSRect, y: CGFloat, height: CGFloat, title: String) -> (container: NSView, textView: NSTextView) {
        let container = NSView(frame: NSRect(x: 18, y: y, width: parentBounds.width - 36, height: height))
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.autoresizingMask = [.width, .minYMargin]

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleField.frame = NSRect(x: 12, y: height - 24, width: container.frame.width - 24, height: 16)
        titleField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(titleField)

        let scrollView = NSScrollView(frame: NSRect(x: 12, y: 12, width: container.frame.width - 24, height: height - 50))
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        scrollView.documentView = textView
        container.addSubview(scrollView)

        return (container, textView)
    }

    private func makeEmbeddedEditorSection(parentBounds: NSRect, y: CGFloat, height: CGFloat, title: String) -> (container: NSView, editorHost: NSView) {
        let container = NSView(frame: NSRect(x: 18, y: y, width: parentBounds.width - 36, height: height))
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.autoresizingMask = [.width, .minYMargin]

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleField.frame = NSRect(x: 12, y: height - 24, width: container.frame.width - 24, height: 16)
        titleField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(titleField)

        let editorHost = NSView(frame: NSRect(x: 12, y: 12, width: container.frame.width - 24, height: height - 40))
        editorHost.autoresizingMask = [.width, .height]
        container.addSubview(editorHost)

        return (container, editorHost)
    }

    private func renderEditor(for node: ConfigNode?) {
        guard let editorContainer else { return }
        editorContainer.subviews.forEach { $0.removeFromSuperview() }

        guard let node else {
            let label = NSTextField(wrappingLabelWithString: "Choose a configurable field to edit its current value.")
            label.textColor = .secondaryLabelColor
            label.frame = editorContainer.bounds
            label.autoresizingMask = [.width, .height]
            editorContainer.addSubview(label)
            return
        }

        guard node.kind == .field else {
            let label = NSTextField(wrappingLabelWithString: "Sections group related settings. Select a concrete field on the left to edit a value.")
            label.textColor = .secondaryLabelColor
            label.frame = editorContainer.bounds
            label.autoresizingMask = [.width, .height]
            editorContainer.addSubview(label)
            return
        }

        let currentValue = configState[node.keyPath] ?? node.defaultValue ?? ""
        let controlHeight: CGFloat = node.type == "boolean" ? 24 : 32
        let controlY = max(0, (editorContainer.bounds.height - controlHeight) / 2)

        if !node.allowedValues.isEmpty {
            let picker = NSPopUpButton(frame: NSRect(x: 0, y: controlY, width: editorContainer.bounds.width, height: controlHeight), pullsDown: false)
            for (index, value) in node.allowedValues.enumerated() {
                let title = index < node.allowedValueTitles.count ? node.allowedValueTitles[index] : value
                picker.addItem(withTitle: title)
            }
            if let selectedIndex = node.allowedValues.firstIndex(of: currentValue) {
                picker.selectItem(at: selectedIndex)
            } else if let selectedIndex = node.allowedValues.firstIndex(of: node.defaultValue ?? "") {
                picker.selectItem(at: selectedIndex)
            }
            picker.target = self
            picker.action = #selector(enumEditorChanged(_:))
            picker.autoresizingMask = [.width, .minYMargin]
            editorContainer.addSubview(picker)

            return
        }

        if node.type == "boolean" {
            let toggle = NSButton(checkboxWithTitle: "Enable this setting", target: self, action: #selector(booleanEditorChanged(_:)))
            toggle.state = currentValue == "true" ? .on : .off
            toggle.frame = NSRect(x: 0, y: controlY, width: editorContainer.bounds.width, height: controlHeight)
            toggle.autoresizingMask = [.width, .minYMargin]
            editorContainer.addSubview(toggle)

            return
        }

        let input = NSTextField(frame: NSRect(x: 0, y: controlY, width: editorContainer.bounds.width, height: controlHeight))
        input.stringValue = currentValue
        input.placeholderString = node.defaultValue ?? "Enter value"
        input.identifier = NSUserInterfaceItemIdentifier(node.keyPath)
        input.target = self
        input.action = #selector(textEditorChanged(_:))
        input.delegate = self
        input.autoresizingMask = [.width, .minYMargin]
        editorContainer.addSubview(input)

    }

    private func seedDefaults(from nodes: [ConfigNode]) {
        for node in nodes {
            if node.kind == .field, let defaultValue = node.defaultValue {
                configState[node.keyPath] = defaultValue
            }
            if !node.children.isEmpty {
                seedDefaults(from: node.children)
            }
        }
    }

    private func applyTreeFilter(selectFirst: Bool) {
        let query = searchField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        visibleNodes = filtered(nodes: nodes, matching: query)
        outlineView?.reloadData()
        outlineView?.expandItem(nil, expandChildren: true)

        if let selectedNode,
           let visibleSelectedNode = findNode(withKeyPath: selectedNode.keyPath, in: visibleNodes),
           let row = outlineView?.row(forItem: visibleSelectedNode), row >= 0 {
            self.selectedNode = visibleSelectedNode
            outlineView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            return
        }

        if selectFirst || !query.isEmpty {
            guard let first = firstSelectableNode(in: visibleNodes) else {
                selectedNode = nil
                updateDetails(for: nil, error: nil)
                return
            }
            select(node: first)
            if let row = outlineView?.row(forItem: first), row >= 0 {
                outlineView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }
    }

    private func filtered(nodes: [ConfigNode], matching query: String) -> [ConfigNode] {
        guard !query.isEmpty else { return nodes }
        let terms = query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        return nodes.compactMap { filtered(node: $0, matching: terms) }
    }

    private func filtered(node: ConfigNode, matching terms: [String]) -> ConfigNode? {
        let filteredChildren = node.children.compactMap { filtered(node: $0, matching: terms) }
        if node.matchesSearchTerms(terms) || !filteredChildren.isEmpty {
            return ConfigNode(
                keyPath: node.keyPath,
                title: node.title,
                summary: node.summary,
                kind: node.kind,
                type: node.type,
                defaultValue: node.defaultValue,
                allowedValues: node.allowedValues,
                allowedValueTitles: node.allowedValueTitles,
                children: filteredChildren
            )
        }
        return nil
    }

    private func findNode(withKeyPath keyPath: String, in nodes: [ConfigNode]) -> ConfigNode? {
        for node in nodes {
            if node.keyPath == keyPath {
                return node
            }
            if let child = findNode(withKeyPath: keyPath, in: node.children) {
                return child
            }
        }
        return nil
    }

    private func firstSelectableNode(in nodes: [ConfigNode]) -> ConfigNode? {
        for node in nodes {
            if node.kind == .field { return node }
            if let child = firstSelectableNode(in: node.children) {
                return child
            }
            if node.children.isEmpty { return node }
        }
        return nil
    }

    private func commitTextValue(_ value: String, forKeyPath keyPath: String?) {
        guard let keyPath else { return }
        configState[keyPath] = value
        if selectedNode?.keyPath == keyPath {
            currentValueField?.stringValue = "Current: \(value)"
        }
    }
}
