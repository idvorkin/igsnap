# SnipSnap plan

A small native Mac screenshot app in the spirit of [Flameshot](https://github.com/flameshot-org/flameshot):
press a hotkey, pick a region or a window, draw on it, copy it.

Status: plan only. No code yet. Open decisions are at the end.

## Why build it

Be honest about the alternatives first.

| Option | What it already does | The gap |
| --- | --- | --- |
| Built-in ⌘⇧4 | Region drag, Space to pick a window, ⌃ to copy directly | Annotating means catching the floating thumbnail, opening Markup, then copying from there. Three steps and a timing game. |
| Flameshot | Everything asked for, annotate in place | Qt app, not notarized: its README says to clear quarantine by hand on macOS 15+. No window snap on the selection. |
| Shottr, CleanShot X | Likely all of it (from memory, not checked) | Not yours: closed source, and CleanShot is paid. |

So the real gap is narrow: **annotate in place and copy with one key, with window snap, in something you own**.
If Shottr already fits, installing it is the lazier answer and this repo should stay a plan. Worth five minutes
with Shottr before M1.

## The flow

1. Hotkey (⌘⇧X, Flameshot's Mac default) or the menu bar item.
2. The screen freezes and dims. Hovering highlights the window under the pointer.
3. Click to take that window's frame, or drag for a free region. Handles adjust it afterwards.
4. A small toolbar appears under the selection: arrow, rectangle, text, colour, undo, **Copy**, save.
5. ⌘C or Return copies the annotated image and closes. Esc cancels.

## Design

**Freeze first, then select.** On the hotkey, capture every display at full resolution, then show each capture
in a borderless full-screen window on its display. Selection and annotation happen on that frozen image, and
the result is a crop of it. This is what Flameshot does, and it removes two problems: nothing moves under the
pointer while selecting, and the overlay itself never appears in the shot.

**Capture.** `SCScreenshotManager.captureImage(contentFilter:configuration:)` (ScreenCaptureKit, macOS 14+)
with one `SCContentFilter` per display, cursor hidden. Checked against the Xcode 27.2 SDK:
`CGWindowListCreateImage` is marked obsolete as of macOS 15, so it is not an option.

**Window snap.** `CGWindowListCopyWindowInfo` (still available) returns on-screen window bounds front to back.
Take layer-0 windows, hit-test the pointer against them in order, highlight the first hit. Bounds need no
permission; window titles do, and we don't need titles.

**Hotkey.** Carbon `RegisterEventHotKey`. Old, but it needs no Accessibility permission, unlike an event tap.

**Shape of the app.** Menu bar only (`LSUIElement`), AppKit for the overlay, no SwiftUI needed.

**Layout**, mirroring `magic-monitor-native`: SwiftPM, a `justfile`, no Xcode project.

```
Package.swift
justfile              test, app, run, install
Support/Info.plist
Sources/SnipCore/     no AppKit: geometry, window hit-testing, annotation model, undo, rendering to CGImage
Sources/SnipSnap/     the app: status item, hotkey, capture, overlay windows, toolbar, pasteboard
Tests/SnipCoreTests/
```

`SnipCore` holds everything that can be wrong without a screen, so `swift test` covers it:

- Coordinate conversion. Window bounds are top-left origin in global points; AppKit is bottom-left;
  the captured image is in pixels at each display's scale. One function each way, tested with a
  two-display, mixed-scale fixture. This is where selection overlays usually break.
- Hit-testing a point against an ordered list of window rects.
- Selection maths: drag, resize by handle, clamp to the display.
- Annotations as values (`arrow`, `rect`, `text`, each with colour and width), an undo stack, and a renderer
  that draws them over a `CGImage`. Tested by rendering onto a blank image and reading known pixels.

## Permission and signing

Capture needs **Screen Recording** (System Settings → Privacy & Security). Two consequences:

- macOS ties the grant to the app's signature. An ad-hoc signed build gets a new identity every build and loses
  the grant. `just app` signs with the Apple Development identity already on this Mac, the same fix
  `magic-monitor-native` uses for the camera, so the grant survives rebuilds.
- On first run, `CGPreflightScreenCaptureAccess()`; if false, `CGRequestScreenCaptureAccess()` and show a
  one-line "grant, then relaunch" notice instead of a blank capture.

To verify in M0, not assumed: whether macOS 27 re-prompts periodically for apps that capture without the
system picker (macOS 15 introduced a recurring prompt). If it does, that is a standing annoyance to weigh.

## Milestones

Each one ends in something usable and a check.

| | Delivers | Check |
| --- | --- | --- |
| **M0 Skeleton** | Package, justfile, signed menu bar app, hotkey, permission check | Hotkey fires from any app. Grant survives a rebuild. |
| **M1 Region → copy** | Freeze, drag a region, Return copies | Paste into Preview: pixel size = points × display scale. Repeat on the external display and over a full-screen app. |
| **M2 Window snap** | Hover highlight, click to take the window | Click a half-covered window: selection equals its frame. Core hit-test tests pass. |
| **M3 Annotate** | Toolbar, arrow, rectangle, text, colour, undo, Copy button | Draw each, undo each, copy, paste: annotations sit where drawn at full resolution. |
| **M4 Polish** | Save to file (⌘S), launch at login | Only what use shows is missing. |

M1 alone already replaces ⌘⇧⌃4. M3 is the bulk of the work.

## Out of scope for v1

Pixelate/blur, pencil and marker, upload, capture history, scrolling capture, screen recording, pinning,
configurable hotkey UI, delay timer, edge-snapping while dragging, notarized distribution.
Pixelate is the first one to add if anything is.

## Risks

- **Overlay over full-screen apps and the menu bar.** Needs a high window level and
  `canJoinAllSpaces` + `fullScreenAuxiliary`. Checked in M1.
- **HDR displays.** Capture as SDR; a washed-out paste is the symptom to look for.
- **Hotkey clash.** ⌘⇧X may be taken in some apps; a global hotkey wins, which may itself be the annoyance.

## Open decisions

Recommendation first in each.

1. **What "smart window snap" means.** Hover-to-highlight, click to take the window (recommended, and what the
   plan assumes), or a dragged region whose edges snap to nearby window edges. The second is more work and can
   follow.
2. **Annotate in place on the overlay** (recommended, Flameshot's way, fewest steps) or in a separate editor
   window after capture (easier to build, one more window to dismiss).
3. **v1 tools: arrow, rectangle, text.** Add pixelate now if you redact often.
4. **Hotkey: ⌘⇧X.**
5. **Name: SnipSnap.** A placeholder; cheap to change before M0.
6. **Minimum macOS: 14**, the floor the capture API allows. Could be 26 or 27 since it is for this Mac.
7. **Repo visibility: private for now.**
