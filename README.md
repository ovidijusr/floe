# Floe

A minimal menu bar icon hider for **macOS 27**.

Pick which menu bar icons to hide; click Floe's chevron to bring them back into the real menu bar, click again (or wait) to hide them.

Ice's classic mechanism (10,000-pt spacer status items + synthetic ⌘-drag events) stopped working on macOS 27, where the menu bar became a single unified window. Floe uses the approach pioneered by [Thaw](https://github.com/stonerl/Thaw)'s macOS 27 work instead:

- **Enumeration** through the Accessibility tree (`AXExtrasMenuBar`)
- **Hiding** via the private `MenuBarClientCore` assessment-mode visibility assertion (bundle-ID allowlist), with a surgical CGS window off-screen move where per-item windows are still resolvable
- **Reveal** = drop the assertion / restore window origins — icons reappear in the actual menu bar

## Requirements

- macOS 27.0 or later
- Accessibility permission (prompted on first launch). No Screen Recording needed.

## Limitations

- Hiding is per-app: hiding any of an app's items hides all of them.
- Built on private API; a macOS update can break it (gracefully — Floe becomes inert, nothing stays lost).

## Building

```sh
xcodegen
xcodebuild -project Floe.xcodeproj -scheme Floe -configuration Release build
```

## License & credits

GPL-3.0. Contains code ported from [Ice](https://github.com/jordanbaird/Ice) (© Jordan Baird) and [Thaw](https://github.com/stonerl/Thaw) (© Toni Förster), both GPL-3.0.
