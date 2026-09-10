import AppKit
import NotaryCore

@MainActor
package enum NotaryAboutPanel {
    private static var retainedController: NotaryAboutWindowController?

    package static func show(applicationName: String) {
        if let retainedController {
            retainedController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NotaryAboutWindowController(
            applicationName: applicationName,
            marketingVersion: NotaryVersion.marketingVersion,
            buildVersion: NotaryVersion.label,
            activationCode: NotaryActivationCode.currentDisplayValue()
        )
        retainedController = controller
        controller.onClose = {
            retainedController = nil
        }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class NotaryAboutWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let activationCode: String?
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let copyFeedback = NSTextField(labelWithString: "")

    init(
        applicationName: String,
        marketingVersion: String,
        buildVersion: String,
        activationCode: String?
    ) {
        self.activationCode = activationCode?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About \(applicationName)"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView(
            applicationName: applicationName,
            marketingVersion: marketingVersion,
            buildVersion: buildVersion
        )
    }

    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func makeContentView(
        applicationName: String,
        marketingVersion: String,
        buildVersion: String
    ) -> NSView {
        let root = NSView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14
        stack.addArrangedSubview(header)

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        header.addArrangedSubview(icon)

        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3
        header.addArrangedSubview(titleStack)

        let title = NSTextField(labelWithString: applicationName)
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        titleStack.addArrangedSubview(title)

        let version = NSTextField(labelWithString: "Version \(marketingVersion) (\(buildVersion))")
        version.textColor = .secondaryLabelColor
        titleStack.addArrangedSubview(version)

        stack.addArrangedSubview(separator())

        let licenseTitle = NSTextField(labelWithString: "License")
        licenseTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(licenseTitle)

        let licenseStack = NSStackView()
        licenseStack.orientation = .vertical
        licenseStack.alignment = .leading
        licenseStack.spacing = 7
        stack.addArrangedSubview(licenseStack)

        let activationLabel = NSTextField(labelWithString: "Activation Code")
        activationLabel.font = .systemFont(ofSize: 12, weight: .medium)
        activationLabel.textColor = .secondaryLabelColor
        licenseStack.addArrangedSubview(activationLabel)

        let code = NSTextField(labelWithString: activationCode ?? "Not configured")
        code.font = activationCode == nil ? .systemFont(ofSize: 13) : .monospacedSystemFont(ofSize: 13, weight: .regular)
        code.textColor = activationCode == nil ? .secondaryLabelColor : .labelColor
        code.lineBreakMode = .byTruncatingMiddle
        code.maximumNumberOfLines = 1
        licenseStack.addArrangedSubview(code)

        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8
        licenseStack.addArrangedSubview(actionRow)

        copyButton.target = self
        copyButton.action = #selector(copyActivationCode)
        copyButton.isEnabled = activationCode != nil
        copyButton.bezelStyle = .rounded
        actionRow.addArrangedSubview(copyButton)

        copyFeedback.textColor = .secondaryLabelColor
        copyFeedback.font = .systemFont(ofSize: 12)
        actionRow.addArrangedSubview(copyFeedback)

        let credits = NSTextField(labelWithString: "Released under Apache-2.0 License. All rights reserved.")
        credits.textColor = .secondaryLabelColor
        credits.font = .systemFont(ofSize: 11)
        credits.lineBreakMode = .byWordWrapping
        credits.maximumNumberOfLines = 2
        stack.addArrangedSubview(credits)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 26),
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
        ])

        return root
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    @objc private func copyActivationCode() {
        guard let activationCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(activationCode, forType: .string)
        copyFeedback.stringValue = "Copied"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyFeedback.stringValue = ""
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
