app := "build/IgSnap.app"
installed := "/Applications/IgSnap.app"

default:
    @just --list

# Host tests for IgSnapCore: geometry, hit-testing, rendering.
test:
    #!/usr/bin/env bash
    # pipefail: a failing suite must fail the recipe instead of hiding behind grep's exit 0.
    set -uo pipefail
    swift test 2>&1 | grep -E "error|✘|Test run"

# The overlay's real mouse and key handlers, driven by made-up events in a window that is never shown.
selftest:
    swift run -q IgSnap --self-test

# Format every Swift file in place to the house style (.swift-format).
fmt:
    swift format format -i -r Sources Tests Package.swift

# Draw the overlay mid-edit to a PNG, off screen: a look at the UI with no permission and no window.
demo out="build/demo.png":
    mkdir -p build
    swift run -q IgSnap --render-demo "{{out}}"
    @echo "{{out}}"

# Build a release binary and wrap it into a signed app bundle.
app:
    #!/usr/bin/env bash
    set -euo pipefail
    swift build -c release 2>&1 | grep -E "error|Build complete"
    rm -rf "{{app}}"
    mkdir -p "{{app}}/Contents/MacOS"
    cp "$(swift build -c release --show-bin-path)/IgSnap" "{{app}}/Contents/MacOS/"
    cp Support/Info.plist "{{app}}/Contents/"
    # Signed with the Mac's Apple Development identity, so the app's designated requirement is the same every
    # build and macOS keeps the Screen Recording grant across rebuilds. Ad-hoc signing gets a new hash, and a new
    # prompt, each build. IGSNAP_SIGN_IDENTITY picks another identity.
    id="${IGSNAP_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')}"
    [ -n "$id" ] || echo "warning: no Apple Development identity: ad-hoc signing, so macOS asks for Screen Recording again" >&2
    codesign --force --sign "${id:--}" "{{app}}"

# Build and take a screenshot.
run: app
    open "{{app}}"

# Copy the app into /Applications, where launchers find it.
install: app
    rm -rf "{{installed}}"
    cp -R "{{app}}" "{{installed}}"
