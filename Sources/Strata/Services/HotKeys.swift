import AppKit
import Carbon.HIToolbox
import Observation

/// A key plus Carbon modifier bits (`cmdKey`, `optionKey`, `controlKey`,
/// `shiftKey`), the form `RegisterEventHotKey` takes.
struct KeyCombo: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    private static let modifierMask = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.modifierMask
    }

    init(event: NSEvent) {
        self.init(keyCode: UInt32(event.keyCode), modifiers: Self.carbonModifiers(event.modifierFlags))
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var bits: UInt32 = 0
        if flags.contains(.control) { bits |= UInt32(controlKey) }
        if flags.contains(.option) { bits |= UInt32(optionKey) }
        if flags.contains(.shift) { bits |= UInt32(shiftKey) }
        if flags.contains(.command) { bits |= UInt32(cmdKey) }
        return bits
    }

    /// "⌃⌥⇧⌘", in the order the menus use.
    static func modifierSymbols(_ bits: UInt32) -> String {
        var text = ""
        if bits & UInt32(controlKey) != 0 { text += "⌃" }
        if bits & UInt32(optionKey) != 0 { text += "⌥" }
        if bits & UInt32(shiftKey) != 0 { text += "⇧" }
        if bits & UInt32(cmdKey) != 0 { text += "⌘" }
        return text
    }

    var isFunctionKey: Bool { Self.functionKeys[keyCode] != nil }

    /// Why macOS (or typing) would not let this combo work as a global
    /// shortcut, or `nil` when it can be used. Since macOS 15 a hotkey whose
    /// only modifiers are ⌥ and ⇧ is refused, and a bare letter would
    /// swallow typing everywhere.
    var rejection: String? {
        if isFunctionKey { return nil }
        if modifiers & UInt32(cmdKey | controlKey) == 0 {
            return modifiers == 0
                ? "Add ⌃ or ⌘ to the key."
                : "Include ⌃ or ⌘ — macOS doesn't allow ⌥ or ⇧ on their own."
        }
        return nil
    }

    /// "⌃⌥D".
    @MainActor
    var display: String { Self.modifierSymbols(modifiers) + Self.keyName(keyCode) }

    // MARK: Key names

    private static let functionKeys: [UInt32: String] = [
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15", UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18", UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
    ]

    private static let specialKeys: [UInt32: String] = [
        UInt32(kVK_Return): "↩", UInt32(kVK_ANSI_KeypadEnter): "⌤", UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Space): "Space", UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "⎋", UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓", UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘", UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_Help): "Help", UInt32(kVK_ANSI_KeypadClear): "⌧",
    ]

    /// The key's label: a symbol for the non-printing keys, otherwise what
    /// the current keyboard layout prints for it.
    @MainActor
    static func keyName(_ keyCode: UInt32) -> String {
        if let name = functionKeys[keyCode] ?? specialKeys[keyCode] { return name }
        return translated(keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    @MainActor
    private static func translated(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        let capacity = 4
        var characters = [UniChar](repeating: 0, count: capacity)
        var length = 0
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                base.assumingMemoryBound(to: UCKeyboardLayout.self),
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                capacity,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// What a global shortcut can do.
enum HotKeyAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case toggleBar
    case openLibrary
    case openSettings
    case toggleFocus
    /// Appended last: hotkey ids are positions in this list.
    case toggleAwake

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleBar: "Show or hide the bar"
        case .openLibrary: "Widget library"
        case .openSettings: "Settings"
        case .toggleFocus: "Start or pause focus"
        case .toggleAwake: "Keep awake on or off"
        }
    }

    var defaultCombo: KeyCombo? {
        switch self {
        case .toggleBar: KeyCombo(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey))
        case .openLibrary: KeyCombo(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(controlKey | optionKey))
        case .openSettings, .toggleFocus, .toggleAwake: nil
        }
    }

    /// The Carbon hotkey id; stable across launches.
    fileprivate var hotKeyID: UInt32 {
        UInt32(Self.allCases.firstIndex(of: self)! + 1)
    }

    fileprivate init?(hotKeyID: UInt32) {
        let index = Int(hotKeyID) - 1
        guard Self.allCases.indices.contains(index) else { return nil }
        self = Self.allCases[index]
    }
}

/// System-wide shortcuts through Carbon's `RegisterEventHotKey`, which
/// needs no Accessibility or Input Monitoring permission. Bindings persist
/// in `app.hotkeys` as JSON; an action missing from the stored map has no
/// shortcut, and a missing key means the defaults.
@MainActor
@Observable
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private static let defaultsKey = "app.hotkeys"
    fileprivate nonisolated static let signature: OSType = 0x4444_636B // 'DDck'

    private(set) var bindings: [HotKeyAction: KeyCombo]
    /// Actions whose shortcut macOS refused (taken by another app).
    private(set) var failed: Set<HotKeyAction> = []

    /// Set once by the app delegate.
    @ObservationIgnored var onAction: (@MainActor (HotKeyAction) -> Void)?

    @ObservationIgnored private var registered: [HotKeyAction: EventHotKeyRef] = [:]
    @ObservationIgnored private var handler: EventHandlerRef?
    /// While a recorder listens, the shortcuts are off so pressing one is
    /// recorded instead of run.
    @ObservationIgnored private var pauseCount = 0

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            var bindings: [HotKeyAction: KeyCombo] = [:]
            for (key, combo) in stored {
                if let action = HotKeyAction(rawValue: key) { bindings[action] = combo }
            }
            self.bindings = bindings
        } else {
            var bindings: [HotKeyAction: KeyCombo] = [:]
            for action in HotKeyAction.allCases {
                if let combo = action.defaultCombo { bindings[action] = combo }
            }
            self.bindings = bindings
        }
    }

    /// Installs the event handler and registers the saved shortcuts.
    func start() {
        installHandler()
        registerAll()
    }

    func combo(for action: HotKeyAction) -> KeyCombo? { bindings[action] }

    /// Binds `combo` to `action` (`nil` clears it). A combo already used by
    /// another action moves here.
    func set(_ combo: KeyCombo?, for action: HotKeyAction) {
        if let combo {
            for (other, existing) in bindings where other != action && existing == combo {
                bindings[other] = nil
            }
        }
        bindings[action] = combo
        save()
        registerAll()
    }

    func pause() {
        pauseCount += 1
        if pauseCount == 1 { unregisterAll() }
    }

    func resume() {
        guard pauseCount > 0 else { return }
        pauseCount -= 1
        if pauseCount == 0 { registerAll() }
    }

    fileprivate func fire(_ hotKeyID: UInt32) {
        guard pauseCount == 0, let action = HotKeyAction(hotKeyID: hotKeyID) else { return }
        onAction?(action)
    }

    // MARK: Carbon

    private func save() {
        let stored = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &spec,
            nil,
            &handler
        )
        if status != noErr {
            NSLog("Strata: hotkey handler failed: %d", status)
        }
    }

    private func registerAll() {
        unregisterAll()
        guard pauseCount == 0 else { return }
        var failed: Set<HotKeyAction> = []
        for action in HotKeyAction.allCases {
            guard let combo = bindings[action] else { continue }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                combo.keyCode,
                combo.modifiers,
                EventHotKeyID(signature: Self.signature, id: action.hotKeyID),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                registered[action] = ref
            } else {
                failed.insert(action)
                NSLog("Strata: hotkey for %@ failed: %d", action.rawValue, status)
            }
        }
        self.failed = failed
    }

    private func unregisterAll() {
        for ref in registered.values {
            UnregisterEventHotKey(ref)
        }
        registered.removeAll()
    }
}

/// Carbon calls this on the main thread for every Strata hotkey press.
private func hotKeyEventHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else {
        return OSStatus(eventNotHandledErr)
    }
    let id = hotKeyID.id
    Task { @MainActor in HotKeyCenter.shared.fire(id) }
    return noErr
}
