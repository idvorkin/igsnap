import AppKit
import IgSnapCore

/// One display's frozen screenshot, with the selection, the annotations and the toolbar drawn over it.
/// Flipped, so view coordinates are the core's display-local space.
final class OverlayView: NSView, NSTextFieldDelegate {
    private let image: CGImage
    private let scale: CGFloat
    /// On-screen windows, front to back, in this display's space.
    private let windows: [CGRect]

    var onCopy: (CGImage, CGFloat) -> Void = { _, _ in }
    var onCancel: () -> Void = {}
    /// A selection started here: the other displays drop theirs.
    var onBegin: () -> Void = {}

    private(set) var selection: CGRect?
    private var hover: CGRect?
    private(set) var annotations: [Annotation] = []
    private var draft: Annotation?
    private var tool = Tool.arrow
    private var color = RGBA.red

    private enum Drag {
        case selecting(from: CGPoint)
        case resizing(Handle, original: CGRect)
        case drawing(from: CGPoint)
    }
    private var drag: Drag?
    private var moved = false
    private var textField: NSTextField?
    private let toolbar = Toolbar()

    init(frame: CGRect, image: CGImage, scale: CGFloat, windows: [CGRect]) {
        (self.image, self.scale, self.windows) = (image, scale, windows)
        super.init(frame: frame)
        toolbar.onTool = { [weak self] in self?.pick($0) }
        toolbar.onColor = { [weak self] in
            self?.commitText()
            self?.color = $0
            self?.refresh()
        }
        toolbar.onUndo = { [weak self] in self?.undo() }
        toolbar.onCopy = { [weak self] in self?.copyOut() }
        toolbar.onCancel = { [weak self] in self?.onCancel() }
        toolbar.isHidden = true
        addSubview(toolbar)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        )
    }

    // MARK: State changes

    /// Back to nothing selected.
    func reset() {
        textField?.removeFromSuperview()
        textField = nil
        (selection, hover, draft, drag) = (nil, nil, nil, nil)
        annotations = []
        refresh()
    }

    func select(_ rect: CGRect) {
        selection = rect.intersection(bounds)
        refresh()
    }

    func add(_ annotation: Annotation) {
        annotations.append(annotation)
        refresh()
    }

    private func pick(_ tool: Tool) {
        commitText()
        self.tool = tool
        refresh()
    }

    private func undo() {
        if textField != nil { cancelText() } else if !annotations.isEmpty { annotations.removeLast() }
        refresh()
    }

    private func copyOut() {
        commitText()
        guard let selection,
            let out = render(image: image, selection: selection, scale: scale, annotations: annotations)
        else { return }
        onCopy(out, scale)
    }

    private func refresh() {
        toolbar.update(tool: tool, color: color)
        var selecting = false
        if case .selecting = drag { selecting = true }
        if let selection, !selecting {
            toolbar.setFrameOrigin(toolbarOrigin(selection: selection, size: toolbar.frame.size, in: bounds))
            toolbar.isHidden = false
        } else {
            toolbar.isHidden = true
        }
        needsDisplay = true
    }

    // MARK: Mouse

    private func location(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    override func mouseMoved(with event: NSEvent) {
        hover(at: location(event))
    }

    /// Highlight the window under the point, while nothing is selected yet.
    func hover(at p: CGPoint) {
        guard selection == nil else { return }
        hover = windowUnder(p, windows: windows)?.intersection(bounds)
        needsDisplay = true
    }

    /// Highlight the window under a pointer that hasn't moved yet (a keyboard launch).
    func seedHover() {
        guard let window, selection == nil else { return }
        let p = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if bounds.contains(p) { hover = windowUnder(p, windows: windows)?.intersection(bounds) }
        needsDisplay = true
    }

    /// The way out that needs no keyboard: the overlay covers every display above everything else.
    override func rightMouseDown(with event: NSEvent) { onCancel() }

    override func mouseExited(with event: NSEvent) {
        hover = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        commitText()
        let p = location(event)
        moved = false
        if let selection {
            if let h = handle(at: p, in: selection, tolerance: 8) {
                drag = .resizing(h, original: selection)
            } else if selection.contains(p) {
                if tool == .text { beginText(at: p) } else { drag = .drawing(from: p) }
            } else {
                drag = .selecting(from: p)
            }
        } else {
            onBegin()
            drag = .selecting(from: p)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = location(event)
        switch drag {
        case .selecting(let from):
            // A few points of slack, so a shaky click still picks the window under it.
            guard moved || abs(p.x - from.x) + abs(p.y - from.y) > 4 else { return }
            if !moved { annotations = [] }
            moved = true
            selection = spanning(from: from, to: p)
        case .resizing(let handle, let original):
            selection = resized(original, handle: handle, to: p)
        case .drawing(let from):
            let shape: Shape =
                switch tool {
                case .arrow: .arrow(from: from, to: p)
                case .rectangle: .rectangle(spanning(from: from, to: p))
                case .blackout: .blackout(spanning(from: from, to: p))
                case .ellipse: .ellipse(spanning(from: from, to: p))
                case .text: .text("", at: from)
                }
            draft = Annotation(shape, color: color, lineWidth: tool == .arrow ? Annotation.arrowWidth : 5)
        case nil: break
        }
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        if case .selecting = drag, !moved, selection == nil { selection = hover }
        if let s = selection, s.width < 3 || s.height < 3 { selection = nil }
        if let draft { annotations.append(draft) }
        (draft, drag) = (nil, nil)
        refresh()
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let command = event.modifierFlags.contains(.command)
        switch (key, command) {
        case ("\u{1b}", _): onCancel()
        case ("\r", _), ("\u{3}", _), ("c", true): copyOut()
        case ("z", true): undo()
        case (_, false):
            if let tool = Tool.allCases.first(where: { $0.key == key }), selection != nil { pick(tool) }
        default: super.keyDown(with: event)
        }
    }

    // MARK: Text

    private func beginText(at p: CGPoint) {
        guard let selection else { return }
        let size: CGFloat = 18
        let field = NSTextField(
            frame: CGRect(x: p.x, y: p.y - size * 0.6, width: max(selection.maxX - p.x, 40), height: size * 1.4))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = annotationFont(size: size) as NSFont
        field.textColor = color.nsColor
        field.delegate = self
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
    }

    private func commitText() {
        guard let field = textField else { return }
        let string = field.stringValue
        // The field draws its text inset by the cell's 2 pt padding.
        let at = CGPoint(x: field.frame.minX + 2, y: field.frame.minY)
        cancelText()
        if !string.isEmpty { annotations.append(Annotation(.text(string, at: at), color: color)) }
        refresh()
    }

    private func cancelText() {
        textField?.removeFromSuperview()
        textField = nil
        window?.makeFirstResponder(self)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): commitText()
        case #selector(NSResponder.cancelOperation(_:)): cancelText()
        default: return false
        }
        return true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // ponytail: the whole display image is redrawn on every mouse move. Fine on Apple silicon at 5K; if it
        // ever drags, put the image in a layer underneath and draw only the dimming and annotations here.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: bounds)
        ctx.restoreGState()

        let clear = selection ?? hover
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let clear { dim.addRect(clear) }
        ctx.addPath(dim)
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.45))
        ctx.fillPath(using: .evenOdd)

        guard let selection else {
            if let hover {
                ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
                ctx.setLineWidth(3)
                ctx.stroke(hover.insetBy(dx: 1.5, dy: 1.5))
            }
            return
        }

        ctx.saveGState()
        ctx.clip(to: selection)
        for annotation in annotations { IgSnapCore.draw(annotation, in: ctx) }
        if let draft { IgSnapCore.draw(draft, in: ctx) }
        ctx.restoreGState()

        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        ctx.setLineWidth(1)
        ctx.stroke(selection.insetBy(dx: -0.5, dy: -0.5))
        for handle in Handle.allCases {
            let p = handle.point(in: selection)
            let box = CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(box)
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.6))
            ctx.stroke(box)
        }
    }
}
