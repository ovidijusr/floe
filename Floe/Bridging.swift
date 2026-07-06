//
//  Bridging.swift
//  Project: Floe
//
//  Ported from Thaw (Shared/Bridging/Bridging.swift), trimmed to the window
//  resolution and movement paths used by the CGS off-screen hider.
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Cocoa

enum Bridging {
    private static let diagLog = DiagLog(category: "Bridging")

    private static func connection() -> CGSConnectionID {
        cgsDefaultConnectionForThread()
    }

    /// Returns the bounds for the given window.
    static func getWindowBounds(for windowID: CGWindowID) -> CGRect? {
        var bounds = CGRect.zero
        let result = cgsGetScreenRectForWindow(connection(), windowID, &bounds)
        guard result == .success else {
            diagLog.error("cgsGetScreenRectForWindow failed with error \(result.logString)")
            return nil
        }
        return bounds
    }

    /// Returns the real `CGWindowID`s of a process's menu-bar item windows.
    ///
    /// On macOS 27 per-item identifiers are synthetic, not real window IDs, so
    /// the CGS off-screen hider resolves a running process to its actual
    /// menu-bar window IDs via its CGS connection. Returns an empty array if
    /// the process has no menu-bar windows or the connection cannot be
    /// resolved.
    static func getMenuBarWindowIDs(forProcess pid: pid_t) -> [CGWindowID] {
        var psn = ProcessSerialNumber()
        guard getProcessForPID(pid, &psn) == noErr else {
            diagLog.debug("getMenuBarWindowIDs: pid \(pid) → no PSN")
            return []
        }
        let cid = connection()
        var targetCID: CGSConnectionID = 0
        guard cgsGetConnectionIDForPSN(cid, &psn, &targetCID) == .success, targetCID != 0 else {
            diagLog.debug("getMenuBarWindowIDs: pid \(pid) → cgsGetConnectionIDForPSN failed")
            return []
        }
        var count: Int32 = 0
        guard cgsGetWindowCount(cid, targetCID, &count) == .success, count > 0 else {
            return []
        }
        var list = [CGWindowID](repeating: 0, count: Int(count))
        var outCount: Int32 = 0
        let result = list.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else {
                return CGError.failure
            }
            return cgsGetProcessMenuBarWindowList(cid, targetCID, count, base, &outCount)
        }
        guard result == .success else {
            diagLog.error("cgsGetProcessMenuBarWindowList failed for pid \(pid): \(result.logString)")
            return []
        }

        // On macOS 27 the menu bar is rendered into shared hosting windows
        // (one per display), not per-item windows; those hosting windows are
        // returned for every process and must be filtered out — moving one
        // off-screen collapses the entire bar. Hosting windows are full display
        // width; real per-item windows are at most a few hundred points wide.
        return list.prefix(Int(outCount)).filter { wid in
            guard let bounds = getWindowBounds(for: wid) else { return false }
            return bounds.width <= 1000
        }
    }

    /// Moves a window's top-left origin in global display coordinates. Returns
    /// whether the move succeeded.
    @discardableResult
    static func moveWindow(_ windowID: CGWindowID, to origin: CGPoint) -> Bool {
        var point = origin
        let result = cgsMoveWindow(connection(), windowID, &point)
        guard result == .success else {
            diagLog.error("cgsMoveWindow failed for window \(windowID): \(result.logString)")
            return false
        }
        return true
    }
}
