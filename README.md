# IgSnap

A small native Mac screenshot app. Run it and the screen freezes: click a window or drag a region, draw on it,
copy it. Then it quits. No hotkey, no menu bar item; whatever launches it is the trigger.

**1. Pick.** The screen freezes and dims. Hovering highlights the window under the pointer; a click takes it, a
drag takes any region.

![Hovering highlights a window](docs/1-pick.png)

**2. Annotate.** Arrow, rectangle, ellipse, black-out box and text, in five colours.

![Annotating the selection](docs/2-annotate.png)

**3. Copy.** Return puts the result on the clipboard at full resolution.

![What lands on the clipboard](docs/3-result.png)

The pictures are drawn by `just demo` over a made-up desktop, so the README never shows a real one.

## Use

```
just install      # build, sign, copy to /Applications
open -a IgSnap
```

The first run asks for Screen Recording permission (System Settings → Privacy & Security). Grant it and run again.

| | |
| --- | --- |
| Hover, click | Take the window under the pointer |
| Drag | Take a region. Handles adjust it; dragging outside starts over |
| `A` `R` `E` `B` `T` | Arrow, rectangle, ellipse, black-out box, text |
| ⌘Z | Undo |
| Return or ⌘C | Copy and quit |
| Esc or right-click | Quit |

## Develop

```
just test         # core tests: geometry, hit-testing, rendering
just selftest     # the overlay's mouse and key handlers, driven headless
just demo         # redraw the pictures above into docs/, off screen, no permission needed
just run          # build and take a screenshot
```

Needs macOS 27 and the Xcode toolchain. Design notes and what is left: [PLAN.md](PLAN.md).
