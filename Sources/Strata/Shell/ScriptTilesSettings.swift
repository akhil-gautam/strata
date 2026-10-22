import SwiftUI

/// The row under the Script Tiles switch in Settings → Extensions.
struct ScriptTilesStatusRows: View {
    /// The extension's footer in Settings → Extensions.
    static let footer = "Each script runs with Strata's permissions, so it needs your approval before its first run and again after every edit. Name scripts like xbar plugins (hello.5s.sh runs every 5 seconds), make them executable, and print JSON or xbar-style text."

    var body: some View {
        LabeledContent("Scripts folder") {
            HStack(spacing: 8) {
                Text((ScriptFiles.folder.path as NSString).abbreviatingWithTildeInPath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Open") { ScriptStore.shared.openFolder() }
            }
        }
    }
}

/// The discovered scripts with their approval, and the folder actions.
struct ScriptTilesSettingsSection: View {
    @State private var examplesNote: String?

    var body: some View {
        let store = ScriptStore.shared
        Section {
            if store.scripts.isEmpty {
                Text(store.hasScanned
                    ? "No scripts yet. Put an executable file in the Scripts folder, or add the examples below."
                    : "Looking for scripts…")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.scripts) { item in
                    ScriptTilesSettingsRow(item: item)
                }
            }
        } header: {
            Text("Scripts")
        } footer: {
            Text("Approving shows the start of the script first. Approved scripts run only while their tile is on the bar, with a 10-second limit.")
        }
        .onAppear { store.rescan() }

        Section {
            LabeledContent {
                Button("Open Scripts Folder") { store.openFolder() }
            } label: {
                Text("Scripts folder")
                Text((ScriptFiles.folder.path as NSString).abbreviatingWithTildeInPath)
            }
            LabeledContent {
                Button("Add Example Scripts") {
                    Task {
                        let added = await store.installExamples()
                        examplesNote = switch added {
                        case 0: "The examples are already in the folder."
                        case 1: "Added 1 example. Approve it before it runs."
                        default: "Added \(added) examples. Approve them before they run."
                        }
                    }
                }
            } label: {
                Text("Examples")
                Text(examplesNote ?? "Uptime (text), battery (JSON) and dirty git repos in ~/projects.")
            }
        } header: {
            Text("Scripts Folder")
        }
    }
}

private struct ScriptTilesSettingsRow: View {
    let item: ScriptFileInfo

    var body: some View {
        let store = ScriptStore.shared
        let trust = store.trust(of: item)
        LabeledContent {
            HStack(spacing: 10) {
                Text(trust.label)
                    .foregroundStyle(trust.tint)
                if trust == .trusted {
                    Button("Revoke") { store.revoke(item.filename) }
                } else {
                    Button("Approve…") { store.review(item.filename) }
                }
            }
        } label: {
            Text(item.title)
            Text("\(item.filename) · every \(ScriptFiles.intervalLabel(item.interval))")
        }
    }
}

private extension ScriptStore.Trust {
    var label: String {
        switch self {
        case .trusted: "Trusted"
        case .notReviewed: "Not reviewed"
        case .changed: "Changed"
        }
    }

    var tint: Color {
        switch self {
        case .trusted: .green
        case .notReviewed: .secondary
        case .changed: .orange
        }
    }
}
