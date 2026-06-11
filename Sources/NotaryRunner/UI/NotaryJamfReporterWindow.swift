import AppKit
import Foundation
import NotaryCore

@MainActor
final class NotaryJamfReporterWindowDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let logger: HardenLogger
    private let terminatesApplicationOnClose: Bool
    var onClose: (() -> Void)?
    private var window: NSWindow?
    private var contentView: NSView?
    private var headerTitleField: NSTextField?
    private var betaBadgeField: BetaBadgeView?
    private var headerSubtitleField: NSTextField?
    private var leftPane: NSView?
    private var rightPane: NSView?
    private var verticalDivider: NSBox?
    private var searchField: NSSearchField?
    private var tableView: NSTableView?
    private var statusField: NSTextField?
    private var refreshButton: NSButton?
    private var detailTitleField: NSTextField?
    private var detailSubtitleField: NSTextField?
    private var transportCard: NSView?
    private var proofCard: NSView?
    private var issuesCard: NSView?
    private var transportView: NSTextView?
    private var proofView: NSTextView?
    private var issuesView: NSTextView?

    private var api: JamfAPI?
    private var auth: JamfAuth?
    private var runnerState: RunnerState?
    private var allComputers: [JamfReportComputer] = []
    private var visibleComputers: [JamfReportComputer] = []
    private var selectedComputerID: Int?
    private let issueSectionByValue = CheckIssueCatalog.sectionByIssueValue()

    init(logger: HardenLogger, terminatesApplicationOnClose: Bool = true, onClose: (() -> Void)? = nil) {
        self.logger = logger
        self.terminatesApplicationOnClose = terminatesApplicationOnClose
        self.onClose = onClose
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = buildWindow(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        window.makeKeyAndOrderFront(nil)
        ensureAppPresentation()
        reloadDevices()
    }

    func buildWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notary Reporter"
        window.minSize = NSSize(width: 1180, height: 760)
        window.center()
        window.delegate = self

        let contentView = AppearanceObservingView(frame: window.contentView?.bounds ?? .zero)
        contentView.appearanceDidChange = { [weak self] in
            self?.applyAppearanceColors()
        }
        contentView.wantsLayer = true
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView
        self.contentView = contentView

        let title = NSTextField(labelWithString: "Notary Reporter")
        title.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        contentView.addSubview(title)
        headerTitleField = title

        let betaBadge = BetaBadgeView(frame: .zero)
        contentView.addSubview(betaBadge)
        betaBadgeField = betaBadge

        let subtitle = NSTextField(labelWithString: "Jamf device reports and Notary findings")
        subtitle.textColor = .secondaryLabelColor
        contentView.addSubview(subtitle)
        headerSubtitleField = subtitle

        let refreshButton = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload") ?? NSImage(), target: self, action: #selector(reloadDevices))
        refreshButton.bezelStyle = .texturedRounded
        refreshButton.imagePosition = .imageOnly
        refreshButton.toolTip = "Reload devices from Jamf"
        contentView.addSubview(refreshButton)
        self.refreshButton = refreshButton

        let leftPane = NSView(frame: .zero)
        contentView.addSubview(leftPane)
        self.leftPane = leftPane

        let divider = NSBox(frame: .zero)
        divider.boxType = .separator
        contentView.addSubview(divider)
        verticalDivider = divider

        let rightPane = NSView(frame: .zero)
        contentView.addSubview(rightPane)
        self.rightPane = rightPane

        let searchField = NSSearchField(frame: .zero)
        searchField.placeholderString = "Filter devices"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(filterChanged(_:))
        leftPane.addSubview(searchField)
        self.searchField = searchField

        let tableScroll = NSScrollView(frame: .zero)
        tableScroll.identifier = NSUserInterfaceItemIdentifier("deviceTableScroll")
        tableScroll.hasVerticalScroller = true
        tableScroll.autohidesScrollers = true
        tableScroll.borderType = .noBorder
        tableScroll.drawsBackground = false
        leftPane.addSubview(tableScroll)

        let table = NSTableView(frame: .zero)
        table.usesAlternatingRowBackgroundColors = false
        table.rowSizeStyle = .medium
        table.style = .sourceList
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        addColumn("compliance", title: "Compliance", width: 34, to: table)
        addColumn("name", title: "Name", width: 170, to: table)
        addColumn("model", title: "Model", width: 150, to: table)
        addColumn("serial", title: "Serial", width: 120, to: table)
        addColumn("user", title: "User", width: 120, to: table)
        tableScroll.documentView = table
        tableView = table

        let statusField = NSTextField(labelWithString: "Ready")
        statusField.textColor = .secondaryLabelColor
        contentView.addSubview(statusField)
        self.statusField = statusField

        let detailTitle = NSTextField(labelWithString: "Select a device")
        detailTitle.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        rightPane.addSubview(detailTitle)
        detailTitleField = detailTitle

        let detailSubtitle = NSTextField(labelWithString: "Device proof and findings will appear here.")
        detailSubtitle.textColor = .secondaryLabelColor
        rightPane.addSubview(detailSubtitle)
        detailSubtitleField = detailSubtitle

        let transport = makeTextBlock(title: "Last Transport")
        let proof = makeTextBlock(title: "Proof")
        let issues = makeTextBlock(title: "Issues")
        [transport.container, proof.container, issues.container].forEach { rightPane.addSubview($0) }
        transportCard = transport.container
        proofCard = proof.container
        issuesCard = issues.container
        transportView = transport.textView
        proofView = proof.textView
        issuesView = issues.textView

        self.window = window
        applyAppearanceColors()
        layoutWindow()
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
        layoutWindow()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleComputers.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < visibleComputers.count else { return nil }
        let computer = visibleComputers[row]
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("name")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = identifier

        let textField = cell.textField ?? NSTextField(labelWithString: "")
        textField.frame = NSRect(x: 4, y: 2, width: (tableColumn?.width ?? 120) - 8, height: 18)
        textField.font = NSFont.systemFont(ofSize: 12.5, weight: identifier.rawValue == "name" ? .semibold : .regular)
        textField.lineBreakMode = .byTruncatingTail
        textField.textColor = identifier.rawValue == "name" ? .labelColor : .secondaryLabelColor
        textField.alignment = identifier.rawValue == "compliance" ? .center : .left
        textField.stringValue = value(for: computer, column: identifier.rawValue)
        textField.toolTip = textField.stringValue
        if cell.textField == nil {
            cell.addSubview(textField)
            cell.textField = textField
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView, tableView.selectedRow >= 0, tableView.selectedRow < visibleComputers.count else {
            selectedComputerID = nil
            renderEmptyDetail()
            return
        }
        let computer = visibleComputers[tableView.selectedRow]
        selectedComputerID = computer.id
        loadDetail(for: computer)
    }

    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSSearchField === searchField {
            applyFilter()
        }
    }

    @objc func reloadDevices() {
        refreshButton?.isEnabled = false
        statusField?.stringValue = "Loading devices from Jamf..."
        Task { [weak self] in
            await self?.loadDevices()
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

    @objc private func filterChanged(_ sender: NSSearchField) {
        applyFilter()
    }

    private func loadDevices() async {
        do {
            let api = try makeAPI()
            let devices = try await api.listNotaryReportComputers()
            allComputers = devices.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            applyFilter(selectFirst: true)
            statusField?.stringValue = "\(devices.count) devices loaded"
        } catch {
            allComputers = []
            visibleComputers = []
            tableView?.reloadData()
            renderError(error)
            statusField?.stringValue = "Jamf reporter unavailable"
        }
        refreshButton?.isEnabled = true
    }

    private func loadDetail(for computer: JamfReportComputer) {
        detailTitleField?.stringValue = computer.name
        detailSubtitleField?.stringValue = "\(computer.model) · \(computer.serialNumber) · \(computer.username)"
        transportView?.string = "Loading..."
        proofView?.string = "Loading..."
        issuesView?.string = "Loading..."

        Task { [weak self] in
            guard let self else { return }
            do {
                let api = try makeAPI()
                guard let detail = await api.getNotaryReportComputerDetail(computerID: computer.id) else {
                    throw ReporterError.detailUnavailable
                }
                guard self.selectedComputerID == computer.id else { return }
                self.render(detail: detail)
            } catch {
                guard self.selectedComputerID == computer.id else { return }
                self.renderError(error)
            }
        }
    }

    private func makeAPI() throws -> JamfAPI {
        if let api {
            return api
        }

        let store = SecurePlistStore<RunnerState>(logger: logger)
        guard let state = try loadRunnerState(store: store) else {
            throw ReporterError.missingState
        }
        let clientID = state.jamfClientID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clientSecret = state.jamfClientSecret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw ReporterError.missingCredentials
        }
        guard let jamfProURL = JamfLocalConfig.jamfProURL() else {
            throw ReporterError.missingJamfURL
        }

        let http = HTTPClient(logger: logger)
        let creds: JamfCredentialsProvider = { (clientID: clientID, clientSecret: clientSecret) }
        let auth = JamfAuth(
            logger: logger,
            http: http,
            baseURL: jamfProURL,
            credentials: creds,
            initialBearerToken: state.jamfBearerToken,
            initialBearerExpirationEpoch: state.jamfBearerExpirationEpoch
        )
        let api = JamfAPI(logger: logger, http: http, baseURL: jamfProURL, auth: auth)
        self.runnerState = state
        self.auth = auth
        self.api = api
        return api
    }

    private func loadRunnerState(store: SecurePlistStore<RunnerState>) throws -> RunnerState? {
        if let state = try store.load() {
            return state
        }

        return try loadPrivilegedRunnerState()
    }

    private func loadPrivilegedRunnerState() throws -> RunnerState? {
        let script = #"do shell script "/usr/bin/plutil -convert xml1 -o - /var/db/notary.plist" with administrator privileges"#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ReporterError.privilegedStateReadFailed(error.localizedDescription)
        }

        let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw ReporterError.privilegedStateReadFailed(errorText.isEmpty ? "Administrator authorization failed." : errorText)
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else {
            throw ReporterError.privilegedStateReadFailed("No Notary state data was returned.")
        }

        do {
            return try PropertyListDecoder().decode(RunnerState.self, from: data)
        } catch {
            throw ReporterError.privilegedStateReadFailed(error.localizedDescription)
        }
    }

    private func applyFilter(selectFirst: Bool = false) {
        let query = searchField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if query.isEmpty {
            visibleComputers = allComputers
        } else {
            visibleComputers = allComputers.filter { computer in
                [computer.name, computer.model, computer.serialNumber, computer.username]
                    .contains { $0.lowercased().contains(query) }
            }
        }

        tableView?.reloadData()
        guard !visibleComputers.isEmpty else {
            selectedComputerID = nil
            renderEmptyDetail()
            statusField?.stringValue = allComputers.isEmpty ? "No devices loaded" : "No matching devices"
            return
        }

        if selectFirst || selectedComputerID == nil || !visibleComputers.contains(where: { $0.id == selectedComputerID }) {
            tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func render(detail: JamfReportComputerDetail) {
        detailTitleField?.stringValue = detail.computer.name
        detailSubtitleField?.stringValue = "\(detail.computer.model) · \(detail.computer.serialNumber) · \(detail.computer.username)"
        transportView?.string = """
        \(detail.lastTransportValue)

        Runner:
        \(detail.runnerStatus)
        """
        proofView?.string = formatProof(detail)
        issuesView?.string = formatIssuesForDisplay(detail.issuesValue)
    }

    private func renderEmptyDetail() {
        detailTitleField?.stringValue = "Select a device"
        detailSubtitleField?.stringValue = "Device proof and findings will appear here."
        transportView?.string = "n/a"
        proofView?.string = "n/a"
        issuesView?.string = ""
    }

    private func renderError(_ error: Error) {
        detailTitleField?.stringValue = "Reporter unavailable"
        detailSubtitleField?.stringValue = "Could not read Jamf report data."
        transportView?.string = "n/a"
        proofView?.string = "\(error.localizedDescription)"
        issuesView?.string = ""
        logger.error("[NotaryReporter] \(error)")
    }

    private func formatProof(_ detail: JamfReportComputerDetail) -> String {
        var lines = [detail.complianceValue]
        if let percent = detail.percentValue, !percent.isEmpty {
            lines.append("")
            let suffix = percent.hasSuffix("%") ? "" : "%"
            lines.append("Compliance percentage: \(percent)\(suffix)")
        }
        return lines.joined(separator: "\n")
    }

    private func formatIssuesForDisplay(_ issues: String) -> String {
        if issues == "EMPTY" {
            return "No current findings."
        }

        let entries = issues
            .components(separatedBy: " • ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "n/a" }

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

    private func addColumn(_ id: String, title: String, width: CGFloat, to table: NSTableView) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
    }

    private func value(for computer: JamfReportComputer, column: String) -> String {
        switch column {
        case "compliance": return computer.complianceIndicator
        case "model": return computer.model
        case "serial": return computer.serialNumber
        case "user": return computer.username
        default: return computer.name
        }
    }

    private func makeTextBlock(title: String) -> (container: NSView, textView: NSTextView) {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.cornerRadius = 12

        let titleField = NSTextField(labelWithString: title)
        titleField.identifier = NSUserInterfaceItemIdentifier("sectionTitle")
        titleField.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        container.addSubview(titleField)

        let scrollView = NSScrollView(frame: .zero)
        scrollView.identifier = NSUserInterfaceItemIdentifier("sectionScroll")
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        container.addSubview(scrollView)

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 13.5, weight: .regular)
        textView.textContainerInset = NSSize(width: 0, height: 4)
        scrollView.documentView = textView

        return (container, textView)
    }

    private func applyAppearanceColors() {
        guard let contentView else { return }
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
        let borderColor = NotaryGUI.adaptiveCGColor(
            light: NSColor.separatorColor.withAlphaComponent(0.55),
            dark: NSColor.white.withAlphaComponent(0.10),
            for: contentView
        )

        contentView.layer?.backgroundColor = windowColor
        NotaryGUI.applyPrimaryTextColor(in: contentView)
        [transportCard, proofCard, issuesCard].forEach { card in
            card?.layer?.backgroundColor = cardColor
            card?.layer?.borderColor = borderColor
            card?.layer?.borderWidth = 1.0
        }
        [headerSubtitleField, detailSubtitleField, statusField].forEach { $0?.textColor = .secondaryLabelColor }
        betaBadgeField?.needsDisplay = true
        [transportView, proofView, issuesView].forEach {
            $0?.textColor = .labelColor
            $0?.insertionPointColor = .labelColor
            $0?.needsDisplay = true
        }
        tableView?.reloadData()
    }

    private func layoutWindow() {
        guard let contentView, let leftPane, let rightPane else { return }
        let bounds = contentView.bounds
        let margin: CGFloat = 24
        let headerHeight: CGFloat = 72
        let footerHeight: CGFloat = 28
        let paneTop = bounds.height - margin - headerHeight
        let paneBottom = margin + footerHeight
        let paneHeight = max(500, paneTop - paneBottom)
        let leftWidth: CGFloat = min(680, max(560, bounds.width * 0.43))
        let gap: CGFloat = 18
        let rightX = margin + leftWidth + gap
        let rightWidth = max(560, bounds.width - rightX - margin)

        headerTitleField?.frame = NSRect(x: margin, y: bounds.height - margin - 34, width: 360, height: 34)
        betaBadgeField?.frame = NSRect(x: margin + 232, y: bounds.height - margin - 35, width: 52, height: 24)
        headerSubtitleField?.frame = NSRect(x: margin, y: bounds.height - margin - 62, width: 620, height: 20)
        refreshButton?.frame = NSRect(x: bounds.width - margin - 34, y: bounds.height - margin - 36, width: 34, height: 30)

        leftPane.frame = NSRect(x: margin, y: paneBottom, width: leftWidth, height: paneHeight)
        verticalDivider?.frame = NSRect(x: margin + leftWidth + (gap / 2), y: paneBottom, width: 1, height: paneHeight)
        rightPane.frame = NSRect(x: rightX, y: paneBottom, width: rightWidth, height: paneHeight)
        statusField?.frame = NSRect(x: margin, y: margin, width: bounds.width - (margin * 2), height: 20)

        searchField?.frame = NSRect(x: 0, y: leftPane.bounds.height - 32, width: leftPane.bounds.width, height: 28)
        if let tableScroll = leftPane.subviews.compactMap({ $0 as? NSScrollView }).first {
            tableScroll.frame = NSRect(x: 0, y: 0, width: leftPane.bounds.width, height: leftPane.bounds.height - 42)
            tableView?.frame = tableScroll.bounds
            let total = max(1, tableScroll.bounds.width)
            let complianceWidth: CGFloat = 20
            let remaining = max(1, total - complianceWidth)
            tableView?.tableColumns.first(where: { $0.identifier.rawValue == "compliance" })?.width = complianceWidth
            tableView?.tableColumns.first(where: { $0.identifier.rawValue == "name" })?.width = max(180, remaining * 0.34)
            tableView?.tableColumns.first(where: { $0.identifier.rawValue == "model" })?.width = max(150, remaining * 0.28)
            tableView?.tableColumns.first(where: { $0.identifier.rawValue == "serial" })?.width = max(96, remaining * 0.16)
            tableView?.tableColumns.first(where: { $0.identifier.rawValue == "user" })?.width = max(116, remaining * 0.20)
        }

        detailTitleField?.frame = NSRect(x: 0, y: rightPane.bounds.height - 34, width: rightPane.bounds.width, height: 30)
        detailSubtitleField?.frame = NSRect(x: 0, y: rightPane.bounds.height - 60, width: rightPane.bounds.width, height: 20)

        let blockGap: CGFloat = 14
        let topY = rightPane.bounds.height - 86
        let transportHeight: CGFloat = 122
        let proofHeight: CGFloat = 105
        let issuesY: CGFloat = 0
        let issuesHeight = max(260, topY - transportHeight - proofHeight - (blockGap * 2))
        transportCard?.frame = NSRect(x: 0, y: topY - transportHeight, width: rightPane.bounds.width, height: transportHeight)
        proofCard?.frame = NSRect(x: 0, y: topY - transportHeight - blockGap - proofHeight, width: rightPane.bounds.width, height: proofHeight)
        issuesCard?.frame = NSRect(x: 0, y: issuesY, width: rightPane.bounds.width, height: issuesHeight)
        [transportCard, proofCard, issuesCard].forEach(layoutTextBlock)
    }

    private func layoutTextBlock(_ container: NSView?) {
        guard let container else { return }
        let title = container.subviews.compactMap { $0 as? NSTextField }.first
        let scroll = container.subviews.compactMap { $0 as? NSScrollView }.first
        title?.frame = NSRect(x: 16, y: container.bounds.height - 30, width: container.bounds.width - 32, height: 20)
        scroll?.frame = NSRect(x: 16, y: 12, width: container.bounds.width - 32, height: container.bounds.height - 46)
    }

    private func ensureAppPresentation() {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = NotaryGUI.makeJamfReporterMenu(delegate: self)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
}

private final class BetaBadgeView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let blue = NSColor.systemBlue
        let badgeRect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let path = NSBezierPath(roundedRect: badgeRect, xRadius: 6, yRadius: 6)
        blue.withAlphaComponent(0.10).setFill()
        blue.setStroke()
        path.lineWidth = 1.5
        path.fill()
        path.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: blue
        ]
        let label = NSString(string: "BETA")
        let labelSize = label.size(withAttributes: attributes)
        let labelRect = NSRect(
            x: (bounds.width - labelSize.width) / 2,
            y: (bounds.height - labelSize.height) / 2,
            width: labelSize.width,
            height: labelSize.height
        )
        label.draw(in: labelRect, withAttributes: attributes)
    }
}

private enum ReporterError: LocalizedError {
    case missingState
    case missingCredentials
    case missingJamfURL
    case detailUnavailable
    case privilegedStateReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingState:
            return "No Notary runner state is available for Jamf API access."
        case .missingCredentials:
            return "Jamf API credentials are missing from Notary state."
        case .missingJamfURL:
            return "Jamf Pro URL is not available on this Mac."
        case .detailUnavailable:
            return "Jamf did not return report details for the selected device."
        case .privilegedStateReadFailed(let message):
            return "Could not read the protected Notary state. \(message)"
        }
    }
}
