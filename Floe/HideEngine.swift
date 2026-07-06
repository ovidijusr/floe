//
//  HideEngine.swift
//  Project: Floe
//  Licensed under the GNU GPLv3
//

import Cocoa
import Combine

/// Floe's single state machine: which apps/system items the user marked as
/// hidable, and whether they are currently concealed or revealed.
///
/// Hiding is two-tier: `CGSWindowHider` first (surgical, per-window, no bar
/// reflow) for any hidden app whose per-item windows are still resolvable;
/// the assessment-mode assertion covers the rest plus Apple system items.
@MainActor
final class HideEngine: ObservableObject {
    /// Bundle IDs of apps whose menu bar items the user chose to hide.
    @Published var hiddenBundleIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(hiddenBundleIDs.sorted(), forKey: Self.hiddenBundleIDsKey)
            applyDesiredState()
        }
    }

    /// `MBSystemItemIdentifier` raw values of system items the user chose to hide.
    @Published var hiddenSystemItemIDs: Set<Int> {
        didSet {
            UserDefaults.standard.set(hiddenSystemItemIDs.sorted(), forKey: Self.hiddenSystemItemIDsKey)
            applyDesiredState()
        }
    }

    /// Seconds after a reveal before auto-rehiding; 0 = never.
    @Published var rehideDelay: Int {
        didSet {
            UserDefaults.standard.set(rehideDelay, forKey: Self.rehideDelayKey)
        }
    }

    /// True while the user has toggled the hidden items back into view.
    @Published private(set) var isRevealed = false

    /// The most recently enumerated menu bar items (for the settings UI).
    @Published private(set) var items: [MenuBarItem] = []

    /// Whether the private hiding mechanism exists on this OS build.
    let isMechanismAvailable = AssessmentModeBackend.isAvailable

    /// Invoked (deferred) after the assertion reflows the menu bar, so the
    /// owner can force its own status item back on — the reflow otherwise
    /// suppresses it permanently. Set by `AppDelegate`.
    var onAssertionApplied: (() -> Void)?

    private static let hiddenBundleIDsKey = "hiddenBundleIDs"
    private static let hiddenSystemItemIDsKey = "hiddenSystemItemIDs"
    private static let rehideDelayKey = "rehideDelay"

    private let diagLog = DiagLog(category: "HideEngine")
    private let backend = AssessmentModeBackend()
    private let cgsHider = CGSWindowHider()

    /// Every bundle ID ever observed hosting a menu bar item this session.
    /// Fed to the assertion allowlist to protect sub-bundle hosts that are
    /// absent from `runningApplications`.
    private var knownHostBundleIDs: Set<String> = []

    /// Re-asserts the off-screen move while hiding is engaged; the system can
    /// reflow hidden windows back on-screen (display changes, app updates).
    private var maintenanceTimer: Timer?
    private var rehideTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        let defaults = UserDefaults.standard
        hiddenBundleIDs = Set(defaults.stringArray(forKey: Self.hiddenBundleIDsKey) ?? [])
        hiddenSystemItemIDs = Set((defaults.array(forKey: Self.hiddenSystemItemIDsKey) as? [Int]) ?? [])
        rehideDelay = defaults.object(forKey: Self.rehideDelayKey) as? Int ?? 30
    }

    /// Called once Accessibility is granted.
    func start() {
        if !isMechanismAvailable {
            diagLog.error("MenuBarClientCore assessment mode unavailable on this OS build; hiding disabled")
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshItems()
                    self?.applyDesiredState()
                }
            })
        }
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyDesiredState() }
        })

        refreshItems()
        applyDesiredState()
    }

    func refreshItems() {
        items = MenuBarItemEnumerator.items()
        for item in items {
            if let bundleID = item.ownerBundleID {
                knownHostBundleIDs.insert(bundleID)
            }
        }
    }

    func toggleReveal() {
        setRevealed(!isRevealed)
    }

    func setRevealed(_ revealed: Bool) {
        guard revealed != isRevealed else { return }
        isRevealed = revealed
        applyDesiredState()

        rehideTimer?.invalidate()
        rehideTimer = nil
        if revealed, rehideDelay > 0 {
            rehideTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(rehideDelay), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.setRevealed(false) }
            }
        }
    }

    /// Reconciles reality with the desired state.
    func applyDesiredState() {
        guard isMechanismAvailable else { return }

        let shouldHide = !isRevealed && !(hiddenBundleIDs.isEmpty && hiddenSystemItemIDs.isEmpty)
        guard shouldHide else {
            cgsHider.apply(hiddenPIDs: [])
            backend.reset()
            stopMaintenanceTimer()
            return
        }

        // Surgical tier: resolve hidden apps to live PIDs and move their item
        // windows off-screen where possible.
        var hiddenPIDs = Set<pid_t>()
        var bundleIDByPID: [pid_t: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier, hiddenBundleIDs.contains(bundleID) else { continue }
            hiddenPIDs.insert(app.processIdentifier)
            bundleIDByPID[app.processIdentifier] = bundleID
        }
        let handledPIDs = cgsHider.apply(hiddenPIDs: hiddenPIDs)
        let handledBundleIDs = Set(handledPIDs.compactMap { bundleIDByPID[$0] })

        // Assertion tier: whatever CGS couldn't handle, plus system items.
        backend.apply(
            concealedBundleIDs: hiddenBundleIDs.subtracting(handledBundleIDs),
            concealedSystemItemIDs: hiddenSystemItemIDs,
            knownHostBundleIDs: knownHostBundleIDs
        )

        // The assertion reflows the whole bar and suppresses our own status
        // item; re-assert it once MenuBarAgent has finished reflowing. Two
        // passes cover both a fast and a slightly delayed reflow.
        for delay in [0.15, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.onAssertionApplied?()
            }
        }

        startMaintenanceTimer()
    }

    private func startMaintenanceTimer() {
        guard maintenanceTimer == nil else { return }
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyDesiredState() }
        }
        maintenanceTimer?.tolerance = 2
    }

    private func stopMaintenanceTimer() {
        maintenanceTimer?.invalidate()
        maintenanceTimer = nil
    }
}
