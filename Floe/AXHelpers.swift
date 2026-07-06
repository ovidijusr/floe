//
//  AXHelpers.swift
//  Project: Floe
//
//  Ported from Thaw (Shared/Utilities/AXHelpers.swift), trimmed to the
//  enumeration path.
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

@preconcurrency import AXSwift
import Cocoa

enum AXHelpers {
    private static let queue = DispatchQueue(
        label: "AXHelpers.queue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    @discardableResult
    static func isProcessTrusted(prompt: Bool = false) -> Bool {
        queue.sync { checkIsProcessTrusted(prompt: prompt) }
    }

    static func application(for runningApp: NSRunningApplication) -> Application? {
        queue.sync {
            let app = Application(runningApp)
            // Bound every AX round trip to this app. Without a timeout,
            // AXUIElementCopyAttributeValue blocks on mach_msg until the target
            // app's accessibility server replies — an unresponsive app would
            // otherwise stall menu bar enumeration indefinitely.
            if let app {
                AXUIElementSetMessagingTimeout(app.element, 0.25)
            }
            return app
        }
    }

    static func extrasMenuBar(for app: Application) -> UIElement? {
        queue.sync { try? app.attribute(.extrasMenuBar) }
    }

    static func children(for element: UIElement) -> [UIElement] {
        queue.sync { try? element.arrayAttribute(.children) } ?? []
    }

    static func frame(for element: UIElement) -> CGRect? {
        queue.sync { try? element.attribute(.frame) }
    }

    /// The element's `AXTitle`, when present. On macOS 27 most menu bar
    /// item elements leave this empty, so callers fall back to ``identifier``.
    static func title(for element: UIElement) -> String? {
        queue.sync { try? element.attribute(.title) }
    }

    /// The element's `AXIdentifier`, when present.
    static func identifier(for element: UIElement) -> String? {
        queue.sync { try? element.attribute(.identifier) }
    }

    /// The element's accessibility description. Some status-item apps expose
    /// a stable semantic label here while `AXTitle` contains live metric text.
    static func description(for element: UIElement) -> String? {
        queue.sync { try? element.attribute(.description) }
    }

    static func pid(for element: UIElement) -> pid_t? {
        queue.sync {
            var pid: pid_t = 0
            let result = AXUIElementGetPid(element.element, &pid)
            return result == .success ? pid : nil
        }
    }
}
