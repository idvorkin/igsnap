import AppKit
import IgSnapCore

/// `IgSnap --render-demo <dir>` (`just demo`): the README's pictures, drawn off screen over a made-up desktop:
/// picking a window, annotating it, and what lands on the clipboard. No Screen Recording permission, no window on
/// screen, and nothing of a real desktop in a public repo.
func renderDemo(to directory: String) {
    let size = CGSize(width: 1100, height: 700), scale: CGFloat = 2
    let windowRect = CGRect(x: 180, y: 110, width: 640, height: 400)
    let behind = CGRect(x: 560, y: 60, width: 460, height: 560)

    let ctx = CGContext(
        data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: size.height * scale)
    ctx.scaleBy(x: scale, y: -scale)
    ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.45, blue: 0.6, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: size))
    for (rect, body) in [(behind, 0.9), (windowRect, 0.97)] {
        ctx.setFillColor(CGColor(gray: body, alpha: 1))
        ctx.fill(rect)
        ctx.setFillColor(CGColor(gray: body - 0.12, alpha: 1))
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 28))
    }
    func label(_ text: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 16) {
        IgSnapCore.draw(Annotation(.text(text, at: CGPoint(x: x, y: y)), color: .black, fontSize: size), in: ctx)
    }
    label("Deploy settings", 200, 160, size: 24)
    label("Region        us-west-2", 220, 230)
    label("Replicas      3", 220, 270)
    label("API key       sk-live-4f9a-example", 220, 425)
    label("Logs", 840, 110, size: 20)
    let image = ctx.makeImage()!

    func overlay() -> OverlayView {
        OverlayView(
            frame: CGRect(origin: .zero, size: size), image: image, scale: scale, windows: [windowRect, behind])
    }
    func write(_ rep: NSBitmapImageRep, _ name: String) {
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
        print(url.path)
    }
    func snapshot(_ view: OverlayView, _ name: String) {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        write(rep, name)
    }

    let picking = overlay()
    picking.hover(at: CGPoint(x: 300, y: 300))
    snapshot(picking, "1-pick.png")

    let annotations = [
        Annotation(
            .arrow(from: CGPoint(x: 640, y: 330), to: CGPoint(x: 400, y: 285)), lineWidth: Annotation.arrowWidth),
        Annotation(.text("should be 5", at: CGPoint(x: 650, y: 320))),
        Annotation(.rectangle(CGRect(x: 212, y: 222, width: 200, height: 34)), color: .blue),
        Annotation(.ellipse(CGRect(x: 200, y: 258, width: 190, height: 44))),
        Annotation(.blackout(CGRect(x: 318, y: 420, width: 250, height: 30))),
    ]
    let editing = overlay()
    editing.select(windowRect)
    annotations.forEach(editing.add)
    snapshot(editing, "2-annotate.png")

    let result = render(image: image, selection: windowRect, scale: scale, annotations: annotations)!
    write(NSBitmapImageRep(cgImage: result), "3-result.png")
}
