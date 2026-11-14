import AppKit
import IgSnapCore
import ScreenCaptureKit

// Run it and it captures: every display freezes, you pick a window or drag a region, draw, copy. Then it quits.
// There is no hotkey and no menu bar item; whatever launches it (Alfred, `y sss`) is the trigger.

/// Borderless windows refuse key status by default; the overlay needs it for Esc, Return and typing.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct Shot {
    let screen: NSScreen
    let image: CGImage
    /// The display in global top-left coordinates, the space window bounds come in.
    let bounds: CGRect
}

func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
}

func captureDisplays() async throws -> [Shot] {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    var shots: [Shot] = []
    for screen in NSScreen.screens {
        guard let id = displayID(screen), let display = content.displays.first(where: { $0.displayID == id }) else {
            continue
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        shots.append(Shot(screen: screen, image: image, bounds: CGDisplayBounds(id)))
    }
    return shots
}

/// Ordinary app windows, front to back, in global top-left coordinates. Bounds need no permission.
func windowRects() -> [CGRect] {
    let info =
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        ?? []
    let me = getpid()
    return info.compactMap { window in
        guard window[kCGWindowLayer as String] as? Int == 0,
            window[kCGWindowOwnerPID as String] as? pid_t != me,
            (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
            let dict = window[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: dict), rect.width >= 40, rect.height >= 40
        else { return nil }
        return rect
    }
}

func copyToPasteboard(_ image: CGImage, scale: CGFloat) {
    let rep = NSBitmapImageRep(cgImage: image)
    // Point size, so a Retina shot pastes at the size it was on screen (what screencapture does).
    rep.size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    if let png = rep.representation(using: .png, properties: [:]) { pasteboard.setData(png, forType: .png) }
    if let tiff = rep.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [OverlayWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            fail(
                "IgSnap needs Screen Recording permission",
                "Turn IgSnap on in System Settings → Privacy & Security → Screen & System Audio Recording, then run it again.",
                settings: true)
            return
        }
        // Before the overlays exist, so neither the list nor the capture includes them.
        let rects = windowRects()
        Task { @MainActor in
            do {
                let shots = try await captureDisplays()
                if shots.isEmpty {
                    fail("No display to capture", "ScreenCaptureKit returned no displays.")
                } else {
                    show(shots, rects)
                }
            } catch {
                fail("The capture failed", error.localizedDescription)
            }
        }
    }

    private func show(_ shots: [Shot], _ rects: [CGRect]) {
        var views: [OverlayView] = []
        for shot in shots {
            let frame = shot.screen.frame
            let view = OverlayView(
                frame: CGRect(origin: .zero, size: frame.size), image: shot.image,
                scale: CGFloat(shot.image.width) / frame.width,
                windows: rects.map { localRect($0, onDisplay: shot.bounds) })
            view.onCopy = { image, scale in
                copyToPasteboard(image, scale: scale)
                NSApp.terminate(nil)
            }
            view.onCancel = { NSApp.terminate(nil) }
            views.append(view)

            let window = OverlayWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.hasShadow = false
            window.animationBehavior = .none
            window.acceptsMouseMovedEvents = true
            window.contentView = view
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
        for view in views {
            view.onBegin = { [weak view] in
                for other in views where other !== view { other.reset() }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        // Keys go to the display the pointer is on.
        let pointed = windows.first { $0.frame.contains(NSEvent.mouseLocation) } ?? windows.first
        pointed?.makeKeyAndOrderFront(nil)
        pointed?.makeFirstResponder(pointed?.contentView)
        (pointed?.contentView as? OverlayView)?.seedHover()
    }

    private func fail(_ title: String, _ detail: String, settings: Bool = false) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "Quit")
        if settings { alert.addButton(withTitle: "Open Settings") }
        if alert.runModal() == .alertSecondButtonReturn,
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        {
            NSWorkspace.shared.open(url)
        }
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if let i = CommandLine.arguments.firstIndex(of: "--render-demo"), CommandLine.arguments.count > i + 1 {
    renderDemo(to: CommandLine.arguments[i + 1])
    exit(0)
}
if CommandLine.arguments.contains("--self-test") { exit(selfTest() ? 0 : 1) }

let delegate = AppDelegate()
app.delegate = delegate
app.run()
