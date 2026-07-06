//
//  SettingsView.swift
//  Project: Floe
//  Licensed under the GNU GPLv3
//

import SwiftUI

/// One window: pick which menu bar items are hidable, and the rehide delay.
struct SettingsView: View {
    @ObservedObject var engine: HideEngine

    /// One row per third-party app (hiding is per-app on macOS 27).
    private var appRows: [(bundleID: String, name: String, icon: NSImage?)] {
        var seen = Set<String>()
        var rows: [(String, String, NSImage?)] = []
        let ownBundleID = Bundle.main.bundleIdentifier
        for item in engine.items {
            guard let bundleID = item.ownerBundleID,
                  bundleID != ownBundleID,
                  !item.isSystemHosted,
                  !seen.contains(bundleID)
            else { continue }
            seen.insert(bundleID)
            let icon = NSRunningApplication(processIdentifier: item.ownerPID)?.icon
            rows.append((bundleID, item.ownerName, icon))
        }
        // Apps whose items are currently hidden drop out of AX enumeration;
        // keep them listed so they can be un-hidden.
        for bundleID in engine.hiddenBundleIDs.sorted() where !seen.contains(bundleID) {
            seen.insert(bundleID)
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            rows.append((bundleID, running?.localizedName ?? bundleID, running?.icon))
        }
        return rows.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    /// System items currently visible in the bar (plus any already hidden).
    private var systemRows: [Int] {
        var ids = Set(engine.items.compactMap(\.systemItemID))
        ids.formUnion(engine.hiddenSystemItemIDs)
        return ids.sorted()
    }

    var body: some View {
        Form {
            if !engine.isMechanismAvailable {
                Section {
                    Label(
                        "This macOS build does not expose the menu bar hiding mechanism. Floe cannot hide items.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
            }

            Section("Apps") {
                if appRows.isEmpty {
                    Text("No third-party menu bar items found.")
                        .foregroundStyle(.secondary)
                }
                ForEach(appRows, id: \.bundleID) { row in
                    Toggle(isOn: hiddenBinding(for: row.bundleID)) {
                        HStack(spacing: 8) {
                            if let icon = row.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "app.dashed")
                                    .frame(width: 20, height: 20)
                            }
                            Text(row.name)
                        }
                    }
                }
            }

            Section("System") {
                ForEach(systemRows, id: \.self) { id in
                    Toggle(SystemItems.displayName(for: id), isOn: systemHiddenBinding(for: id))
                }
            }

            Section("Behavior") {
                Picker("Rehide after showing", selection: $engine.rehideDelay) {
                    Text("Never").tag(0)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 480)
        .navigationTitle("Floe")
        .onAppear { engine.refreshItems() }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            engine.refreshItems()
        }
    }

    private func hiddenBinding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { engine.hiddenBundleIDs.contains(bundleID) },
            set: { hidden in
                if hidden {
                    engine.hiddenBundleIDs.insert(bundleID)
                } else {
                    engine.hiddenBundleIDs.remove(bundleID)
                }
            }
        )
    }

    private func systemHiddenBinding(for id: Int) -> Binding<Bool> {
        Binding(
            get: { engine.hiddenSystemItemIDs.contains(id) },
            set: { hidden in
                if hidden {
                    engine.hiddenSystemItemIDs.insert(id)
                } else {
                    engine.hiddenSystemItemIDs.remove(id)
                }
            }
        )
    }
}
