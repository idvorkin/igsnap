import CoreGraphics

// Everything in the core is display-local: points, origin top-left, y down. The app converts once, on the way in
// (window bounds, mouse) and never on the way out: the captured image is cropped in the same space times `scale`.

/// A global rect (top-left origin, as CGDisplayBounds and CGWindowList give it) in one display's local space.
public func localRect(_ global: CGRect, onDisplay display: CGRect) -> CGRect {
    global.offsetBy(dx: -display.minX, dy: -display.minY)
}

/// The frontmost window under the point. `windows` is front to back.
public func windowUnder(_ point: CGPoint, windows: [CGRect]) -> CGRect? {
    windows.first { $0.contains(point) }
}

public func spanning(from a: CGPoint, to b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
}

/// The rect in image pixels, on whole pixels.
public func pixelRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
    let minX = (rect.minX * scale).rounded(), minY = (rect.minY * scale).rounded()
    let maxX = (rect.maxX * scale).rounded(), maxY = (rect.maxY * scale).rounded()
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

public enum Handle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    // -1: the min edge moves, 1: the max edge moves, 0: neither.
    var x: Int {
        switch self {
        case .topLeft, .left, .bottomLeft: -1
        case .topRight, .right, .bottomRight: 1
        case .top, .bottom: 0
        }
    }
    var y: Int {
        switch self {
        case .topLeft, .top, .topRight: -1
        case .bottomLeft, .bottom, .bottomRight: 1
        case .left, .right: 0
        }
    }

    public func point(in rect: CGRect) -> CGPoint {
        CGPoint(
            x: x < 0 ? rect.minX : x > 0 ? rect.maxX : rect.midX,
            y: y < 0 ? rect.minY : y > 0 ? rect.maxY : rect.midY)
    }
}

public func handle(at point: CGPoint, in rect: CGRect, tolerance: CGFloat) -> Handle? {
    Handle.allCases.first {
        let h = $0.point(in: rect)
        return abs(h.x - point.x) <= tolerance && abs(h.y - point.y) <= tolerance
    }
}

/// The rect after dragging a handle to the point. Dragging past the opposite edge flips it rather than going negative.
public func resized(_ rect: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
    var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
    if handle.x < 0 { minX = point.x } else if handle.x > 0 { maxX = point.x }
    if handle.y < 0 { minY = point.y } else if handle.y > 0 { maxY = point.y }
    return spanning(from: CGPoint(x: minX, y: minY), to: CGPoint(x: maxX, y: maxY))
}

/// Where the toolbar goes: under the selection, right-aligned; above it when there is no room; inside it otherwise.
public func toolbarOrigin(selection: CGRect, size: CGSize, in bounds: CGRect, gap: CGFloat = 8) -> CGPoint {
    let x = min(max(selection.maxX - size.width, bounds.minX + gap), bounds.maxX - size.width - gap)
    if selection.maxY + gap + size.height <= bounds.maxY { return CGPoint(x: x, y: selection.maxY + gap) }
    if selection.minY - gap - size.height >= bounds.minY {
        return CGPoint(x: x, y: selection.minY - gap - size.height)
    }
    return CGPoint(x: x, y: selection.maxY - gap - size.height)
}
