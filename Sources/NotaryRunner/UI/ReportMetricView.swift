import AppKit

final class ReportMetricView: NSView {
    private let titleField: NSTextField
    private let valueField: NSTextField

    var value: String {
        get { valueField.stringValue }
        set { valueField.stringValue = newValue }
    }

    init(title: String) {
        self.titleField = NSTextField(labelWithString: title)
        self.valueField = NSTextField(labelWithString: "—")
        super.init(frame: .zero)

        titleField.textColor = .secondaryLabelColor
        titleField.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        addSubview(titleField)

        valueField.textColor = .labelColor
        valueField.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        valueField.lineBreakMode = .byWordWrapping
        valueField.maximumNumberOfLines = 2
        valueField.cell?.wraps = true
        valueField.cell?.isScrollable = false
        valueField.cell?.usesSingleLineMode = false
        addSubview(valueField)
    }

    func applyAppearanceColors() {
        titleField.textColor = .secondaryLabelColor
        valueField.textColor = .labelColor
        needsDisplay = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        titleField.frame = NSRect(x: 0, y: bounds.height - 18, width: bounds.width, height: 16)
        valueField.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - 18)
    }
}
