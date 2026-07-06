//
//  StatusItemController.swift
//  Project: Floe
//  Licensed under the GNU GPLv3
//

import Cocoa
import Combine
import ServiceManagement

/// Floe's own menu bar icon: left-click toggles the hidden items back into the
/// real menu bar; right-click opens the menu.
@MainActor
final class StatusItemController: NSObject {
    private static let autosaveName = "Floe.ControlItem"

    private let engine: HideEngine
    private let openSettings: () -> Void
    private let statusItem: NSStatusItem
    private var cancellable: AnyCancellable?

    init(engine: HideEngine, openSettings: @escaping () -> Void) {
        self.engine = engine
        self.openSettings = openSettings
        // Clear any stale VisibleCC=0 a previous session's assertion reflow left
        // behind, so the item is not suppressed before the first reassert.
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "NSStatusItem Visible \(Self.autosaveName)")
        defaults.set(true, forKey: "NSStatusItem VisibleCC \(Self.autosaveName)")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Stable autosave name so the NSStatusItem visibility defaults MenuBarAgent
        // writes are keyed predictably and can be forced back on (see reassertVisibility).
        statusItem.autosaveName = Self.autosaveName
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityIdentifier("lt.ovi.floe.statusItem")
        }
        updateIcon(revealed: engine.isRevealed)
        cancellable = engine.$isRevealed.sink { [weak self] revealed in
            self?.updateIcon(revealed: revealed)
        }
    }

    /// Forces Floe's own status item back on after the assessment-mode assertion
    /// reflows the menu bar. MenuBarAgent zeroes the item's persisted
    /// `NSStatusItem Visible`/`VisibleCC` defaults during the reflow, which would
    /// otherwise suppress the item permanently. Reset both, re-show, and refresh
    /// the length/image so Floe stays reachable while other items are hidden.
    func reassertVisibility() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "NSStatusItem Visible \(Self.autosaveName)")
        defaults.set(true, forKey: "NSStatusItem VisibleCC \(Self.autosaveName)")
        statusItem.isVisible = true
        statusItem.length = NSStatusItem.squareLength
        updateIcon(revealed: engine.isRevealed)
    }

    private func updateIcon(revealed: Bool) {
        let symbol = revealed ? "chevron.forward" : "chevron.backward"
        let description = revealed ? "Hide menu bar items" : "Show hidden menu bar items"
        statusItem.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: description
        )
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            engine.toggleReveal()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(settingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Floe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        // Assigning the menu and clicking programmatically shows it at the
        // status item; clearing it afterwards keeps left-click as a plain
        // action instead of always opening the menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func settingsAction() {
        openSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Launch at Login toggle failed: \(error)")
        }
    }
}
