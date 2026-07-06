//
//  MenuBarItems.swift
//  Project: Floe
//
//  AX enumeration ported from Thaw (MenuBarItemAXProvider.swift), with Thaw's
//  tag/layout machinery replaced by a flat per-app model.
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Cocoa

/// A single status item observed in the menu bar.
struct MenuBarItem: Hashable, Identifiable {
    let ownerPID: pid_t
    /// Bundle ID of the app that published the item (nil for unbundled).
    let ownerBundleID: String?
    /// Human-readable name of the owning app.
    let ownerName: String
    let title: String
    let frame: CGRect

    var id: String { "\(ownerBundleID ?? ownerName):\(title):\(Int(frame.minX))" }

    /// The `MBSystemItemIdentifier` raw value if this is one of the Apple
    /// system items the assessment-mode restriction can conceal individually.
    var systemItemID: Int? {
        SystemItems.identifier(forTitle: title)
    }

    /// Whether the item is hosted by an Apple system process whose bundle must
    /// never be concealed as a whole.
    var isSystemHosted: Bool {
        guard let ownerBundleID else { return false }
        return SystemItems.hostBundleIDs.contains(ownerBundleID)
    }
}

/// Knowledge about Apple's private `MBSystemItemIdentifier` enum (9 cases,
/// raw values 0...8), probed by the Thaw project on 2026-06-18. Widening past
/// 8 maps to nothing, and an empty allowlist hides ALL system items.
enum SystemItems {
    static let all: Set<Int> = Set(0 ... 8)

    /// Bundles that host system menu extras. Concealing these hosts at the
    /// bundle level would blank every item they own (the whole system side of
    /// the bar); system items are concealed via their index instead.
    static let hostBundleIDs: Set<String> = [
        "com.apple.MenuBarAgent",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
    ]

    static func identifier(forTitle title: String) -> Int? {
        switch title {
        case "Battery":
            return 0
        case "Bluetooth", "com.apple.menuextra.bluetooth":
            return 1
        case "Clock", "com.apple.menuextra.clock":
            return 2
        case "Displays", "Display", "com.apple.menuextra.displays":
            return 3
        case "Keyboard", "com.apple.menuextra.keyboard":
            return 4
        case "Sound", "Volume", "com.apple.menuextra.volume":
            return 5
        case "WiFi", "Wi-Fi", "com.apple.menuextra.wifi":
            return 6
        case "ScreenMirroring", "Screen Mirroring", "com.apple.menuextra.screenmirroring":
            return 7
        case "BentoBox-0", "ControlCenter", "com.apple.menuextra.controlcenter":
            return 8
        default:
            return nil
        }
    }

    static func displayName(for identifier: Int) -> String {
        switch identifier {
        case 0: "Battery"
        case 1: "Bluetooth"
        case 2: "Clock"
        case 3: "Displays"
        case 4: "Keyboard"
        case 5: "Sound"
        case 6: "Wi-Fi"
        case 7: "Screen Mirroring"
        case 8: "Control Center"
        default: "System Item \(identifier)"
        }
    }
}

/// Enumerates menu bar items through the Accessibility tree.
///
/// macOS 27 (Golden Gate) retired the WindowServer mechanism menu bar managers
/// relied on for every prior release: `CGSGetProcessMenuBarWindowList` no
/// longer returns individual status-item windows, and the `MenuBarAgent` XPC
/// interface that does expose items is gated behind Apple-private
/// entitlements. AX is the only mechanism still available to a third-party
/// app, and it attributes directly: every app publishes its status items under
/// its own application element's `AXExtrasMenuBar`; system items are published
/// by `MenuBarAgent` itself.
enum MenuBarItemEnumerator {
    private static let diagLog = DiagLog(category: "MenuBarItemEnumerator")

    /// The maximum height an extras-bar child may have to be considered a menu
    /// bar status item. Real items match the menu bar height (~24–30 pt);
    /// larger children are incidental (open popovers, panels).
    private static let maxItemHeight: CGFloat = 40

    /// macOS 27's native menu-bar overflow control can appear in AX as a
    /// MenuBarAgent extra. It is a system placeholder, not a status item.
    private static let overflowChevronGlyphs = Set("<>‹›«»")

    static func items() -> [MenuBarItem] {
        guard AXHelpers.isProcessTrusted() else {
            diagLog.warning("items: accessibility permission missing; cannot enumerate")
            return []
        }

        var items: [MenuBarItem] = []

        for runningApp in NSWorkspace.shared.runningApplications {
            guard let app = AXHelpers.application(for: runningApp) else { continue }
            guard let bar = AXHelpers.extrasMenuBar(for: app) else { continue }

            let children = AXHelpers.children(for: bar)
            guard !children.isEmpty else { continue }

            let bundleID = runningApp.bundleIdentifier
            let ownerName = runningApp.localizedName ?? bundleID ?? "pid \(runningApp.processIdentifier)"
            var fallbackIndex = 0

            for child in children {
                guard let frame = AXHelpers.frame(for: child) else { continue }
                // Skip incidental children (open popovers / panels).
                guard frame.height > 0, frame.height <= maxItemHeight else { continue }

                // Some apps publish identity attributes on the status-bar
                // button rather than its container, so scan one level deeper.
                let identifier = AXHelpers.identifier(for: child)?.nonEmpty
                    ?? AXHelpers.children(for: child)
                    .lazy
                    .compactMap { AXHelpers.identifier(for: $0)?.nonEmpty }
                    .first
                let description = AXHelpers.description(for: child)?.nonEmpty
                    ?? AXHelpers.children(for: child)
                    .lazy
                    .compactMap { AXHelpers.description(for: $0)?.nonEmpty }
                    .first
                let axTitle = AXHelpers.title(for: child)?.nonEmpty
                let title = axTitle ?? description ?? identifier ?? "Item-\(fallbackIndex)"
                if axTitle == nil, description == nil, identifier == nil {
                    fallbackIndex += 1
                }

                if bundleID == "com.apple.MenuBarAgent", isOverflowChevron(title) {
                    continue
                }

                let ownerPID = AXHelpers.pid(for: child) ?? runningApp.processIdentifier
                items.append(
                    MenuBarItem(
                        ownerPID: ownerPID,
                        ownerBundleID: bundleID,
                        ownerName: ownerName,
                        title: title,
                        frame: frame
                    )
                )
            }
        }

        items.sort { $0.frame.minX < $1.frame.minX }
        diagLog.debug("items: enumerated \(items.count) menu bar items via AX")
        return items
    }

    private static func isOverflowChevron(_ title: String) -> Bool {
        let glyphs = title.filter { !$0.isWhitespace }
        guard !glyphs.isEmpty, glyphs.count <= 4 else { return false }
        return glyphs.allSatisfy { overflowChevronGlyphs.contains($0) }
    }
}

private extension String {
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
