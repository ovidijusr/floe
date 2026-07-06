//
//  AssessmentModeBackend.swift
//  Project: Floe
//
//  Ported from Thaw (AssessmentModeBackend.swift), simplified: Floe's hidden
//  set is chosen per-app by the user (stable bundle IDs), so Thaw's per-item
//  identity learning and anti-flap hysteresis are not needed here.
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

import Cocoa

/// macOS 27 menu bar item hiding via the private MenuBarClientCore
/// "Assessment Mode" visibility-restriction assertion.
///
/// The assertion is an **allowlist**: every menu bar item whose owner is not
/// listed is hidden and the bar reflows. Floe's model is a *deny* set (the
/// apps the user chose to hide), so this backend inverts it — allow every
/// running app except the hidden ones, and keep Apple system items visible
/// unless individually concealed by their `MBSystemItemIdentifier` index.
///
/// Granularity for third-party items is per owning app: the allowlist keys on
/// bundle identifiers, so hiding *any* item of an app hides *all* of that
/// app's items. When the private API is unavailable this backend is inert.
@MainActor
final class AssessmentModeBackend {
    /// Whether the private assertion API is present on this system.
    static var isAvailable: Bool {
        FloeAssessmentModeHidingAvailable()
    }

    private let diagLog = DiagLog(category: "AssessmentModeBackend")

    /// The live assertion handle, or `nil` when nothing is hidden.
    private var handle: UnsafeMutableRawPointer?

    /// The configuration baked into the currently-active assertion.
    private var appliedConcealed: Set<String> = []
    private var appliedAllowed: Set<String> = []
    private var appliedAllowedSystemItems = SystemItems.all

    /// Monotonic token identifying the most recent activation attempt. The
    /// assertion's failure callback fires asynchronously, by which point a
    /// newer activation may already be in effect; the callback compares
    /// against this to avoid tearing down a handle it didn't create.
    private var activationGeneration = 0

    /// The configuration whose activation most recently failed asynchronously.
    /// Not retried until the desired set genuinely changes (avoids hot-looping
    /// on periodic re-apply ticks).
    private var lastFailedConfiguration: (allowed: Set<String>, systemItems: Set<Int>)?

    /// Never conceal Floe itself — its own status item is the only way back.
    private var protectedBundleIDs: Set<String> {
        if let bundleID = Bundle.main.bundleIdentifier { [bundleID] } else { [] }
    }

    /// Applies (or re-applies) the restriction.
    ///
    /// - Parameters:
    ///   - concealedBundleIDs: Third-party app bundles whose items to hide.
    ///   - concealedSystemItemIDs: `MBSystemItemIdentifier` raw values to hide.
    ///   - knownHostBundleIDs: Every bundle observed hosting a menu bar item.
    ///     Force-included in the allowlist (unless concealed) to cover
    ///     sub-bundle hosts absent from `runningApplications`.
    /// - Returns: Whether a (re)activation happened.
    @discardableResult
    func apply(
        concealedBundleIDs: Set<String>,
        concealedSystemItemIDs: Set<Int>,
        knownHostBundleIDs: Set<String>
    ) -> Bool {
        var concealed = concealedBundleIDs
        // Never conceal Floe itself, and never bundle-conceal a system host —
        // that would blank every system item the host owns (the whole system
        // side of the bar). System items are concealed via their index below.
        concealed.subtract(protectedBundleIDs)
        concealed.subtract(SystemItems.hostBundleIDs)

        let allowedSystemItemSet = SystemItems.all.subtracting(concealedSystemItemIDs)

        // Nothing concealed → tear down any active restriction.
        guard !concealed.isEmpty || !concealedSystemItemIDs.isEmpty else {
            return reset()
        }

        // Allow every running app except those whose items are hidden. Listing
        // all running apps (not just ones currently hosting items) means apps
        // that appear later stay visible without a race.
        var allowedSet = Set(
            NSWorkspace.shared.runningApplications
                .compactMap(\.bundleIdentifier)
                .filter { !concealed.contains($0) }
        )
        allowedSet.formUnion(protectedBundleIDs)
        for bundleID in knownHostBundleIDs where !concealed.contains(bundleID) {
            allowedSet.insert(bundleID)
        }

        // Re-activating tears down and rebuilds the restriction, which reflows
        // the whole menu bar — expensive. Re-apply only when it matters:
        // nothing active yet, the concealed set changed, or a *new* app
        // appeared that must be kept visible. Apps merely quitting leave
        // harmless stale entries in the allowlist.
        let concealedChanged = concealed != appliedConcealed
        let systemItemsChanged = allowedSystemItemSet != appliedAllowedSystemItems
        let newlyAppeared = !allowedSet.subtracting(appliedAllowed).isEmpty
        guard handle == nil || concealedChanged || systemItemsChanged || newlyAppeared else {
            return false
        }

        // Don't re-activate the exact configuration that just failed
        // asynchronously — that would hot-loop on the re-apply tick. Any change
        // to the desired set makes this unequal and allows a genuine retry.
        if let lastFailedConfiguration,
           allowedSet == lastFailedConfiguration.allowed,
           allowedSystemItemSet == lastFailedConfiguration.systemItems
        {
            return false
        }
        lastFailedConfiguration = nil

        activationGeneration += 1
        let generation = activationGeneration
        let attemptedAllowed = allowedSet
        let attemptedSystemItems = allowedSystemItemSet

        // System item changes require the old assertion to be torn down BEFORE
        // the new one is created. MenuBarAgent only re-composites system-item
        // visibility when it observes an assertion going away; a silent swap
        // (create-then-invalidate) is treated as an update and items remain
        // on-screen. Bundle changes tolerate the swap order fine, so only
        // invert for system-item changes to avoid the extra reflow flash.
        if systemItemsChanged, let old = handle {
            FloeAssessmentModeHidingInvalidate(old)
            handle = nil
        }

        let allowedBundleIDs = allowedSet.sorted()
        let allowedSystemItems = allowedSystemItemSet.sorted().map { NSNumber(value: $0) }
        diagLog.info(
            "applying restriction: concealing \(concealed.sorted()), " +
                "systemItems=\(allowedSystemItems.map(\.stringValue)), allowing \(allowedBundleIDs.count) bundles"
        )

        let newHandle = FloeAssessmentModeHidingActivate(allowedBundleIDs, allowedSystemItems) { [weak self] in
            // Dispatched to the main queue by the ObjC wrapper, so MainActor
            // isolation holds at runtime even though the block type is not.
            MainActor.assumeIsolated {
                guard let self, self.activationGeneration == generation else { return }
                self.diagLog.error("activation failed asynchronously; tearing down handle to allow retry")
                if let dud = self.handle {
                    FloeAssessmentModeHidingInvalidate(dud)
                }
                self.handle = nil
                self.appliedConcealed = []
                self.appliedAllowed = []
                self.appliedAllowedSystemItems = SystemItems.all
                self.lastFailedConfiguration = (attemptedAllowed, attemptedSystemItems)
            }
        }
        if let old = handle {
            FloeAssessmentModeHidingInvalidate(old)
        }
        handle = newHandle
        appliedConcealed = concealed
        appliedAllowed = allowedSet
        appliedAllowedSystemItems = allowedSystemItemSet
        return true
    }

    /// Invalidates the live assertion, revealing everything it concealed.
    @discardableResult
    func reset() -> Bool {
        guard handle != nil else { return false }
        FloeAssessmentModeHidingInvalidate(handle)
        handle = nil
        appliedConcealed = []
        appliedAllowed = []
        appliedAllowedSystemItems = SystemItems.all
        diagLog.info("restriction reset; all items revealed")
        return true
    }
}
