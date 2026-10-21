import AppKit
import SwiftUI

/// Which display the bar lives on.
enum BarDisplayChoice: Hashable, Sendable {
    /// The display with the menu bar.
    case main
    /// Whichever display the pointer last rested at the bar's edge of, like
    /// the macOS Dock.
    case pointer
    /// One display, remembered by id and name: ids can change when displays
    /// are reconnected, names rarely do.
    case display(id: CGDirectDisplayID, name: String)

    /// `main`, `pointer` or `display:<id>:<name>`.
    var storageValue: String {
        switch self {
        case .main: "main"
        case .pointer: "pointer"
        case let .display(id, name): "display:\(id):\(name)"
        }
    }

    init(storageValue: String) {
        switch storageValue {
        case "pointer":
            self = .pointer
        default:
            let parts = storageValue.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count == 3, parts[0] == "display", let id = CGDirectDisplayID(parts[1]) {
                self = .display(id: id, name: String(parts[2]))
            } else {
                self = .main
            }
        }
    }
}

/// Where the bar shows and when it steps aside. The bar controller listens
/// for `.dockBarDisplayDidChange`.
@MainActor
@Observable
final class BarDisplayStore {
    static let shared = BarDisplayStore()

    private static let displayKey = "bar.display"
    private static let fullScreenKey = "bar.hidesInFullScreen"

    var choice: BarDisplayChoice {
        didSet {
            guard choice != oldValue else { return }
            UserDefaults.standard.set(choice.storageValue, forKey: Self.displayKey)
            NotificationCenter.default.post(name: .dockBarDisplayDidChange, object: nil)
        }
    }

    /// Slide the bar away while a full-screen app covers its display.
    var hidesInFullScreen: Bool {
        didSet {
            guard hidesInFullScreen != oldValue else { return }
            UserDefaults.standard.set(hidesInFullScreen, forKey: Self.fullScreenKey)
            NotificationCenter.default.post(name: .dockBarDisplayDidChange, object: nil)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        choice = defaults.string(forKey: Self.displayKey).map(BarDisplayChoice.init(storageValue:)) ?? .main
        hidesInFullScreen = defaults.object(forKey: Self.fullScreenKey) as? Bool ?? true
    }

    /// The connected screen a remembered display refers to: the same id and
    /// name, else the same name (its id changed), else the same id (it was
    /// renamed).
    static func screen(id: CGDirectDisplayID, name: String) -> NSScreen? {
        let screens = NSScreen.screens
        return screens.first { $0.displayID == id && $0.localizedName == name }
            ?? screens.first { $0.localizedName == name }
            ?? screens.first { $0.displayID == id }
    }

    /// Re-remembers the chosen display under its current id and name once it
    /// is connected again, so the setting keeps matching it.
    func reconcile() {
        guard case let .display(id, name) = choice,
              let screen = Self.screen(id: id, name: name),
              let current = screen.displayID
        else { return }
        choice = .display(id: current, name: screen.localizedName)
    }
}

extension Notification.Name {
    /// Posted after `BarDisplayStore.choice` or `.hidesInFullScreen` changes.
    static let dockBarDisplayDidChange = Notification.Name("DockDock.barDisplayDidChange")
}

extension NSScreen {
    /// The Core Graphics id of the display this screen shows.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// "Show bar on" and "Hide in full-screen apps".
struct BarDisplaySettingsSection: View {
    private struct Option: Hashable {
        var title: String
        var choice: BarDisplayChoice
    }

    /// The connected displays; `NSScreen.screens` is not observable, so it
    /// is re-read when displays change.
    @State private var screens: [Option] = Self.connectedScreens()

    var body: some View {
        @Bindable var store = BarDisplayStore.shared
        Section {
            Picker(selection: $store.choice) {
                Text("Main display").tag(BarDisplayChoice.main)
                Text("Follow pointer").tag(BarDisplayChoice.pointer)
                Divider()
                ForEach(options(for: store.choice), id: \.self) { option in
                    Text(option.title).tag(option.choice)
                }
            } label: {
                Text("Show bar on")
                Text(caption(for: store.choice))
            }
            Toggle(isOn: $store.hidesInFullScreen) {
                Text("Hide in full-screen apps")
                Text("The bar slides away while an app fills its display as a full-screen Space.")
            }
        } header: {
            Text("Displays")
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            refresh()
        }
    }

    private func caption(for choice: BarDisplayChoice) -> String {
        switch choice {
        case .main:
            "The display with the menu bar."
        case .pointer:
            "Rest the pointer at the bar's edge of a display to move the bar there."
        case let .display(id, name):
            BarDisplayStore.screen(id: id, name: name) == nil
                ? "Not connected: the bar is on the main display until it is."
                : "The bar stays on this display."
        }
    }

    /// Every connected display, plus the chosen one while it is unplugged so
    /// the picker can still show it.
    private func options(for choice: BarDisplayChoice) -> [Option] {
        guard case let .display(_, name) = choice, !screens.contains(where: { $0.choice == choice }) else {
            return screens
        }
        return screens + [Option(title: "\(name) (not connected)", choice: choice)]
    }

    private func refresh() {
        BarDisplayStore.shared.reconcile()
        screens = Self.connectedScreens()
    }

    private static func connectedScreens() -> [Option] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            guard let id = screen.displayID else { return nil }
            let name = screen.localizedName
            return Option(
                title: index == 0 ? "\(name) (main)" : name,
                choice: .display(id: id, name: name)
            )
        }
    }
}
