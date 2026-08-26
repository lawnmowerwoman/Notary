import AppKit
import Foundation
import NotaryCore

package enum NotaryReporterAvailability: Equatable {
    case buildUnavailable
    case unauthorized
    case available

    var title: String {
        switch self {
        case .buildUnavailable:
            return "Reporter Unavailable"
        case .unauthorized:
            return "Reporter Authorization Required"
        case .available:
            return "Notary Reporter"
        }
    }

    var message: String {
        switch self {
        case .buildUnavailable:
            return """
            This Notary build does not include the Reporter module.

            Local compliance checks, local reports and the menu bar remain available.
            """
        case .unauthorized:
            return """
            This App Token does not include the Reporter capability.

            Ask your administrator for a Notary App Token with Reporter access.
            """
        case .available:
            return """
            Reporter is authorized, but no Reporter implementation is registered in this build.
            """
        }
    }

    var logMessage: String {
        switch self {
        case .buildUnavailable:
            return "[NotaryReporter] Reporter module is not available in this build."
        case .unauthorized:
            return "[NotaryReporter] Reporter capability is missing from the App Token."
        case .available:
            return "[NotaryReporter] Reporter capability is valid, but no implementation is registered."
        }
    }
}

@MainActor
package final class NotaryJamfReporterWindowDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let logger: HardenLogger
    private let availability: NotaryReporterAvailability
    private let terminatesApplicationOnClose: Bool
    package var onClose: (() -> Void)?
    private var window: NSWindow?

    package init(
        logger: HardenLogger,
        availability: NotaryReporterAvailability = .buildUnavailable,
        terminatesApplicationOnClose: Bool = true,
        onClose: (() -> Void)? = nil
    ) {
        self.logger = logger
        self.availability = availability
        self.terminatesApplicationOnClose = terminatesApplicationOnClose
        self.onClose = onClose
    }

    package func applicationDidFinishLaunching(_ notification: Notification) {
        openOrFocusWindow()
    }

    package func openOrFocusWindow() {
        let targetWindow: NSWindow
        if let window {
            targetWindow = window
        } else {
            targetWindow = buildWindow(frame: NSRect(x: 0, y: 0, width: 760, height: 360))
        }
        targetWindow.makeKeyAndOrderFront(nil)
        ensureAppPresentation()
    }

    package func buildWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notary Reporter"
        window.center()
        window.delegate = self
        window.isRestorable = false

        let contentView = NSView(frame: window.contentView?.bounds ?? .zero)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        let title = NSTextField(labelWithString: availability.title)
        title.font = NSFont.systemFont(ofSize: 26, weight: .bold)
        title.frame = NSRect(x: 48, y: 238, width: 660, height: 34)
        contentView.addSubview(title)

        let message = NSTextField(wrappingLabelWithString: availability.message)
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
        logger.warn(availability.logMessage)
        return window
    }

    package func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        terminatesApplicationOnClose
    }

    package func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    package func windowWillClose(_ notification: Notification) {
        onClose?()
        if terminatesApplicationOnClose {
            NSApp.terminate(nil)
        }
    }

    package func windowDidBecomeKey(_ notification: Notification) {
        ensureAppPresentation()
    }

    @objc package func reloadDevices() {
        logger.warn("[NotaryReporter] Reload ignored. \(availability.logMessage)")
    }

    @objc package func showAboutPanel() {
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Notary",
            .applicationVersion: NotaryVersion.marketingVersion,
            .version: NotaryVersion.label,
            .credits: NSAttributedString(string: "Released under Apache-2.0 License. All rights reserved.")
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
        ensureAppPresentation()
    }

    @objc package func closeWindow() {
        window?.close()
    }

    package func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem(title: "Notary", action: nil, keyEquivalent: "")
        mainMenu.addItem(appItem)

        let appMenu = NSMenu(title: "Notary")
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Notary", action: #selector(showAboutPanel), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Reload Devices", action: #selector(reloadDevices), keyEquivalent: "r").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Close", action: #selector(closeWindow), keyEquivalent: "w").target = self
        appMenu.addItem(withTitle: "Quit Notary", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Reload Devices", action: #selector(reloadDevices), keyEquivalent: "").target = self
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    private func ensureAppPresentation() {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = makeMainMenu()
        NSApp.activate(ignoringOtherApps: true)
    }
}
