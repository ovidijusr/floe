<h1 align="center">Floe</h1>

<p align="center">A tiny, native menu bar tidier for <b>macOS 27</b>.<br>
Hide the icons you don't need — click to get them back.</p>

<p align="center">
  <img src="docs/floe-demo.gif" alt="Floe hiding and showing menu bar icons" width="720">
</p>

---

## What it does

Your menu bar fills up fast. Floe lets you pick which icons stay tucked away, then reveals them **in the real menu bar** whenever you want:

- **Click Floe's chevron** (`‹`), or
- **Click any empty spot on the menu bar**

Click again — or let it auto-hide after a few seconds — and they slide back out of sight. That's the whole app. No profiles, no styling, no subscription.

## Why Floe exists

The much-loved [Ice](https://github.com/jordanbaird/Ice) stopped working on macOS 27: Apple rebuilt the menu bar as a single window, so Ice's old trick of stretching a spacer to push icons offscreen no longer does anything (see [Ice #954](https://github.com/jordanbaird/Ice/issues/954)).

Floe uses the approach worked out by the actively-maintained Ice fork [Thaw](https://github.com/stonerl/Thaw):

1. It reads your menu bar through **Accessibility**.
2. It hides icons with the system's own private menu-bar visibility mechanism (`MenuBarClientCore`), the same one Apple uses internally.
3. Revealing just drops that restriction, so icons reappear exactly where they were.

No screen recording, no background CPU churn, and if a future macOS ever changes the mechanism, Floe simply goes inert and reveals everything — nothing gets stranded.

## Install

1. Download **`Floe-<version>-macos-arm64.app.zip`** from the [latest release](https://github.com/ovidijusr/floe/releases/latest).
2. Unzip and move **Floe.app** to `/Applications`.
3. Launch it. When prompted, grant **Accessibility** access (System Settings → Privacy & Security → Accessibility) and turn **Floe** on. You only do this once.

Requirements: macOS 27, Apple Silicon. The app is signed with a Developer ID and notarized by Apple.

## Using it

- Open **Settings** from Floe's menu bar icon (right-click → Settings, or the chevron's menu).
- Flip on the apps and system icons you want hidden.
- Reveal them anytime by clicking the chevron or the empty menu bar; hide again the same way.
- Optionally set an **auto-rehide** delay, or turn off click-to-toggle, in Settings.

## Troubleshooting

**"It keeps asking for Accessibility even though I granted it."**
macOS ties the grant to an app's exact code signature. If you ran more than one build of Floe (e.g. an old copy and a new one), each counts as a different app. Fix it once:

```sh
tccutil reset Accessibility lt.ovi.floe
```

Then launch only the copy in `/Applications` and grant it. Future updates keep the grant.

**"Floe's own icon disappeared / I can't find it."**
Quitting Floe always reveals everything. If it's not visible to quit:

```sh
pkill -x Floe
```

Every hidden icon comes right back.

## Building from source

```sh
brew install xcodegen
xcodegen
xcodebuild -project Floe.xcodeproj -scheme Floe -configuration Release build
```

## Credits & license

GPL-3.0. Floe stands on the shoulders of [Ice](https://github.com/jordanbaird/Ice) (© Jordan Baird) and [Thaw](https://github.com/stonerl/Thaw) (© Toni Förster), whose macOS 27 reverse-engineering made the hiding mechanism possible.
