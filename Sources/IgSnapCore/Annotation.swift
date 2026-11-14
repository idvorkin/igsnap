import CoreGraphics
import CoreText
import Foundation

public struct RGBA: Equatable, Sendable {
    public var r, g, b, a: CGFloat
    public init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) {
        (self.r, self.g, self.b, self.a) = (r, g, b, a)
    }
    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    public static let red = RGBA(1, 0.23, 0.19)
    public static let yellow = RGBA(1, 0.8, 0)
    public static let green = RGBA(0.2, 0.78, 0.35)
    public static let blue = RGBA(0, 0.48, 1)
    public static let black = RGBA(0, 0, 0)
    public static let palette: [RGBA] = [.red, .yellow, .green, .blue, .black]
}

public enum Shape: Equatable, Sendable {
    case arrow(from: CGPoint, to: CGPoint)
    case rectangle(CGRect)
    /// A solid black box, for hiding what is under it. Ignores the colour.
    case blackout(CGRect)
    case ellipse(CGRect)
    /// `at` is the top-left of the line of text.
    case text(String, at: CGPoint)
}

public struct Annotation: Equatable, Sendable {
    /// Arrows are drawn heavier than outlines: they have to be seen from across the screenshot.
    public static let arrowWidth: CGFloat = 8

    public var shape: Shape
    public var color: RGBA
    public var lineWidth: CGFloat
    public var fontSize: CGFloat

    public init(_ shape: Shape, color: RGBA = .red, lineWidth: CGFloat = 5, fontSize: CGFloat = 18) {
        (self.shape, self.color, self.lineWidth, self.fontSize) = (shape, color, lineWidth, fontSize)
    }
}

/// The font for text annotations: the bold system font, so the editing field and the drawn text match.
public func annotationFont(size: CGFloat) -> CTFont {
    CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
        ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
}

/// Draws into a context whose y axis points down (a flipped view, or `render` below).
public func draw(_ annotation: Annotation, in ctx: CGContext) {
    ctx.saveGState()
    defer { ctx.restoreGState() }
    let color = annotation.color.cgColor
    ctx.setStrokeColor(color)
    ctx.setFillColor(color)
    ctx.setLineWidth(annotation.lineWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    switch annotation.shape {
    case .blackout(let rect):
        ctx.setFillColor(RGBA.black.cgColor)
        ctx.fill(rect)
    case .rectangle(let rect):
        ctx.stroke(rect)
    case .ellipse(let rect):
        ctx.strokeEllipse(in: rect)
    case .arrow(let from, let to):
        let dx = to.x - from.x, dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return }
        let ux = dx / length, uy = dy / length
        let head = min(max(14, annotation.lineWidth * 3.5), length)
        let half = head * 0.45
        // The shaft stops inside the head so its round cap doesn't blunt the tip.
        let base = CGPoint(x: to.x - ux * head, y: to.y - uy * head)
        ctx.move(to: from)
        ctx.addLine(to: base)
        ctx.strokePath()
        ctx.move(to: to)
        ctx.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
        ctx.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
        ctx.closePath()
        ctx.fillPath()
    case .text(let string, let at):
        let font = annotationFont(size: annotation.fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        // Core Text draws y-up; flip the glyphs back in a y-down context.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: at.x, y: at.y + CTFontGetAscent(font))
        CTLineDraw(line, ctx)
    }
}

/// The selection cropped out of the captured display image at full resolution, with the annotations drawn on it.
/// `selection` and the annotations are in display-local points; the image is `scale` pixels per point.
public func render(image: CGImage, selection: CGRect, scale: CGFloat, annotations: [Annotation]) -> CGImage? {
    let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let pixels = pixelRect(selection, scale: scale).intersection(full)
    guard pixels.width >= 1, pixels.height >= 1, let crop = image.cropping(to: pixels) else { return nil }
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard
        let ctx = CGContext(
            data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
    // From here on: y down, in points, origin at the display's top-left.
    ctx.translateBy(x: 0, y: CGFloat(crop.height))
    ctx.scaleBy(x: scale, y: -scale)
    ctx.translateBy(x: -pixels.minX / scale, y: -pixels.minY / scale)
    for annotation in annotations { draw(annotation, in: ctx) }
    return ctx.makeImage()
}
