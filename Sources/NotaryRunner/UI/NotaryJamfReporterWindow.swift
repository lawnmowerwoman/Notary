import AppKit
import Foundation
import NotaryCore

@MainActor
final class NotaryJamfReporterWindowDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let logger: HardenLogger
    private let terminatesApplicationOnClose: Bool
    var onClose: (() -> Void)?
    private var window: NSWindow?

    init(logger: HardenLogger, terminatesApplicationOnClose: Bool = true, onClose: (() -> Void)? = nil) {
        self.logger = logger
        self.terminatesApplicationOnClose = terminatesApplicationOnClose
        self.onClose = onClose
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = buildWindow(frame: NSRect(x: 0, y: 0, width: 760, height: 360))
        window.makeKeyAndOrderFront(nil)
        ensureAppPresentation()
    }

    func buildWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notary Reporter"
        window.center()
        window.delegate = self

        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        let title = NSTextField(labelWithString: "Reporter Unavailable")
        title.font = NSFont.systemFont(ofSize: 26, weight: .bold)
        title.frame = NSRect(x: 48, y: 238, width: 660, height: 34)
        contentView.addSubview(title)

        let message = NSTextField(wrappingLabelWithString: """
        This public Notary build does not include the confidential Transporter.

        Local compliance checks, local reports and the menu bar remain available.
        """)
        message.font = NSFont.systemFont(ofSize: 15)
        message.textColor = .secondaryLabelColor
        message.frame = NSRect(x: 48, y: 132, width: 660, height: 88)
        contentView.addSubview(message)

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        closeButton.bezelStyle = .rounded
        closeButton.frame = NSRect(x: frame.width - 168, y: 36, width: 120, height: 32)
        closeButton.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(closeButton)

        self.window = window
        logger.warn("[NotaryReporter] Confidential Transporter is not available in this public build.")
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

    @objc func reloadDevices() {
        logger.warn("[NotaryReporter] Reload ignored because the confidential Transporter is unavailable.")
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

    private func ensureAppPresentation() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.mainMenu = NotaryGUI.makeJamfReporterMenu(delegate: self)
    }
}
