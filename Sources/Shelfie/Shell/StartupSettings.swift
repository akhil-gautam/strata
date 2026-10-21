import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// Login item, global shortcuts and the `shelfie://` links. Embedded in a
/// grouped `Form`.
struct StartupSettingsSection: View {
    @State private var recorder = ShortcutRecorderModel()

    var body: some View {
        let login = LaunchAtLogin.shared
        Section {
            Toggle(isOn: Binding(
                get: { login.isRequested },
                set: { login.setEnabled($0) }
            )) {
                Text("Open Shelfie at login")
                Text("Starts Shelfie when you log in to this Mac.")
            }
            .task {
                // The user can approve or remove the login item in System
                // Settings while this window is open.
                while !Task.isCancelled {
                    login.refresh()
                    do {
                        try await Task.sleep(for: .seconds(2))
                    } catch {
                        return
                    }
                }
            }
            if login.requiresApproval {
                LabeledContent {
                    Button("Approve in System Settings") { login.openSystemSettings() }
                } label: {
                    Text("Waiting for approval")
                    Text("macOS keeps Shelfie off at login until you allow it under Login Items.")
                }
            }
            if let error = login.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Startup")
        }

        Section {
            ForEach(HotKeyAction.allCases) { action in
                ShortcutRow(action: action, recorder: recorder)
            }
        } header: {
            Text("Keyboard Shortcuts")
        } footer: {
            Text("Shortcuts work in every app. Click one and press the keys: Esc cancels, Delete clears. Scripts can run `open shelfie://toggle`; the links are \(URLCommand.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        .onDisappear { recorder.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            recorder.stop()
        }
    }
}

/// One action's shortcut: the recorder button, a clear button and why the
/// last combo was refused.
private struct ShortcutRow: View {
    let action: HotKeyAction
    let recorder: ShortcutRecorderModel

    var body: some View {
        let hotKeys = HotKeyCenter.shared
        let combo = hotKeys.combo(for: action)
        let isRecording = recorder.recording == action
        LabeledContent {
            HStack(spacing: 6) {
                Button {
                    isRecording ? recorder.stop() : recorder.start(action)
                } label: {
                    Text(label(combo: combo, isRecording: isRecording))
                        .monospacedDigit()
                        .frame(minWidth: 120)
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .accentColor : nil)

                Button {
                    recorder.stop()
                    hotKeys.set(nil, for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear shortcut")
                .opacity(combo == nil || isRecording ? 0 : 1)
                .disabled(combo == nil || isRecording)
            }
        } label: {
            Text(action.title)
            if let message = recorder.messages[action] {
                Text(message).foregroundStyle(.red)
            } else if combo != nil, hotKeys.failed.contains(action) {
                Text("macOS refused this shortcut; another app may be using it.").foregroundStyle(.red)
            }
        }
    }

    private func label(combo: KeyCombo?, isRecording: Bool) -> String {
        if isRecording {
            let held = KeyCombo.modifierSymbols(recorder.heldModifiers)
            return held.isEmpty ? "Type shortcut…" : held + "…"
        }
        return combo?.display ?? "Record Shortcut"
    }
}

/// Listens for the next key combo while a recorder button is armed. The
/// app's own hotkeys are paused meanwhile so an existing shortcut can be
/// recorded again instead of firing.
@MainActor
@Observable
private final class ShortcutRecorderModel {
    private(set) var recording: HotKeyAction?
    private(set) var heldModifiers: UInt32 = 0
    private(set) var messages: [HotKeyAction: String] = [:]
    @ObservationIgnored private var monitor: Any?

    func start(_ action: HotKeyAction) {
        stop()
        recording = action
        heldModifiers = 0
        messages[action] = nil
        HotKeyCenter.shared.pause()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    func stop() {
        guard recording != nil else { return }
        recording = nil
        heldModifiers = 0
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        HotKeyCenter.shared.resume()
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let action = recording else { return false }
        if event.type == .flagsChanged {
            heldModifiers = KeyCombo.carbonModifiers(event.modifierFlags)
            return true
        }
        let combo = KeyCombo(event: event)
        if combo.modifiers == 0 {
            switch Int(combo.keyCode) {
            case kVK_Escape:
                stop()
                return true
            case kVK_Delete, kVK_ForwardDelete:
                HotKeyCenter.shared.set(nil, for: action)
                stop()
                return true
            default:
                break
            }
        }
        if let rejection = combo.rejection {
            messages[action] = rejection
            return true
        }
        messages[action] = nil
        HotKeyCenter.shared.set(combo, for: action)
        stop()
        return true
    }
}
