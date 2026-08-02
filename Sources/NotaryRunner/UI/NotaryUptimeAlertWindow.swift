import Foundation
import AppKit
import NotaryCore

@MainActor
final class NotaryUptimeAlertWindowDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let logger: HardenLogger
    private let payload: UptimeAlertPayload
    private var window: NSWindow?

    init(logger: HardenLogger, payload: UptimeAlertPayload) {
        self.logger = logger
        self.payload = payload
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = NotaryGUI.appName
        window.center()
        window.delegate = self
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 400)

        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        let iconView = NSImageView(frame: NSRect(x: 28, y: 296, width: 64, height: 64))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = payload.severity == .required ? .systemRed : .systemOrange
        iconView.image = NSImage(systemSymbolName: payload.severity == .required ? "exclamationmark.triangle.fill" : "arrow.clockwise.circle.fill", accessibilityDescription: "Uptime alert")
        contentView.addSubview(iconView)

        let titleField = NSTextField(labelWithString: payload.title)
        titleField.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        titleField.frame = NSRect(x: 108, y: 316, width: 480, height: 34)
        contentView.addSubview(titleField)

        let subtitleField = NSTextField(labelWithString: "Notary recommends attention for extended system uptime.")
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.frame = NSRect(x: 108, y: 290, width: 480, height: 20)
        contentView.addSubview(subtitleField)

        let messageView = NSScrollView(frame: NSRect(x: 28, y: 108, width: 564, height: 156))
        messageView.borderType = .noBorder
        messageView.drawsBackground = false
        messageView.hasVerticalScroller = true
        messageView.autohidesScrollers = true

        let messageText = NSTextView(frame: messageView.bounds)
        messageText.isEditable = false
        messageText.isSelectable = true
        messageText.drawsBackground = false
        messageText.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        messageText.string = payload.message
        messageView.documentView = messageText
        contentView.addSubview(messageView)

        let adviceField = NSTextField(labelWithString: payload.severity == .required ? "Please restart the Mac as soon as possible." : "Please save your work and restart when convenient.")
        adviceField.textColor = .secondaryLabelColor
        adviceField.frame = NSRect(x: 28, y: 74, width: 420, height: 20)
        contentView.addSubview(adviceField)

        let restartButton = NSButton(frame: NSRect(x: 360, y: 28, width: 120, height: 32))
        restartButton.title = "Restart Now"
        restartButton.bezelStyle = .rounded
        restartButton.target = self
        restartButton.action = #selector(restartNow)
        contentView.addSubview(restartButton)

        let laterButton = NSButton(frame: NSRect(x: 492, y: 28, width: 100, height: 32))
        laterButton.title = "Later"
        laterButton.bezelStyle = .rounded
        laterButton.target = self
        laterButton.action = #selector(closeWindow)
        contentView.addSubview(laterButton)

        self.window = window
        window.makeKeyAndOrderFront(nil)
        ensureAppPresentation()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        NotaryGUI.releaseRetainedUptimeAlertDelegate()
        NSApp.terminate(nil)
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

    @objc private func restartNow() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"System Events\" to restart"]
        do {
            try process.run()
        } catch {
            logger.warn("[UptimeAlert] Failed to request restart via osascript: \(error)")
        }
        closeWindow()
    }

    private func ensureAppPresentation() {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = NotaryGUI.makePlaceholderMenu(delegate: self)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
}
