//
//  CGSWindowHider.swift
//  Project: Floe
//
//  Ported from Thaw (CGSWindowHider.swift).
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Cocoa

/// Hides menu-bar items by moving their windows off-screen via private CGS
/// APIs — a per-window, surgical hide that never re-composites the whole menu
/// bar.
///
/// This is a *complement* to ``AssessmentModeBackend``, not a replacement. The
/// assessment-mode assertion is the right tool for Apple system items, but
/// every (re)activation reflows the entire bar. Moving a *third-party* item's
/// own window off-screen instead touches only that window.
///
/// macOS 27 carries *synthetic* per-item window IDs internally, so this
/// resolves each owning process to its real menu-bar window IDs via
/// ``Bridging/getMenuBarWindowIDs(forProcess:)`` at apply time.
///
/// Safety: every moved window's original origin is remembered and restored
/// when the process leaves the hidden set, and ``restoreAll()`` runs on app
/// termination so a hide never outlives Floe (a stranded status item would
/// otherwise sit invisibly off-screen until its app relaunched).
@MainActor
final class CGSWindowHider {
    /// X coordinate far outside any plausible display arrangement. Items moved
    /// here are off every screen but still valid windows we can move back.
    static let offScreenX: CGFloat = -30000

    private let diagLog = DiagLog(category: "CGSWindowHider")

    /// Original origin of every window this hider has moved off-screen, keyed
    /// by real window ID. Presence == "currently hidden by us".
    private var hiddenOrigins: [CGWindowID: CGPoint] = [:]

    private var terminationObserver: NSObjectProtocol?

    init(notificationCenter: NotificationCenter = .default) {
        terminationObserver = notificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreAll() }
        }
    }

    /// Drives the off-screen hide to match `hiddenPIDs`: every menu-bar window
    /// of a listed process is moved off-screen, and any window we previously
    /// hid for a process no longer listed is restored. Safe to call every
    /// refresh tick — it re-applies the off-screen move to windows the system
    /// may have reflowed back on-screen, and is a no-op once settled.
    ///
    /// - Returns: The subset of `hiddenPIDs` for which at least one window was
    ///   resolved and handled. Callers should only strip these PIDs from the
    ///   assertion input; PIDs that had no windows (items drawn into shared
    ///   hosting windows) must fall back to the assertion.
    @discardableResult
    func apply(hiddenPIDs: Set<pid_t>) -> Set<pid_t> {
        // Resolve the live windows that should be hidden right now.
        var desiredHidden = Set<CGWindowID>()
        var handledPIDs = Set<pid_t>()
        for pid in hiddenPIDs {
            let wids = Bridging.getMenuBarWindowIDs(forProcess: pid)
            if !wids.isEmpty {
                handledPIDs.insert(pid)
                desiredHidden.formUnion(wids)
            }
        }

        // Restore windows that should no longer be hidden.
        for (windowID, origin) in hiddenOrigins where !desiredHidden.contains(windowID) {
            Bridging.moveWindow(windowID, to: origin)
            hiddenOrigins.removeValue(forKey: windowID)
        }

        // Hide (or re-hide after a reflow) every desired window.
        for windowID in desiredHidden {
            if hiddenOrigins[windowID] == nil {
                // First time hiding this window — remember where it lives so it
                // can be restored exactly. Skip if we can't read its origin
                // (don't move a window we can't put back).
                guard let origin = Bridging.getWindowBounds(for: windowID)?.origin else {
                    diagLog.error("Skipping hide of window \(windowID); origin unavailable")
                    continue
                }
                hiddenOrigins[windowID] = origin
            }
            let target = CGPoint(x: Self.offScreenX, y: hiddenOrigins[windowID]?.y ?? 0)
            Bridging.moveWindow(windowID, to: target)
        }

        return handledPIDs
    }

    /// Restores every window this hider has moved, used on teardown so no item
    /// is left stranded off-screen.
    func restoreAll() {
        guard !hiddenOrigins.isEmpty else { return }
        for (windowID, origin) in hiddenOrigins {
            Bridging.moveWindow(windowID, to: origin)
        }
        diagLog.info("restoreAll: restored \(hiddenOrigins.count) window(s)")
        hiddenOrigins.removeAll()
    }
}
