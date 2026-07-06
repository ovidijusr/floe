//
//  DiagLog.swift
//  Project: Floe
//

import os

/// Thin wrapper over `os.Logger` matching the call sites ported from Thaw.
struct DiagLog: Sendable {
    private let logger: Logger

    init(category: String) {
        logger = Logger(subsystem: "lt.ovi.floe", category: category)
    }

    func debug(_ message: String) { logger.debug("\(message, privacy: .public)") }
    func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    func warning(_ message: String) { logger.warning("\(message, privacy: .public)") }
    func error(_ message: String) { logger.error("\(message, privacy: .public)") }
}
