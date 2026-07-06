//
//  MenuBarClickMonitor.swift
//  Project: Floe
//  Licensed under the GNU GPLv3
//

import AXSwift
import Cocoa

/// Watches for clicks on the empty region of the menu bar (the gap between the
/// frontmost app's menus and the leftmost status item) and toggles the hidden
/// section, so the whole bar behaves like Floe's own icon.
///
/// The monitor is passive: an empty menu-bar click does nothing by default, so
/// observing it (without consuming) is safe. All geometry stays in Cocoa
/// coordinates — only the Y axis differs from the CG frames our enumeration
/// produces, and we compare X (identical in both) for the horizontal gap and
/// use each screen's own menu-bar strip for the vertical test.
@MainActor
final class MenuBarClickMonitor {
    private let engine: HideEngine
    private let diagLog = DiagLog(category: "MenuBarClickMonitor")
    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// Invoked when the user right-clicks the empty menu bar; the argument is a
    /// Cocoa screen point where the controls menu should appear.
    var onRequestMenu: ((NSPoint) -> Void)?

    init(engine: HideEngine) {
        self.engine = engine
    }

    var isEnabled: Bool {
        get { globalMonitor != nil }
        set { newValue ? start() : stop() }
    }

    private func start() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleClick(rightButton: event.type == .rightMouseDown) }
        }
        // Local monitor covers the rare case where Floe itself is the active app.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleClick(rightButton: event.type == .rightMouseDown) }
            return event
        }
    }

    private func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    /// Everything here is computed in CG (top-left) coordinates, anchored to the
    /// display that hosts the app menus + status items, so the gap is coherent
    /// even with multiple displays each drawing their own menu bar.
    private func handleClick(rightButton: Bool) {
        // A right-click in the gap only matters if it will open the menu; skip
        // the AX walk otherwise. Left-clicks toggle only when that's enabled.
        if rightButton {
            guard onRequestMenu != nil else { return }
        } else {
            guard engine.toggleOnEmptyClick else { return }
        }

        // The frontmost app's menu bar frame (CG coords) locates the app-menu
        // display and its right edge. Without it there's no reliable gap.
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let app = AXHelpers.application(for: frontApp),
              let menuBar = try? app.attribute(.menuBar) as UIElement?,
              let menuFrame = AXHelpers.frame(for: menuBar)
        else {
            return
        }

        let click = mouseLocationInCG()

        // Vertical: click must be within the menu bar strip (its y-band).
        guard click.y >= menuFrame.minY, click.y <= menuFrame.maxY else { return }

        // Refresh item positions so the gap reflects the current bar (cheap
        // enough for a rare menu-bar click; only after the vertical test).
        engine.refreshItems()

        // AXMenuBar's own frame spans the whole width; the app-menus extent is
        // the union of its children (Apple menu, app name, File, Edit, …).
        let appMenusMaxX = AXHelpers.children(for: menuBar)
            .compactMap { AXHelpers.frame(for: $0)?.maxX }
            .max() ?? menuFrame.minX

        // Status items sharing the menu bar's y-band.
        let yBand = menuFrame.minY ... menuFrame.maxY
        let statusMinX = engine.items
            .filter { yBand.contains($0.frame.midY) && $0.frame.minX >= appMenusMaxX }
            .map(\.frame.minX)
            .min()

        let leftBound = appMenusMaxX + 8 // just past the last app menu
        let rightBound = statusMinX ?? menuFrame.maxX // display right edge fallback
        let inGap = click.x > leftBound && click.x < rightBound
        diagLog.debug("click x=\(click.x) y=\(click.y) yBand=\(menuFrame.minY)...\(menuFrame.maxY) gap=[\(leftBound),\(rightBound)] inGap=\(inGap)")
        guard inGap else { return }

        if rightButton {
            diagLog.debug("empty menu-bar right-click → menu")
            onRequestMenu?(NSEvent.mouseLocation)
        } else {
            diagLog.debug("empty menu-bar click → toggle")
            engine.toggleReveal()
        }
    }

    /// Converts the current cursor location from Cocoa (bottom-left origin of the
    /// primary screen) to CG (top-left) coordinates, matching AX/item frames.
    private func mouseLocationInCG() -> CGPoint {
        let cocoa = NSEvent.mouseLocation
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: cocoa.x, y: primaryTop - cocoa.y)
    }
}
