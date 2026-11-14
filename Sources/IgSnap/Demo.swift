import AppKit
import IgSnapCore

/// `IgSnap --render-demo out.png`: the overlay, mid-edit, drawn off screen over a made-up desktop. A look at the
/// selection, annotations and toolbar without the Screen Recording permission or a window on screen (`just demo`).
func renderDemo(to path: String) {
    let size = CGSize(width: 1100, height: 700), scale: CGFloat = 2
    let windowRect = CGRect(x: 180, y: 110, width: 640, height: 400)

    let ctx = CGContext(
        data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: size.height * scale)
    ctx.scaleBy(x: scale, y: -scale)
    ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.45, blue: 0.6, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: size))
    ctx.setFillColor(CGColor(gray: 0.97, alpha: 1))
    ctx.fill(windowRect)
    ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
    ctx.fill(CGRect(x: windowRect.minX, y: windowRect.minY, width: windowRect.width, height: 28))
    IgSnapCore.draw(Annotation(.text("A window", at: CGPoint(x: 200, y: 160)), color: .black, fontSize: 24), in: ctx)

    let view = OverlayView(frame: CGRect(origin: .zero, size: size), image: ctx.makeImage()!, scale: scale, windows: [windowRect])
    view.select(windowRect)
    view.add(Annotation(.arrow(from: CGPoint(x: 560, y: 380), to: CGPoint(x: 340, y: 200))))
    view.add(Annotation(.rectangle(CGRect(x: 190, y: 150, width: 150, height: 44))))
    view.add(Annotation(.ellipse(CGRect(x: 600, y: 200, width: 160, height: 100)), color: .blue))
    view.add(Annotation(.text("look here", at: CGPoint(x: 570, y: 372)), color: .red))

    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
