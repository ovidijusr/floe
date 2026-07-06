//
//  FloeApp.swift
//  Project: Floe
//  Licensed under the GNU GPLv3
//

import AXSwift
import Cocoa
import SwiftUI

@main
struct FloeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar-only app; the settings window is managed by AppDelegate so
        // it can be opened reliably from the status item menu.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = HideEngine()
    private var statusItemController: StatusItemController?
    private var clickMonitor: MenuBarClickMonitor?
    private var settingsWindow: NSWindow?
    private var permissionPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController(engine: engine) { [weak self] in
            self?.showSettingsWindow()
        }
        statusItemController = controller
        engine.onAssertionApplied = { [weak controller] in
            controller?.reassertVisibility()
        }

        let monitor = MenuBarClickMonitor(engine: engine)
        clickMonitor = monitor
        monitor.onRequestMenu = { [weak controller] point in
            controller?.showContextMenu(at: point)
        }
        engine.onToggleOnEmptyClickChanged = { [weak self] _ in self?.updateClickMonitor() }
        engine.onHideOwnIconChanged = { [weak self, weak controller] hidden in
            controller?.setIconHidden(hidden)
            self?.updateClickMonitor()
        }
        updateClickMonitor()

        // Prompting via AXIsProcessTrustedWithOptions auto-registers Floe in
        // System Settings → Privacy & Security → Accessibility.
        if AXHelpers.isProcessTrusted(prompt: true) {
            engine.start()
        } else {
            showSettingsWindow()
            permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, AXHelpers.isProcessTrusted() else { return }
                    self.permissionPollTimer?.invalidate()
                    self.permissionPollTimer = nil
                    self.engine.start()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Reveal everything on the way out so no item stays hidden without
        // Floe running to bring it back. CGSWindowHider also restores via its
        // own willTerminate observer; this covers the assertion.
        engine.setRevealed(true)
    }

    /// The click monitor is needed for empty-click toggling and/or reaching the
    /// controls menu when Floe's own icon is hidden.
    private func updateClickMonitor() {
        clickMonitor?.isEnabled = engine.toggleOnEmptyClick || engine.hideOwnIcon
    }

    private func showSettingsWindow() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(engine: engine))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Floe"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
