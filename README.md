<p align="center"><img src="docs/icon.png" width="128" alt="Petal icon"></p>

<h1 align="center">Petal</h1>

<p align="center">Name and color your Mac Desktops from the menu bar. Now in beta.</p>

<p align="center">
  <a href="https://daisy-technology.github.io/petal/">Website</a> ·
  <a href="https://github.com/daisy-technology/petal/releases/download/v0.1.0-beta.1/Petal.zip">Download</a> ·
  <a href="https://github.com/daisy-technology/petal/actions/workflows/ci.yml"><img src="https://github.com/daisy-technology/petal/actions/workflows/ci.yml/badge.svg?branch=dev" alt="CI"></a>
</p>

macOS calls every Space "Desktop 1", "Desktop 2" and gives you no way to rename them. Petal keeps a name and a color for each Desktop and shows the one you're on in the menu bar. Click the flower to see every Desktop on every display. In that list:

- click a Desktop to switch to it
- double-click to rename it
- press and hold to open Mission Control and drag the Desktop to a new place; Petal's list follows the real order
- click the dot to pick one of eight colors, or drag along the hue strip for any color

Petal also writes each Desktop's name in large, faint letters on its wallpaper, behind your windows. Mission Control keeps its own "Desktop 1, 2" labels, so while it's open Petal brings the name in front of the windows and you can see which Desktop is which, even one filled by a big app. A colored Desktop also gets a thin edge in that color. You can turn either one off in the menu, and a slider sets how big the name is. Hold the slider and the name comes in front of your windows so you see the size change as you drag. You can also pick how the name comes in (Fade, Zoom, Slide or None) and how long that takes; Petal plays it once each time you change either.

Petal needs no account and makes no network requests. Naming and colors need no permissions. The first time you click a Desktop to switch to it, Petal asks for Accessibility access: macOS has no API for switching Desktops, so Petal presses your Mission Control shortcut (Control-arrow, or Control-number if you've turned those on) for you. Because Petal isn't notarized yet, macOS may ask you to allow it again after an update.

## Install

Download [Petal.zip](https://github.com/daisy-technology/petal/releases/download/v0.1.0-beta.1/Petal.zip), unzip it and move Petal to Applications. This is a beta: please [report anything odd](https://github.com/daisy-technology/petal/issues). It runs on macOS 14 or later, on Apple silicon and Intel.

Petal isn't notarized yet, so macOS blocks the first launch. Open it once, then go to System Settings → Privacy & Security and click Open Anyway. You can also clear the quarantine flag in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/Petal.app
```

## What it can't do

The labels under each Desktop in Mission Control stay "Desktop 1, 2, 3". The Dock draws them, and changing them means injecting code into the Dock with System Integrity Protection partly turned off. Petal won't go there. For the same reason Petal can't move a Desktop by itself: holding a row opens Mission Control, you drag the Desktop there, and Petal's list follows.

Petal reads Spaces through the same private SkyLight calls that WhichSpace and Spaceman use, because macOS has no public API for them. A future macOS update could break that. If it does, Petal shows "Desktop" in the menu bar and keeps your saved names.

Names on the wallpaper and colored edges are created the first time you visit a Desktop after Petal starts, so a Desktop you haven't opened since login doesn't show them in Mission Control yet.

## Build from source

You need Xcode 15 or later.

```sh
swift test                 # run the tests
scripts/package.sh 0.1.0   # build dist/Petal.app and dist/Petal.zip (universal)
open dist/Petal.app
```

`brand/petal.svg` is the logo. After changing it, run `swift scripts/make-icon.swift` to regenerate `Resources/AppIcon.icns` and `docs/icon.png`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the branch and release workflow.

## Windows and Linux

Mac only for now. Windows and Linux versions are planned.

## License

MIT © 2026 [Daisy Technology](https://www.daisytechs.com/). If Petal saves you some clicks, you can [sponsor its development](https://github.com/sponsors/daisy-technology).
