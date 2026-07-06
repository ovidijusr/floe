//
//  CGSShims.swift
//  Project: Floe
//
//  Ported from Thaw (Shared/Bridging/Shims.swift), trimmed to the symbols the
//  CGS off-screen hider needs.
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import CoreGraphics
import Foundation

typealias CGSConnectionID = Int32

@_silgen_name("CGSMainConnectionID")
func cgsMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSDefaultConnectionForThread")
func cgsDefaultConnectionForThread() -> CGSConnectionID

@_silgen_name("CGSGetWindowCount")
func cgsGetWindowCount(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetProcessMenuBarWindowList")
func cgsGetProcessMenuBarWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetScreenRectForWindow")
func cgsGetScreenRectForWindow(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ outRect: inout CGRect
) -> CGError

/// Moves a window's top-left origin in global display coordinates. Used by the
/// CGS off-screen hider to push a status-item window outside every display's
/// bounds (and to restore it). Works cross-process via the default connection,
/// without requiring an assessment-mode reflow.
@_silgen_name("CGSMoveWindow")
func cgsMoveWindow(
    _ cid: CGSConnectionID,
    _ wid: CGWindowID,
    _ origin: inout CGPoint
) -> CGError

@_silgen_name("GetProcessForPID")
func getProcessForPID(
    _ pid: pid_t,
    _ psn: inout ProcessSerialNumber
) -> OSStatus

/// Resolves the CGS connection ID owning a process (identified by its PSN) so
/// its menu-bar item windows can be enumerated via
/// ``cgsGetProcessMenuBarWindowList``.
@_silgen_name("CGSGetConnectionIDForPSN")
func cgsGetConnectionIDForPSN(
    _ cid: CGSConnectionID,
    _ psn: inout ProcessSerialNumber,
    _ outTargetCID: inout CGSConnectionID
) -> CGError

extension CGError {
    var logString: String {
        "\(rawValue)"
    }
}
