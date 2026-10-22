import AppKit
import SwiftUI

@main
enum StrataMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSResponder, NSApplicationDelegate, NSMenuDelegate {
    private let layoutStore = LayoutStore()
    private lazy var barController = DockBarController(layoutStore: layoutStore)
    private let library = LibraryPanelController()
    private let popover = SettingsPopoverController()
    private let splash = SplashController()
    private lazy var dockSwap = SystemDockSwap(layoutStore: layoutStore)
    private var statusItem: NSStatusItem?
    /// `strata://` links that arrive before the bar is up (one may have
    /// launched the app) wait here.
    private var pendingCommands: [URLCommand] = []
    private var isLaunched = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Installed this early so the link that launched the app is caught.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Before loading: a bar that already holds an extension's tile keeps it.
        ExtensionStore.shared.enableIfUsed(byBar: layoutStore.layout.barTiles)
        DockBarState.shared.load(from: layoutStore)
        wireShell()
        installStatusItem()
        loadCatalog()
        startTicker()
        HotKeyCenter.shared.start()
        LaunchAtLogin.shared.refresh()

        // The Dock restarts to pick up its new setting; the black splash
        // covers that, then the bar slides up where the Dock was.
        dockSwap.update(barVisible: true)
        splash.show { [weak self] in
            guard let self else { return }
            self.barController.enter()
            self.isLaunched = true
            let pending = self.pendingCommands
            self.pendingCommands.removeAll()
            for command in pending { self.run(command) }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard barController.isVisible else {
            dockSwap.restore()
            return .terminateNow
        }
        // Hand the screen back the way it was taken: the bar slides away,
        // then the macOS Dock returns (video f79–f82).
        popover.close()
        library.hide()
        barController.exit { [weak self] in
            self?.dockSwap.restore()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        dockSwap.restore()
        layoutStore.save()
    }

    // MARK: - Shell

    private func wireShell() {
        AppsTiles.addToBar = { [weak self] id in
            self?.barController.addTile(id: id)
        }

        library.onAdd = { [weak self] id in
            if AppsTiles.handleLibraryClick(id: id) { return }
            self?.barController.addTile(id: id)
        }
        library.onVisibilityChange = { [weak self] visible in
            ServiceScheduler.shared.libraryVisible = visible
            withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
                DockBarState.shared.isEditing = visible
            }
            self?.barController.libraryVisibilityChanged(visible)
        }

        barController.onOpenLibrary = { [weak self] in self?.showLibrary() }
        barController.onFrameChange = { [weak self] frame in
            self?.library.place(beside: frame)
        }
        barController.holdsOpen = { [weak self] in
            guard let self else { return false }
            return self.library.isVisible || self.popover.isOpen
        }
        barController.onOpenTileSettings = { [weak self] spec, rect in
            guard let self, let settings = spec.settings else { return }
            if self.popover.openID == spec.id {
                self.popover.close()
                return
            }
            self.popover.open(
                id: spec.id,
                title: spec.title,
                settings: settings,
                anchor: rect,
                bar: self.barController.restingFrame
            )
        }
        barController.onOpenBarSettings = { _ in
            SettingsWindowController.shared.show()
        }

        SettingsWindowController.shared.controls = ShellControls(
            isBarVisible: { [weak self] in self?.barController.isVisible ?? false },
            setBarVisible: { [weak self] visible in self?.setBarVisible(visible) },
            autoHidesBar: { [weak self] in self?.layoutStore.layout.autoHide ?? false },
            setAutoHidesBar: { [weak self] enabled in self?.setAutoHidesBar(enabled) },
            hidesSystemDock: { [weak self] in self?.dockSwap.isEnabled ?? false },
            setHidesSystemDock: { [weak self] enabled in self?.setHidesSystemDock(enabled) }
        )

        HotKeyCenter.shared.onAction = { [weak self] action in self?.runShortcut(action) }
    }

    private func showLibrary() {
        if !barController.isVisible {
            barController.enter()
            dockSwap.update(barVisible: true)
            SettingsWindowController.shared.refresh()
        }
        popover.close()
        library.show(beside: barController.restingFrame)
    }

    // MARK: - Shortcuts and links

    private func runShortcut(_ action: HotKeyAction) {
        switch action {
        case .toggleBar:
            setBarVisible(!barController.isVisible)
        case .openLibrary:
            library.isVisible ? library.hide() : showLibrary()
        case .openSettings:
            SettingsWindowController.shared.show()
        case .toggleFocus:
            FocusTimer.shared.toggle()
        case .toggleAwake:
            KeepAwake.shared.toggle()
        }
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: text),
              let command = URLCommand(url: url)
        else {
            NSLog("Strata: ignored an unknown strata:// link")
            return
        }
        guard isLaunched else {
            if pendingCommands.count < 8 { pendingCommands.append(command) }
            return
        }
        run(command)
    }

    /// Every link is idempotent: `show` on a shown bar does nothing.
    private func run(_ command: URLCommand) {
        switch command {
        case .show:
            if !barController.isVisible { setBarVisible(true) }
        case .hide:
            if barController.isVisible { setBarVisible(false) }
        case .toggle:
            setBarVisible(!barController.isVisible)
        case .library:
            showLibrary()
        case .settings:
            SettingsWindowController.shared.show()
        case .focusStart:
            if !FocusTimer.shared.isRunning { FocusTimer.shared.toggle() }
        case .focusPause:
            if FocusTimer.shared.isRunning { FocusTimer.shared.toggle() }
        case .awakeOn:
            if !KeepAwake.shared.isActive { KeepAwake.shared.start(KeepAwake.shared.defaultSpan) }
        case .awakeOff:
            if KeepAwake.shared.isActive { KeepAwake.shared.stop() }
        case .refresh:
            refreshData()
        }
    }

    /// Refreshes only what a tile already shows, so a link never raises the
    /// keychain or location prompt for a tile that isn't there.
    private func refreshData() {
        if ExtensionStore.shared.isEnabled(.aiUsage) {
            let usage = AIUsageStore.shared
            switch usage.claude {
            case .idle, .accessDenied: break
            default: usage.refresh(.claude)
            }
            if case .idle = usage.codex, usage.codexDaily == nil {} else {
                usage.refresh(.codex)
            }
        }
        let weather = WeatherInfo.shared
        if weather.temperature != nil || weather.failed {
            Task { await weather.refreshIfNeeded(force: true) }
        }
    }

    // MARK: - Switches

    /// Shared by the status menu and the Settings window.
    private func setBarVisible(_ visible: Bool) {
        if !visible {
            popover.close()
            library.hide()
        }
        barController.setVisible(visible)
        dockSwap.update(barVisible: visible)
        SettingsWindowController.shared.refresh()
    }

    private func setAutoHidesBar(_ enabled: Bool) {
        barController.setAutoHide(enabled)
        SettingsWindowController.shared.refresh()
    }

    private func setHidesSystemDock(_ enabled: Bool) {
        dockSwap.setEnabled(enabled, barVisible: barController.isVisible)
        SettingsWindowController.shared.refresh()
    }

    // MARK: - Catalog

    /// The installed-apps catalogue the app tiles and the picker read.
    private func loadCatalog() {
        Task {
            let catalog = await Task.detached(priority: .userInitiated) { AppCatalog.scan() }.value
            AppCatalogStore.shared.update(catalog)
        }
    }

    // MARK: - Live data

    /// One shared clock for every tile; services refresh only while a tile
    /// that reads them is on the bar. See ``ServiceScheduler``.
    private func startTicker() {
        ServiceScheduler.shared.start()
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StrataMark.menuBarImage()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Rebuilt on every open so the checkmarks track the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        let widgets = ShellMenuItem("Widgets…") { [weak self] in
            guard let self else { return }
            self.library.isVisible ? self.library.hide() : self.showLibrary()
        }
        widgets.state = library.isVisible ? .on : .off
        menu.addItem(widgets)
        menu.addItem(.separator())

        let bar = ShellMenuItem("Show Strata Bar") { [weak self] in
            guard let self else { return }
            self.setBarVisible(!self.barController.isVisible)
        }
        bar.state = barController.isVisible ? .on : .off
        menu.addItem(bar)

        let autoHide = ShellMenuItem("Auto-hide Strata Bar") { [weak self] in
            guard let self else { return }
            self.setAutoHidesBar(!self.layoutStore.layout.autoHide)
        }
        autoHide.state = layoutStore.layout.autoHide ? .on : .off
        menu.addItem(autoHide)

        let systemDock = ShellMenuItem("Hide macOS Dock") { [weak self] in
            guard let self else { return }
            self.setHidesSystemDock(!self.dockSwap.isEnabled)
        }
        systemDock.state = dockSwap.isEnabled ? .on : .off
        menu.addItem(systemDock)

        let login = LaunchAtLogin.shared
        let launchAtLogin = ShellMenuItem("Launch at Login") {
            // Waiting on approval: only System Settings can finish it.
            login.requiresApproval ? login.openSystemSettings() : login.setEnabled(!login.isEnabled)
        }
        launchAtLogin.state = login.isEnabled ? .on : login.requiresApproval ? .mixed : .off
        menu.addItem(launchAtLogin)
        // Picks up a change made in System Settings for the next open.
        login.refresh()

        menu.addItem(.separator())
        let settings = ShellMenuItem("Settings…") { SettingsWindowController.shared.show() }
        settings.keyEquivalent = ","
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = ShellMenuItem("Quit Strata") { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }
}
