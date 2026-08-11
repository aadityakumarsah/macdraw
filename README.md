# macdraw

Draw, annotate and laser-point directly on your screen — over any app, in seconds. A lightweight macOS overlay app written in Swift + AppKit.

![macOS](https://img.shields.io/badge/macOS-13+-black) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-blue) ![Size](https://img.shields.io/badge/size-1MB-lightgrey)

## What it does

macdraw is a full-screen transparent overlay that captures your clicks so you can write on top of whatever is on screen — presentations, videos, code, anything.

- **17 drawing tools** — rectangle, diamond, ellipse, arrow, line, freehand sketch, magic shape, frame, text, image, eraser, lasso, laser, fill and more
- **Glowing laser pointer** — neon glow that fades tail-first, leaves no marks
- **White / black screen** — flip the whole display to a clean writing surface
- **Full color palette** — stroke & fill colors, stroke width, dashed strokes
- **Real text** — type anywhere, pick a font family and size, re-edit anytime
- **Images & emoji** — drop pictures, or press `/` for a quick emoji palette
- **Selection editing** — move, resize, rotate, lasso-select, delete, undo
- **Autosave** — your drawing persists across quits and relaunches
- **Keyboard-first** — every tool has a one-key shortcut

## Install

### Via the website

Download the DMG or zip from [the macdraw site](https://github.com/aadityakumarsah/macdraw-site) and drag to Applications. First launch: right-click → Open → Open (Gatekeeper is cautious about free unsigned apps).

### Build from source

```bash
git clone https://github.com/aadityakumarsah/macdraw.git
cd macdraw
bash scripts/make_signing_identity.sh   # one-time: creates the self-signed signing cert
bash build.sh          # builds build/macdraw.app
bash dist.sh           # signs it + packages DMG & zip into dist/
open build/macdraw.app
```

Requires Xcode Command Line Tools (`xcode-select --install`) on macOS 13+ and Homebrew OpenSSL 3 for the signing identity (`brew install openssl@3`).

> **Why self-signed?** macOS 15+ refuses to run unsigned apps, and ad-hoc signed apps show a scary "damaged — move to bin" dialog after download. A self-signed signature is cryptographically valid but not Apple-trusted, so Gatekeeper shows the standard "unidentified developer" prompt instead — right-click → Open (once) and it runs. No Apple Developer account needed.

## Usage

Press **⌃⌥** (Control+Option) to open the overlay, then start drawing. Click the **Draw** button in the toolbar to capture clicks; click it again to pause and interact with apps below. Press ⌃⌥ again (or the ✕ button) to close.

### Shortcuts

| Tool | Key | Tool | Key |
|---|---|---|---|
| Select | `V` | Lasso | `S` |
| Pan | `H` | Laser | `Z` |
| Rectangle | `R` | Fill | `B` |
| Diamond | `Y` | Undo | `⌘Z` |
| Ellipse | `O` | Select all | `⌘A` |
| Arrow | `A` | Delete selection | `⌫` |
| Line | `L` | Close overlay | `⌃⌥` |
| Sketch | `D` | Emoji palette | `/` |
| Text | `T` | Pause drawing | Draw button |

Press `Esc` to exit text editing or clear the selection.

## Architecture

- `Sources/AppDelegate.swift` — app lifecycle, status bar item
- `Sources/CanvasView.swift` — the drawing surface: tools, selection, undo, laser, persistence
- `Sources/IslandManager.swift` — borderless overlay window & "dynamic island" pill animation
- `Sources/ToolbarView.swift` — SwiftUI toolbar with tools, palette, background mode, shortcuts panel
- `Sources/SVGIconRenderer.swift` — renders tool icons from SVG path data (no external deps)
- `Sources/Model.swift` — tools, shapes, annotations, shortcuts
- `Resources/` — fonts, tool icons, app icon

No third-party dependencies — pure AppKit/SwiftUI.

## License

MIT
