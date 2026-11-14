import AppKit
import IgSnapCore

/// `IgSnap --self-test` (`just selftest`): the overlay's real mouse and key handlers, driven by made-up events in
/// a window that is never shown. No permission, nothing on screen. What it can't cover is the capture and whether
/// the window server delivers events to the live overlay.
func selfTest() -> Bool {
    let size = CGSize(width: 800, height: 600), scale: CGFloat = 2
    let front = CGRect(x: 100, y: 100, width: 300, height: 200)
    let back = CGRect(x: 50, y: 50, width: 600, height: 400)
    let ctx = CGContext(
        data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    var failures = 0
    func check(_ ok: Bool, _ what: String) {
        print(ok ? "  ok    \(what)" : "  FAIL  \(what)")
        if !ok { failures += 1 }
    }

    var copied: CGImage?
    var cancelled = 0
    func makeView() -> (OverlayView, NSWindow) {
        let view = OverlayView(
            frame: CGRect(origin: .zero, size: size), image: ctx.makeImage()!, scale: scale, windows: [front, back])
        view.onCopy = { image, _ in copied = image }
        view.onCancel = { cancelled += 1 }
        let window = OverlayWindow(
            contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.makeFirstResponder(view)
        return (view, window)
    }

    // Points are given as the view sees them (top-left origin); events carry window coordinates (bottom-left).
    func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: CGPoint(x: x, y: size.height - y), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    func key(_ characters: String, command: Bool = false, in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: command ? .command : [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0)!
    }
    func drag(_ view: OverlayView, _ window: NSWindow, from a: CGPoint, to b: CGPoint) {
        view.mouseDown(with: mouse(.leftMouseDown, a.x, a.y, in: window))
        view.mouseDragged(with: mouse(.leftMouseDragged, (a.x + b.x) / 2, (a.y + b.y) / 2, in: window))
        view.mouseDragged(with: mouse(.leftMouseDragged, b.x, b.y, in: window))
        view.mouseUp(with: mouse(.leftMouseUp, b.x, b.y, in: window))
    }

    print("window snap")
    var (view, window) = makeView()
    view.mouseMoved(with: mouse(.mouseMoved, 150, 150, in: window))
    view.mouseDown(with: mouse(.leftMouseDown, 150, 150, in: window))
    view.mouseUp(with: mouse(.leftMouseUp, 150, 150, in: window))
    check(view.selection == front, "hover then click takes the front window")

    (view, window) = makeView()
    view.mouseMoved(with: mouse(.mouseMoved, 500, 400, in: window))
    view.mouseDown(with: mouse(.leftMouseDown, 500, 400, in: window))
    view.mouseUp(with: mouse(.leftMouseUp, 500, 400, in: window))
    check(view.selection == back, "a click beside it takes the window behind")

    (view, window) = makeView()
    view.mouseMoved(with: mouse(.mouseMoved, 750, 550, in: window))
    view.mouseDown(with: mouse(.leftMouseDown, 750, 550, in: window))
    view.mouseUp(with: mouse(.leftMouseUp, 750, 550, in: window))
    check(view.selection == nil, "a click on no window selects nothing")

    print("region")
    (view, window) = makeView()
    drag(view, window, from: CGPoint(x: 600, y: 500), to: CGPoint(x: 200, y: 100))
    let region = CGRect(x: 200, y: 100, width: 400, height: 400)
    check(view.selection == region, "a drag up and left takes the region")
    drag(view, window, from: CGPoint(x: 600, y: 500), to: CGPoint(x: 700, y: 550))
    check(view.selection == CGRect(x: 200, y: 100, width: 500, height: 450), "dragging a corner handle resizes")
    drag(view, window, from: CGPoint(x: 700, y: 550), to: CGPoint(x: 600, y: 500))

    print("annotate")
    drag(view, window, from: CGPoint(x: 250, y: 150), to: CGPoint(x: 350, y: 250))
    check(
        view.annotations.last?.shape == .arrow(from: CGPoint(x: 250, y: 150), to: CGPoint(x: 350, y: 250)),
        "arrow is the default tool")
    view.keyDown(with: key("r", in: window))
    drag(view, window, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 400, y: 300))
    check(
        view.annotations.last?.shape == .rectangle(CGRect(x: 300, y: 200, width: 100, height: 100)),
        "R draws a rectangle")
    view.keyDown(with: key("e", in: window))
    drag(view, window, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 400, y: 300))
    check(
        view.annotations.last?.shape == .ellipse(CGRect(x: 300, y: 200, width: 100, height: 100)), "E draws an ellipse")
    view.keyDown(with: key("b", in: window))
    drag(view, window, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 400, y: 300))
    check(
        view.annotations.last?.shape == .blackout(CGRect(x: 300, y: 200, width: 100, height: 100)), "B blacks out a box"
    )
    view.keyDown(with: key("z", command: true, in: window))
    check(view.annotations.count == 3, "three annotations")
    view.keyDown(with: key("z", command: true, in: window))
    check(view.annotations.count == 2, "⌘Z removes the last")

    view.keyDown(with: key("t", in: window))
    view.mouseDown(with: mouse(.leftMouseDown, 300, 300, in: window))
    view.mouseUp(with: mouse(.leftMouseUp, 300, 300, in: window))
    let field = view.subviews.compactMap { $0 as? NSTextField }.first
    check(field != nil, "T then a click opens a text field")
    check(window.firstResponder === field?.currentEditor(), "the field has the keyboard")
    field?.stringValue = "hello"
    // A click elsewhere in the selection commits the text and starts another.
    view.mouseDown(with: mouse(.leftMouseDown, 250, 400, in: window))
    view.mouseUp(with: mouse(.leftMouseUp, 250, 400, in: window))
    if case .text(let string, _)? = view.annotations.last?.shape {
        check(string == "hello", "the typed text becomes an annotation")
    } else {
        check(false, "the typed text becomes an annotation")
    }
    view.keyDown(with: key("z", command: true, in: window))
    check(view.subviews.compactMap { $0 as? NSTextField }.isEmpty, "⌘Z drops an open text field")
    check(window.firstResponder === view, "and the keyboard is back on the overlay")

    print("toolbar")
    let toolbar = view.subviews.compactMap { $0 as? Toolbar }.first
    check(toolbar?.isHidden == false, "shown once there is a selection")
    check(toolbar.map { view.bounds.contains($0.frame) } == true, "and on screen")
    let before = view.annotations.count
    if let toolbar {
        let p = CGPoint(x: toolbar.frame.minX + 2, y: toolbar.frame.minY + 2)
        // hitTest takes the superview's coordinates.
        let hit = view.hitTest(view.superview.map { view.convert(p, to: $0) } ?? p)
        check(hit?.isDescendant(of: toolbar) == true, "its padding takes the click, not the screenshot")
        hit?.mouseDown(with: mouse(.leftMouseDown, p.x, p.y, in: window))
        hit?.mouseUp(with: mouse(.leftMouseUp, p.x, p.y, in: window))
    }
    check(view.annotations.count == before, "no stray annotation")

    print("finish")
    view.keyDown(with: key("\r", in: window))
    check(
        copied.map { $0.width == 800 && $0.height == 800 } == true,
        "Return copies the selection at 2× (400 pt → 800 px)")
    copied = nil
    view.keyDown(with: key("c", command: true, in: window))
    check(copied != nil, "⌘C copies")
    view.keyDown(with: key("\u{1b}", in: window))
    check(cancelled == 1, "Esc cancels")
    view.rightMouseDown(with: mouse(.rightMouseDown, 10, 10, in: window))
    check(cancelled == 2, "right-click cancels")

    print(failures == 0 ? "self-test passed" : "self-test FAILED: \(failures)")
    return failures == 0
}
