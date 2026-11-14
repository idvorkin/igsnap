import AppKit
import IgSnapCore

enum Tool: CaseIterable {
    case arrow, rectangle, ellipse, text

    var symbol: String {
        switch self {
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "oval"
        case .text: "textformat"
        }
    }
    var key: String {
        switch self {
        case .arrow: "a"
        case .rectangle: "r"
        case .ellipse: "e"
        case .text: "t"
        }
    }
    var name: String {
        switch self {
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .text: "Text"
        }
    }
}

extension RGBA {
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

private final class ActionButton: NSButton {
    var onClick: () -> Void = {}

    convenience init(symbol: String, tip: String, onClick: @escaping () -> Void) {
        self.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        isBordered = false
        toolTip = tip
        setUp(onClick)
        widthAnchor.constraint(equalToConstant: 26).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    func setUp(_ onClick: @escaping () -> Void) {
        self.onClick = onClick
        target = self
        action = #selector(clicked)
    }

    @objc private func clicked() { onClick() }
}

/// The strip under the selection: tools, colours, undo, Copy, cancel.
final class Toolbar: NSView {
    var onTool: (Tool) -> Void = { _ in }
    var onColor: (RGBA) -> Void = { _ in }
    var onUndo: () -> Void = {}
    var onCopy: () -> Void = {}
    var onCancel: () -> Void = {}

    private var toolButtons: [(Tool, NSButton)] = []
    private var colorButtons: [(RGBA, NSButton)] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.92).cgColor
        layer?.cornerRadius = 9

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)

        for tool in Tool.allCases {
            let button = ActionButton(symbol: tool.symbol, tip: "\(tool.name) (\(tool.key.uppercased()))") {
                [weak self] in
                self?.onTool(tool)
            }
            toolButtons.append((tool, button))
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(divider())
        for color in RGBA.palette {
            let button = ActionButton(symbol: "circle.fill", tip: "Colour") { [weak self] in self?.onColor(color) }
            colorButtons.append((color, button))
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(
            tinted(ActionButton(symbol: "arrow.uturn.backward", tip: "Undo (⌘Z)") { [weak self] in self?.onUndo() }))
        stack.addArrangedSubview(
            tinted(ActionButton(symbol: "xmark", tip: "Cancel (Esc)") { [weak self] in self?.onCancel() }))

        let copy = ActionButton(title: "Copy", target: nil, action: nil)
        copy.setUp { [weak self] in self?.onCopy() }
        copy.bezelStyle = .rounded
        copy.bezelColor = .controlAccentColor
        copy.toolTip = "Copy and close (Return or ⌘C)"
        stack.addArrangedSubview(copy)

        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setFrameSize(stack.fittingSize)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // A click on the padding stays here instead of drawing on the screenshot underneath.
    override func mouseDown(with event: NSEvent) {}

    func update(tool: Tool, color: RGBA) {
        for (t, button) in toolButtons { button.contentTintColor = t == tool ? .controlAccentColor : .white }
        for (c, button) in colorButtons {
            button.contentTintColor = c.nsColor
            let symbol = c == color ? "circle.inset.filled" : "circle.fill"
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Colour")?
                .withSymbolConfiguration(.init(pointSize: c == color ? 17 : 13, weight: .medium))
        }
    }

    private func tinted(_ button: NSButton) -> NSButton {
        button.contentTintColor = .white
        return button
    }

    private func divider() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(white: 1, alpha: 0.25).cgColor
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        line.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return line
    }
}
