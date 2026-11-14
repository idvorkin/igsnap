# IgSnap plan

A small native Mac screenshot app in the spirit of [Flameshot](https://github.com/flameshot-org/flameshot):
run it, pick a region or a window, draw on it, copy it.

## Why build it

| Option | What it already does | The gap |
| --- | --- | --- |
| Built-in ⌘⇧4 | Region drag, Space to pick a window, ⌃ to copy directly | Annotating means catching the floating thumbnail, opening Markup, then copying from there. |
| Flameshot | Annotate in place | Qt app, not notarized: its README says to clear quarantine by hand on macOS 15+. No window snap. |
| Shottr, CleanShot X | Likely all of it (from memory, not checked) | Closed source; CleanShot is paid. |

The gap is narrow: annotate in place and copy with one key, with window snap, in something Igor owns.

## Decisions

- **Run-and-quit.** No hotkey, no menu bar item. Launching the app is the trigger, so Alfred or `y sss` can call it.
- **Window snap** means hover highlights the window under the pointer and a click takes its frame.
- **Annotate in place** on the frozen screen, not in a separate editor window.
- **Tools:** arrow, rectangle, ellipse, text. Five colours. Undo.
- **macOS 27 only.**

## Design

**Freeze first, then select.** On launch, capture every display at full resolution and show each capture in a
borderless full-screen window on its display. Selection and annotation happen on that frozen image and the
result is a crop of it. Nothing moves under the pointer, and the overlay never appears in the shot.

**Capture.** `SCScreenshotManager.captureImage(contentFilter:configuration:)`, one `SCContentFilter` per display,
cursor hidden. `CGWindowListCreateImage` is marked obsolete in the SDK.

**Window snap.** `CGWindowListCopyWindowInfo` gives on-screen window bounds front to back. Layer-0 windows,
hit-tested in order. Bounds need no permission.

**One coordinate space.** `IgSnapCore` works in display-local points, origin top-left, y down: the space window
bounds and `CGDisplayBounds` already use, minus the display's origin. The overlay view is flipped to match, and
the captured image is cropped in the same space times the display's scale. Mixed-scale and multi-display setups
then need no special case.

```
Sources/IgSnapCore/   no AppKit: geometry, hit-testing, annotations, rendering to CGImage. Host tests.
Sources/IgSnap/       the app: capture, overlay windows, toolbar, pasteboard, the off-screen demo
```

**Permission and signing.** Capture needs Screen Recording, and macOS ties the grant to the app's signature.
`just app` signs with the Apple Development identity so the grant survives rebuilds.

## Status

Built: region select, window snap, the four tools, colours, undo, copy.

Checked by `just test`: coordinate conversion, hit-testing, handle resizing, toolbar placement, and that the
crop is full resolution, the right way up, with annotations where they were drawn.
Checked by eye from `just demo`: the overlay, selection, annotations and toolbar.

**Not yet checked on a real screen**, because it needs the Screen Recording grant and hands:

- [ ] The capture itself, and that the grant survives a rebuild
- [ ] Paste into Preview: pixel size = points × display scale
- [ ] Window snap picks a half-covered window's frame
- [ ] Keys reach the overlay (Esc, Return, typing text)
- [ ] The external display, and over a full-screen app
- [ ] Whether macOS 27 re-prompts periodically for Screen Recording
- [ ] Launched from Alfred: is Alfred's own window gone before the capture?

## Later, if use shows it is missing

Save to file, pixelate, moving an annotation after drawing it, multi-line text, edge-snapping while dragging.

## Risks

- **HDR displays.** The capture is SDR; a washed-out paste is the symptom.
- **Redraw cost.** The whole display image is redrawn on each mouse move (`ponytail:` in `OverlayView.draw`).
