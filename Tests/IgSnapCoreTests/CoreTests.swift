import CoreGraphics
import Testing

@testable import IgSnapCore

/// 200×200 px, white, with a black top-left quadrant: tells top from bottom.
private func fixture() -> CGImage {
    let ctx = CGContext(
        data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 100, width: 100, height: 100))  // y-up: this is the top half
    return ctx.makeImage()!
}

/// RGB at a pixel, counted from the top-left.
private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let ctx = CGContext(
        data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let i = (y * image.width + x) * 4
    return Array(data[i..<i + 3])
}

private func isRed(_ p: [UInt8]) -> Bool { p[0] > 200 && p[1] < 100 && p[2] < 100 }

@Test func windowBoundsBecomeLocalToASecondDisplay() {
    // A display to the left of and above the primary has a negative global origin.
    let display = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
    let window = CGRect(x: -1900, y: -100, width: 800, height: 600)
    #expect(localRect(window, onDisplay: display) == CGRect(x: 20, y: 100, width: 800, height: 600))
}

@Test func theFrontmostWindowUnderThePointerWins() {
    let front = CGRect(x: 100, y: 100, width: 200, height: 200)
    let back = CGRect(x: 0, y: 0, width: 1000, height: 800)
    #expect(windowUnder(CGPoint(x: 150, y: 150), windows: [front, back]) == front)
    #expect(windowUnder(CGPoint(x: 50, y: 50), windows: [front, back]) == back)
    #expect(windowUnder(CGPoint(x: 2000, y: 50), windows: [front, back]) == nil)
}

@Test func aDragInAnyDirectionGivesAPositiveRect() {
    #expect(
        spanning(from: CGPoint(x: 50, y: 60), to: CGPoint(x: 10, y: 20)) == CGRect(x: 10, y: 20, width: 40, height: 40))
}

@Test func pixelRectsLandOnWholePixels() {
    #expect(
        pixelRect(CGRect(x: 10.25, y: 10, width: 50, height: 50.5), scale: 2)
            == CGRect(x: 21, y: 20, width: 100, height: 101))
}

@Test func handlesAreFoundAndResizeTheirEdges() {
    let r = CGRect(x: 100, y: 100, width: 200, height: 100)
    #expect(handle(at: CGPoint(x: 302, y: 198), in: r, tolerance: 6) == .bottomRight)
    #expect(handle(at: CGPoint(x: 200, y: 150), in: r, tolerance: 6) == nil)
    #expect(resized(r, handle: .right, to: CGPoint(x: 400, y: 0)) == CGRect(x: 100, y: 100, width: 300, height: 100))
    #expect(resized(r, handle: .topLeft, to: CGPoint(x: 50, y: 80)) == CGRect(x: 50, y: 80, width: 250, height: 120))
    // Past the opposite edge: flips instead of going negative.
    #expect(resized(r, handle: .left, to: CGPoint(x: 350, y: 0)) == CGRect(x: 300, y: 100, width: 50, height: 100))
}

@Test func theToolbarGoesBelowThenAboveThenInside() {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 300, height: 40)
    #expect(
        toolbarOrigin(selection: CGRect(x: 100, y: 100, width: 500, height: 300), size: size, in: bounds)
            == CGPoint(x: 300, y: 408))
    #expect(
        toolbarOrigin(selection: CGRect(x: 100, y: 400, width: 500, height: 400), size: size, in: bounds)
            == CGPoint(x: 300, y: 352))
    #expect(toolbarOrigin(selection: bounds, size: size, in: bounds) == CGPoint(x: 692, y: 752))
    // A narrow selection at the left edge: the toolbar stays on screen.
    #expect(toolbarOrigin(selection: CGRect(x: 0, y: 100, width: 50, height: 50), size: size, in: bounds).x == 8)
}

@Test func theCropIsFullResolutionAndTheRightWayUp() throws {
    let image = fixture()  // a 100×100 pt display at 2×
    let top = try #require(
        render(image: image, selection: CGRect(x: 10, y: 10, width: 30, height: 20), scale: 2, annotations: []))
    #expect(top.width == 60 && top.height == 40)
    #expect(pixel(top, 5, 5) == [0, 0, 0])
    let bottom = try #require(
        render(image: image, selection: CGRect(x: 10, y: 60, width: 30, height: 20), scale: 2, annotations: []))
    #expect(pixel(bottom, 5, 5) == [255, 255, 255])
}

@Test func annotationsLandWhereTheyWereDrawn() throws {
    // White bottom-right quadrant of the fixture; a rectangle drawn at display point (60, 60), 20×20.
    let selection = CGRect(x: 50, y: 50, width: 50, height: 50)
    let box = Annotation(.rectangle(CGRect(x: 60, y: 60, width: 20, height: 20)), lineWidth: 2)
    let out = try #require(render(image: fixture(), selection: selection, scale: 2, annotations: [box]))
    #expect(isRed(pixel(out, 20, 40)))  // left edge, midway down
    #expect(isRed(pixel(out, 40, 20)))  // top edge
    #expect(pixel(out, 40, 40) == [255, 255, 255])  // inside stays clear
    #expect(pixel(out, 80, 80) == [255, 255, 255])  // outside
}

@Test func anArrowHasAShaftAndAHeadAtTheTargetEnd() throws {
    let selection = CGRect(x: 50, y: 50, width: 50, height: 50)
    let arrow = Annotation(.arrow(from: CGPoint(x: 55, y: 75), to: CGPoint(x: 95, y: 75)), lineWidth: 2)
    let out = try #require(render(image: fixture(), selection: selection, scale: 2, annotations: [arrow]))
    #expect(isRed(pixel(out, 30, 50)))  // on the shaft
    #expect(isRed(pixel(out, 72, 56)))  // head is wider than the shaft, near its base
    #expect(!isRed(pixel(out, 30, 56)))  // the shaft is not
}

@Test func textIsDrawnBelowItsTopLeftPoint() throws {
    let selection = CGRect(x: 50, y: 50, width: 50, height: 50)
    let text = Annotation(.text("████", at: CGPoint(x: 55, y: 60)), fontSize: 20)
    let out = try #require(render(image: fixture(), selection: selection, scale: 2, annotations: [text]))
    #expect(isRed(pixel(out, 30, 44)))  // inside the block glyphs, below the anchor
    #expect(!isRed(pixel(out, 30, 8)))  // nothing above the anchor
}

@Test func anEmptySelectionRendersNothing() {
    #expect(
        render(image: fixture(), selection: CGRect(x: 500, y: 500, width: 10, height: 10), scale: 2, annotations: [])
            == nil)
}
