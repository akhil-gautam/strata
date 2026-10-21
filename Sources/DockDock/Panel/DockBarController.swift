import AppKit
import SwiftUI

/// The bar of tiles. It sits where `AppearanceStore.position` says: bottom
/// centre where the macOS Dock sits (video f06–f81), a column on the left or
/// right edge, or hanging from the top edge around the camera housing; on
/// the display `BarDisplayStore` picks, stepping aside for full-screen apps.
@MainActor
final class DockBarController {
    /// Space between the bar and its screen edge (bottom, left or right).
    static let edgeInset: CGFloat = 2
    /// The bar never gets closer than this to the screen's ends along its
    /// length; beyond that its tiles scroll.
    static let endMargin: CGFloat = 8
    /// How far past its edge the bar parks when hidden.
    static let hiddenOverscan: CGFloat = 8
    /// The smallest bottom corner radius of the notch bar.
    static let notchMinCorner: CGFloat = 10
    /// Above the menu bar and its status items, so the notch bar covers
    /// them; still below menus and pop-ups.
    static let level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    private let panel: DockBarPanel
    private let host: NSHostingView<DockBarView>
    private let state = DockBarState.shared
    private let tooltip = DockBarTooltip()
    private let layoutStore: LayoutStore
    private let appearance = AppearanceStore.shared
    private var autoHide: AutoHideController?
    private var mouseMonitor: Any?

    /// The position the bar is laid out for. Trails `AppearanceStore` while
    /// the bar slides out from its old edge.
    private var position: DockPosition
    /// Size of the tiles plus padding, as SwiftUI measured it.
    private var contentSize: CGSize
    /// Each tile's frame in the window's content, top-left origin.
    private var tileFrames: [String: CGRect] = [:]
    private var hoveredID: String?
    /// Slide animations in flight; layout changes wait for them to land.
    private var activeSlides = 0
    /// Bumped on every position change, so only the latest one slides in.
    private var positionChanges = 0
    /// The bar is parked past its old edge, waiting to come in at the new
    /// one.
    private var isChangingPosition = false
    /// The display the bar is laid out on. Trails the display setting (and,
    /// following the pointer, the pointer) while the bar slides across.
    private var screenID: CGDirectDisplayID?
    /// Following the pointer: the display whose bar edge the pointer last
    /// rested at.
    private var pointerScreenID: CGDirectDisplayID?
    private var pointerMonitors: [Any] = []
    /// The pointer is at the bar's edge of another display; after a short
    /// rest the bar moves there.
    private var edgeRest: (screenID: CGDirectDisplayID, task: Task<Void, Never>)?
    /// The bar is on screen or sliding in, rather than parked out of sight.
    private var isOnScreen = false
    /// A full-screen Space covers the bar's display.
    private var isCoveredByFullScreen = false
    /// The user brought the bar up over a full-screen app; it stays until
    /// the next Space change.
    private var showsOverFullScreen = false
    /// Bumped on every full-screen check, so only the latest one counts.
    private var fullScreenChecks = 0
    /// A tile is being dragged to a new place.
    private var isReordering = false
    private let displays = BarDisplayStore.shared

    /// "Widgets…" in the bar's menu.
    var onOpenLibrary: (() -> Void)?
    /// "Settings…" in the bar's menu; the rect is the bar in screen space.
    var onOpenBarSettings: ((NSRect) -> Void)?
    /// A tile asked for its settings popover; the rect is the tile in screen
    /// space.
    var onOpenTileSettings: ((TileSpec, NSRect) -> Void)?
    /// The bar's resting frame changed (size, position or screen).
    var onFrameChange: ((NSRect) -> Void)?
    /// Keeps the bar on screen while the library or a popover is open.
    var holdsOpen: (() -> Bool)?

    /// Whether the user wants the bar on screen.
    private(set) var isVisible = false

    init(layoutStore: LayoutStore) {
        self.layoutStore = layoutStore
        position = AppearanceStore.shared.position
        contentSize = CGSize(width: TileMetrics.barPadding * 2, height: TileMetrics.barHeight)

        panel = DockBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: TileMetrics.barHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = Self.level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false

        host = NSHostingView(
            rootView: DockBarView(state: DockBarState.shared, position: position, topInset: 0, actions: DockBarActions())
        )
        host.sizingOptions = []
        panel.contentView = host
        screenID = targetScreenID()
        updateRootView()
        applyTheme()

        autoHide = AutoHideController(
            window: panel,
            delay: { [layoutStore] in layoutStore.layout.hideDelay },
            parkedOrigin: { [weak self] in self?.restingFrame.origin ?? .zero },
            hiddenOrigin: { [weak self] in self?.hiddenOrigin ?? .zero },
            revealZone: { [weak self] in self?.revealZone ?? .zero },
            holdsOpen: { [weak self] in
                guard let self else { return false }
                return self.isReordering || (self.holdsOpen?() ?? false)
            }
        )

        installMouseMonitor()
        let center = NotificationCenter.default
        center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensDidChange()
            }
        }
        center.addObserver(forName: .dockPositionDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.retarget()
            }
        }
        center.addObserver(forName: .dockThemeDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyTheme()
            }
        }
        center.addObserver(forName: .dockBarDisplayDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.displaySettingsDidChange()
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.activeSpaceDidChange()
            }
        }
        workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkFullScreen()
            }
        }
        updatePointerTracking()
        checkFullScreen()
    }

    // MARK: - Showing

    /// The frame the bar rests at, against its edge of the screen.
    var restingFrame: NSRect {
        guard let screen else { return panel.frame }
        let frame = screen.frame
        switch position {
        case .bottom:
            let width = min(contentSize.width, frame.width - Self.endMargin * 2).rounded()
            return NSRect(
                x: (frame.midX - width / 2).rounded(),
                y: frame.minY + Self.edgeInset,
                width: width,
                height: TileMetrics.barHeight
            )
        case .left, .right:
            let visible = screen.visibleFrame
            let width = contentSize.width.rounded()
            let height = min(contentSize.height, visible.height - Self.endMargin * 2).rounded()
            return NSRect(
                x: position == .left ? frame.minX + Self.edgeInset : frame.maxX - Self.edgeInset - width,
                y: (visible.midY - height / 2).rounded(),
                width: width,
                height: height
            )
        case .notch:
            let width = min(max(contentSize.width, Self.housingWidth(of: screen)), frame.width - Self.endMargin * 2)
                .rounded()
            let height = TileMetrics.barHeight + Self.housingHeight(of: screen)
            return NSRect(
                x: (frame.midX - width / 2).rounded(),
                y: frame.maxY - height,
                width: width,
                height: height
            )
        }
    }

    /// Slides the bar in from its screen edge, where the macOS Dock was for
    /// the bottom bar (video f07–f09).
    func enter() {
        isVisible = true
        // Asked for over a full-screen app: it stays until the next Space
        // change.
        if isCoveredByFullScreen {
            showsOverFullScreen = true
        }
        slideIn()
    }

    /// Slides the bar out past its screen edge (video f79–f82).
    func exit(completion: (@MainActor () -> Void)? = nil) {
        isVisible = false
        showsOverFullScreen = false
        isOnScreen = false
        autoHide?.setEnabled(false, animated: false)
        tooltip.hide()
        slideOut { [weak self] in
            guard let self else { return }
            if !self.isOnScreen {
                self.panel.orderOut(nil)
            }
            completion?()
        }
    }

    func setVisible(_ visible: Bool) {
        visible ? enter() : exit()
    }

    func setAutoHide(_ enabled: Bool) {
        layoutStore.setAutoHide(enabled)
        guard isOnScreen else { return }
        autoHide?.setEnabled(enabled)
    }

    /// Whether the bar belongs on screen: the user wants it, and no
    /// full-screen app covers its display (unless the user asked for it
    /// there).
    private var isShown: Bool {
        isVisible && !(displays.hidesInFullScreen && isCoveredByFullScreen && !showsOverFullScreen)
    }

    private func slideIn() {
        isChangingPosition = false
        isOnScreen = true
        let target = restingFrame
        panel.setFrame(NSRect(origin: hiddenOrigin, size: target.size), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        activeSlides += 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(target, display: true)
        } completionHandler: {
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                self.activeSlides -= 1
                // Tiles may have changed size while it slid.
                self.relayout()
                if self.isOnScreen {
                    self.autoHide?.setEnabled(self.layoutStore.layout.autoHide)
                }
            }
        }
        onFrameChange?(target)
    }

    private func slideOut(completion: @escaping @MainActor () -> Void) {
        activeSlides += 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(
                NSRect(origin: hiddenOrigin, size: panel.frame.size),
                display: true
            )
        } completionHandler: {
            MainActor.assumeIsolated { [weak self] in
                self?.activeSlides -= 1
                completion()
            }
        }
    }

    // MARK: - Position and theme

    /// Moves the bar to the position and display the settings (and the
    /// pointer) ask for. On screen, it leaves by its old edge, is re-laid,
    /// and comes back in at the new one.
    private func retarget() {
        guard appearance.position != position || targetScreenID() != screenID else { return }
        tooltip.hide()
        hoveredID = nil
        guard isOnScreen else {
            applyTarget()
            return
        }
        positionChanges += 1
        let change = positionChanges
        isChangingPosition = true
        autoHide?.setEnabled(false, animated: false)
        slideOut { [weak self] in
            guard let self, change == self.positionChanges else { return }
            self.applyTarget()
            // Give SwiftUI a moment to measure the tiles in their new
            // arrangement before the bar sizes itself to them.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, change == self.positionChanges, self.isChangingPosition else { return }
                if self.isShown {
                    self.slideIn()
                } else {
                    // Hidden, or covered by a full-screen app, meanwhile.
                    self.isChangingPosition = false
                    self.isOnScreen = false
                    self.panel.orderOut(nil)
                }
            }
        }
    }

    private func applyTarget() {
        if appearance.position != position {
            position = appearance.position
            tileFrames.removeAll()
        }
        let target = targetScreenID()
        if target != screenID {
            screenID = target
            checkFullScreen()
        }
        updateRootView()
        host.layoutSubtreeIfNeeded()
        relayout()
    }

    private func updateRootView() {
        host.rootView = DockBarView(
            state: state,
            position: position,
            topInset: position == .notch ? screen.map(Self.housingHeight(of:)) ?? 0 : 0,
            actions: DockBarActions(
                remove: { [weak self] id in self?.removeTile(id: id) },
                openSettings: { [weak self] id in self?.openSettings(forTile: id) },
                hover: { [weak self] id, hovering in self?.hover(id, hovering) },
                frame: { [weak self] id, frame in self?.tileFrames[id] = frame },
                contentSize: { [weak self] size in self?.updateContentSize(size) },
                reorder: { [weak self] active in self?.reorderDidChange(active) },
                move: { [weak self] id, index in self?.state.move(id, to: index) },
                openBarSettings: { [weak self] in
                    guard let self else { return }
                    self.tooltip.hide()
                    self.onOpenBarSettings?(self.panel.frame)
                }
            )
        )
    }

    /// Window-level parts of the theme: the shadow and the AppKit
    /// appearance (context menus, scrollers).
    private func applyTheme() {
        let theme = appearance.theme
        panel.hasShadow = theme.barShadow
        panel.appearance = theme.appearance.nsAppearance
        // The shadow follows the bar's shape once SwiftUI has redrawn it.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            self?.panel.invalidateShadow()
        }
    }

    // MARK: - Tiles

    func addTile(id: String) {
        state.add(id)
    }

    func removeTile(id: String) {
        state.remove(id)
        tileFrames[id] = nil
        if hoveredID == id {
            hover(id, false)
        }
    }

    /// A tile's rect in screen coordinates.
    func screenRect(ofTile id: String) -> NSRect? {
        guard let frame = tileFrames[id] else { return nil }
        return NSRect(
            x: panel.frame.minX + frame.minX,
            y: panel.frame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private func openSettings(forTile id: String) {
        guard let spec = TileCatalog.spec(id: id), spec.settings != nil else { return }
        tooltip.hide()
        let rect = screenRect(ofTile: id) ?? panel.frame
        onOpenTileSettings?(spec, rect)
    }

    // MARK: - Layout

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.displayID == screenID } ?? NSScreen.screens.first
    }

    /// The display the settings ask for; the main one while the chosen
    /// display is disconnected.
    private func targetScreenID() -> CGDirectDisplayID? {
        let screens = NSScreen.screens
        let main = screens.first?.displayID
        func connected(_ id: CGDirectDisplayID?) -> CGDirectDisplayID? {
            guard let id, screens.contains(where: { $0.displayID == id }) else { return nil }
            return id
        }
        switch displays.choice {
        case .main:
            return main
        case .pointer:
            return connected(pointerScreenID) ?? connected(screenID) ?? main
        case let .display(id, name):
            return BarDisplayStore.screen(id: id, name: name)?.displayID ?? main
        }
    }

    /// Height of the camera housing the notch bar hangs around; zero on
    /// screens without one.
    private static func housingHeight(of screen: NSScreen) -> CGFloat {
        screen.safeAreaInsets.top
    }

    /// Width of the camera housing: the gap between the menu bar areas on
    /// either side of it.
    private static func housingWidth(of screen: NSScreen) -> CGFloat {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return 0 }
        return max(right.minX - left.maxX, 0)
    }

    /// Just past the bar's own screen edge.
    private var hiddenOrigin: NSPoint {
        let resting = restingFrame
        guard let frame = screen?.frame else { return resting.origin }
        switch position {
        case .bottom:
            return NSPoint(x: resting.minX, y: frame.minY - resting.height - Self.hiddenOverscan)
        case .notch:
            return NSPoint(x: resting.minX, y: frame.maxY + Self.hiddenOverscan)
        case .left:
            return NSPoint(x: frame.minX - resting.width - Self.hiddenOverscan, y: resting.minY)
        case .right:
            return NSPoint(x: frame.maxX + Self.hiddenOverscan, y: resting.minY)
        }
    }

    /// Where the pointer brings an auto-hidden bar back: the strip of the
    /// bar's screen edge alongside the bar.
    private var revealZone: CGRect {
        let resting = restingFrame
        guard let frame = screen?.frame else { return .zero }
        switch position {
        case .bottom:
            return CGRect(x: resting.minX - 20, y: frame.minY - 20, width: resting.width + 40, height: 24)
        case .notch:
            return CGRect(x: resting.minX - 20, y: frame.maxY - 4, width: resting.width + 40, height: 24)
        case .left:
            return CGRect(x: frame.minX - 20, y: resting.minY - 20, width: 24, height: resting.height + 40)
        case .right:
            return CGRect(x: frame.maxX - 4, y: resting.minY - 20, width: 24, height: resting.height + 40)
        }
    }

    private func updateContentSize(_ size: CGSize) {
        guard abs(size.width - contentSize.width) > 0.5 || abs(size.height - contentSize.height) > 0.5 else { return }
        contentSize = size
        relayout()
    }

    private func relayout() {
        let resting = restingFrame
        onFrameChange?(resting)
        // A sliding bar is re-laid when it lands.
        guard isOnScreen, activeSlides == 0, !isChangingPosition else { return }
        let origin = autoHide?.isHidden == true ? hiddenOrigin : resting.origin
        panel.setFrame(NSRect(origin: origin, size: resting.size), display: true)
        panel.invalidateShadow()
    }

    // MARK: - Displays

    private func screensDidChange() {
        displays.reconcile()
        // The bar's display went away: it is re-laid on the one the settings
        // fall back to.
        if !NSScreen.screens.contains(where: { $0.displayID == screenID }) {
            screenID = targetScreenID()
        }
        updateRootView()
        relayout()
        updatePointerTracking()
        retarget()
        checkFullScreen()
    }

    private func displaySettingsDidChange() {
        if displays.choice != .pointer {
            pointerScreenID = nil
        }
        updatePointerTracking()
        retarget()
        checkFullScreen()
    }

    /// Watches the pointer only while following it across displays.
    private func updatePointerTracking() {
        let wanted = displays.choice == .pointer && NSScreen.screens.count > 1
        if wanted, pointerMonitors.isEmpty {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.pointerMoved()
                }
            }) {
                pointerMonitors.append(monitor)
            }
            if let monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
                MainActor.assumeIsolated {
                    self?.pointerMoved()
                }
                return event
            }) {
                pointerMonitors.append(monitor)
            }
        } else if !wanted, !pointerMonitors.isEmpty {
            for monitor in pointerMonitors {
                NSEvent.removeMonitor(monitor)
            }
            pointerMonitors.removeAll()
            edgeRest?.task.cancel()
            edgeRest = nil
        }
    }

    /// Like the macOS Dock: resting the pointer at the bar's edge of another
    /// display for a moment brings the bar there.
    private func pointerMoved() {
        guard let edge = edgeScreen(at: NSEvent.mouseLocation), edge != screenID else {
            edgeRest?.task.cancel()
            edgeRest = nil
            return
        }
        guard edgeRest?.screenID != edge else { return }
        edgeRest?.task.cancel()
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.edgeRest = nil
            guard self.edgeScreen(at: NSEvent.mouseLocation) == edge else { return }
            self.pointerRested(on: edge)
        }
        edgeRest = (edge, task)
    }

    /// The display whose bar edge the point is against. An edge shared with
    /// a neighbouring display does not count: the pointer passes through it.
    private func edgeScreen(at point: NSPoint) -> CGDirectDisplayID? {
        let screens = NSScreen.screens
        for screen in screens {
            let frame = screen.frame
            let alongX = point.x >= frame.minX && point.x <= frame.maxX
            let alongY = point.y >= frame.minY && point.y <= frame.maxY
            let beyond: NSPoint
            switch position {
            case .bottom:
                guard alongX, abs(point.y - frame.minY) <= 2 else { continue }
                beyond = NSPoint(x: point.x, y: frame.minY - 4)
            case .notch:
                guard alongX, abs(point.y - frame.maxY) <= 2 else { continue }
                beyond = NSPoint(x: point.x, y: frame.maxY + 4)
            case .left:
                guard alongY, abs(point.x - frame.minX) <= 2 else { continue }
                beyond = NSPoint(x: frame.minX - 4, y: point.y)
            case .right:
                guard alongY, abs(point.x - frame.maxX) <= 2 else { continue }
                beyond = NSPoint(x: frame.maxX + 4, y: point.y)
            }
            if !screens.contains(where: { $0.frame.contains(beyond) }) {
                return screen.displayID
            }
        }
        return nil
    }

    private func pointerRested(on id: CGDirectDisplayID) {
        // Not while the user works with the bar: the library or a popover is
        // open beside it, or a tile is being dragged.
        guard displays.choice == .pointer, !isReordering, !(holdsOpen?() ?? false) else { return }
        pointerScreenID = id
        retarget()
    }

    // MARK: - Full screen

    private func activeSpaceDidChange() {
        showsOverFullScreen = false
        checkFullScreen()
    }

    /// Looks for a full-screen app on the bar's display, now and again once
    /// windows settle: they are still animating into (or out of) a
    /// full-screen Space when it becomes active.
    private func checkFullScreen() {
        fullScreenChecks += 1
        let check = fullScreenChecks
        Task { @MainActor [weak self] in
            for delay in [0, 700] {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                guard let self, check == self.fullScreenChecks else { return }
                let covered = await self.fullScreenCovers()
                guard check == self.fullScreenChecks else { return }
                self.isCoveredByFullScreen = covered
                self.syncShown()
            }
        }
    }

    private func fullScreenCovers() async -> Bool {
        guard displays.hidesInFullScreen, let id = screenID else { return false }
        let own = ProcessInfo.processInfo.processIdentifier
        return await Task.detached(priority: .userInitiated) {
            FullScreenDetector.covers(display: id, excludingProcess: own)
        }.value
    }

    /// Slides the bar out over a full-screen app and back once it is gone.
    /// Never brings back a bar the user hid.
    private func syncShown() {
        guard isShown != isOnScreen, !isChangingPosition else { return }
        if isShown {
            slideIn()
            return
        }
        isOnScreen = false
        autoHide?.setEnabled(false, animated: false)
        tooltip.hide()
        slideOut { [weak self] in
            guard let self, !self.isOnScreen else { return }
            self.panel.orderOut(nil)
        }
    }

    // MARK: - Reordering

    private func reorderDidChange(_ active: Bool) {
        isReordering = active
        if active {
            tooltip.hide()
            hoveredID = nil
        }
    }

    // MARK: - Tooltip

    private func hover(_ id: String, _ hovering: Bool) {
        if hovering {
            guard !isReordering else { return }
            hoveredID = id
            guard let spec = TileCatalog.spec(id: id), let rect = screenRect(ofTile: id) else { return }
            tooltip.show(spec.title, beside: rect, bar: panel.frame, position: position)
        } else if hoveredID == id {
            hoveredID = nil
            tooltip.hide()
        }
    }

    // MARK: - Menus

    /// Right-click (or control-click) opens a tile's menu, or the bar's own
    /// menu on the empty part of the bar (video f10, f58, f62, f73).
    private func installMouseMonitor() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.rightMouseDown, .leftMouseDown]
        ) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, event.window === self.panel else { return false }
                self.tooltip.hide()
                let isContextClick = event.type == .rightMouseDown
                    || event.modifierFlags.contains(.control)
                guard isContextClick else { return false }
                self.showMenu(for: event)
                return true
            }
            return handled ? nil : event
        }
    }

    private func showMenu(for event: NSEvent) {
        // Tile frames are in the content's top-left space, whichever way the
        // tiles are stacked and however far they are scrolled.
        let location = event.locationInWindow
        let point = CGPoint(x: location.x, y: host.bounds.height - location.y)
        let hit = tileFrames.first { state.tileIDs.contains($0.key) && $0.value.contains(point) }?.key
        let menu = hit.flatMap(tileMenu(for:)) ?? barMenu()
        menu.appearance = appearance.theme.appearance.nsAppearance
        NSMenu.popUpContextMenu(menu, with: event, for: host)
    }

    private func tileMenu(for id: String) -> NSMenu? {
        guard let spec = TileCatalog.spec(id: id) else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        addItems(spec.menu, to: menu, spec: spec)
        if !menu.items.isEmpty, menu.items.last?.isSeparatorItem == false {
            menu.addItem(.separator())
        }
        menu.addItem(ShellMenuItem("Remove") { [weak self] in self?.removeTile(id: id) })
        return menu
    }

    private func addItems(_ items: [TileMenuItem], to menu: NSMenu, spec: TileSpec) {
        for item in items {
            switch item {
            case let .action(title, run):
                menu.addItem(ShellMenuItem(title) { run() })
            case let .customize(title):
                guard spec.settings != nil else { continue }
                menu.addItem(ShellMenuItem(title) { [weak self] in self?.openSettings(forTile: spec.id) })
            case .separator:
                // Never two in a row, never first.
                guard let last = menu.items.last, !last.isSeparatorItem else { continue }
                menu.addItem(.separator())
            case let .header(title):
                let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)
            case let .submenu(title, children):
                let submenu = NSMenu(title: title)
                submenu.autoenablesItems = false
                addItems(children, to: submenu, spec: spec)
                guard !submenu.items.isEmpty else { continue }
                let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                parent.submenu = submenu
                menu.addItem(parent)
            case let .dynamic(build):
                addItems(build(), to: menu, spec: spec)
            }
        }
    }

    private func barMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ShellMenuItem("Widgets…") { [weak self] in self?.onOpenLibrary?() })
        menu.addItem(ShellMenuItem("Settings…") { [weak self] in
            guard let self else { return }
            self.onOpenBarSettings?(self.panel.frame)
        })
        return menu
    }
}

/// The bar window. It never takes key focus, so clicking a tile leaves the
/// library's search field focused, and it may sit over the menu bar.
private final class DockBarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The notch bar is flush with the top of the screen, over the menu bar,
    /// and every bar parks past its edge when hidden.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Spots a full-screen Space from window bounds alone, which need no Screen
/// Recording permission: another app's window fills the display edge to
/// edge, menu bar included. A zoomed window stops at the menu bar, so it
/// does not count.
private enum FullScreenDetector {
    static func covers(display: CGDirectDisplayID, excludingProcess own: pid_t) -> Bool {
        let bounds = CGDisplayBounds(display)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let owner = info[kCGWindowOwnerPID as String] as? Int, owner != Int(own),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let rect = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: rect as CFDictionary)
            else { return false }
            return abs(frame.minX - bounds.minX) < 1 && abs(frame.minY - bounds.minY) < 1
                && abs(frame.width - bounds.width) < 1 && abs(frame.height - bounds.height) < 1
        }
    }
}

// MARK: - Views

/// Callbacks from the bar's SwiftUI content to its controller.
struct DockBarActions: Sendable {
    var remove: @MainActor @Sendable (String) -> Void = { _ in }
    var openSettings: @MainActor @Sendable (String) -> Void = { _ in }
    var hover: @MainActor @Sendable (String, Bool) -> Void = { _, _ in }
    var frame: @MainActor @Sendable (String, CGRect) -> Void = { _, _ in }
    var contentSize: @MainActor @Sendable (CGSize) -> Void = { _ in }
    /// A tile started (true) or stopped (false) being dragged along the bar.
    var reorder: @MainActor @Sendable (Bool) -> Void = { _ in }
    /// A dragged tile was let go at a new index.
    var move: @MainActor @Sendable (String, Int) -> Void = { _, _ in }
    /// The gear in the bar's top-right corner.
    var openBarSettings: @MainActor @Sendable () -> Void = {}
}

/// A tile being dragged to a new place on the bar.
private struct DockBarReorder: Sendable {
    let id: String
    /// Every tile's slot when the drag began, in the stack's space.
    let origins: [String: CGRect]
    /// The tile's index when the drag began.
    let start: Int
    var translation: CGSize = .zero
    /// The index the tile lands at if let go now.
    var target: Int
    /// Dragged well off the bar: letting go puts the tile back.
    var isOutside = false
}

struct DockBarView: View {
    let state: DockBarState
    let position: DockPosition
    /// Extra space above the tiles: the camera housing the notch bar hangs
    /// around.
    let topInset: CGFloat
    let actions: DockBarActions

    /// The tile being dragged to a new place, if any.
    @State private var reorder: DockBarReorder?
    /// Each tile's slot in the stack, as laid out (a lifted tile's offset
    /// aside).
    @State private var slots: [String: CGRect] = [:]
    /// The tile whose drag is live. Resets by itself when the gesture ends
    /// or is cancelled.
    @GestureState private var draggingID: String?

    nonisolated private static let stackSpace = "DockBarStack"
    /// How far past the bar's sides a dragged tile may go before letting go
    /// puts it back.
    private static let cancelReach: CGFloat = 36

    /// Rounded all round, except the notch bar's square top corners.
    private var shape: UnevenRoundedRectangle {
        let corner = TileMetrics.barCorner
        guard position == .notch else {
            return UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: corner,
                    bottomLeading: corner,
                    bottomTrailing: corner,
                    topTrailing: corner
                ),
                style: .continuous
            )
        }
        let bottom = max(corner, DockBarController.notchMinCorner)
        return UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(bottomLeading: bottom, bottomTrailing: bottom),
            style: .continuous
        )
    }

    var body: some View {
        let theme = AppearanceStore.shared.theme
        let axis: Axis.Set = position.isVertical ? .vertical : .horizontal
        let stack = position.isVertical
            ? AnyLayout(DockColumnLayout(spacing: TileMetrics.barGap))
            : AnyLayout(HStackLayout(spacing: TileMetrics.barGap))

        ScrollView(axis) {
            stack {
                ForEach(orderedIDs, id: \.self) { id in
                    let lifted = reorder?.id == id
                    DockBarTileHost(
                        id: id,
                        isEditing: state.isEditing,
                        isSelected: state.selectedID == id,
                        actions: actions
                    )
                        .scaleEffect(lifted ? 1.05 : 1)
                        .shadow(color: .black.opacity(lifted ? 0.28 : 0), radius: lifted ? 5 : 0, y: lifted ? 2 : 0)
                        .opacity(lifted && reorder?.isOutside == true ? 0.55 : 1)
                        .animation(.spring(duration: 0.2, bounce: 0.3), value: lifted)
                        .animation(.easeOut(duration: 0.15), value: reorder?.isOutside)
                        .offset(lifted ? liftOffset : .zero)
                        .zIndex(lifted ? 1 : 0)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.stackSpace)) } action: { frame in
                            slots[id] = frame
                        }
                        .gesture(reorderGesture(for: id))
                        // The lifted tile follows the pointer exactly; only
                        // its neighbours spring out of the way.
                        .transaction { if lifted { $0.animation = nil } }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .coordinateSpace(.named(Self.stackSpace))
            .padding(TileMetrics.barPadding)
            .padding(.top, topInset)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                actions.contentSize(size)
            }
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize, axes: axis)
        // The notch bar can be wider than its tiles (the camera housing).
        .defaultScrollAnchor(.center, for: .alignment)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shellSurface(
            shape,
            fill: theme.barFill,
            blur: theme.barBlur,
            border: theme.barBorder,
            borderWidth: theme.barBorderWidth,
            appearance: theme.appearance,
            openTop: position == .notch
        )
        .overlay(alignment: .topTrailing) {
            ZStack {
                // Edit mode puts the last tile's remove badge in this corner.
                if !state.isEditing && reorder == nil {
                    DockBarSettingsButton(action: actions.openBarSettings)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3, bounce: 0.3), value: state.isEditing)
            // Centred on the corner of the tile area, like a badge.
            .offset(
                x: -(TileMetrics.barPadding - DockBarSettingsButton.diameter / 2),
                y: topInset + TileMetrics.barPadding - DockBarSettingsButton.diameter / 2
            )
        }
        .environment(\.colorScheme, theme.appearance)
        .environment(\.tileContext, .bar)
        .environment(\.tileFillsWidth, position.isVertical)
        .onChange(of: draggingID) { _, id in
            draggingDidChange(id)
        }
    }

    // MARK: Reordering

    /// The bar's tiles, with a dragged tile where it would land.
    private var orderedIDs: [String] {
        guard let reorder, let from = state.tileIDs.firstIndex(of: reorder.id) else { return state.tileIDs }
        var ids = state.tileIDs
        ids.remove(at: from)
        ids.insert(reorder.id, at: min(reorder.target, ids.count))
        return ids
    }

    /// Where the lifted tile is drawn relative to its slot: under the
    /// pointer.
    private var liftOffset: CGSize {
        guard let reorder, let start = reorder.origins[reorder.id] else { return .zero }
        let translation = reorder.translation
        guard !position.isVertical else {
            // Rows are re-packed as tiles move, so the slot comes from layout.
            let slot = slots[reorder.id] ?? start
            return CGSize(
                width: start.minX - slot.minX + translation.width,
                height: start.minY - slot.minY + translation.height
            )
        }
        // Along a row the slot is the row's start plus every tile before it.
        // Working it out, rather than waiting for layout to report it, keeps
        // the tile under the pointer in the same frame its neighbours move.
        let ids = orderedIDs
        let rowStart = ids.compactMap { reorder.origins[$0]?.minX }.min() ?? start.minX
        let slotX = ids.prefix { $0 != reorder.id }.reduce(rowStart) { x, id in
            x + (reorder.origins[id]?.width ?? 0) + TileMetrics.barGap
        }
        return CGSize(width: start.minX + translation.width - slotX, height: 0)
    }

    /// Dragging a tile moves it along the bar. The small minimum distance
    /// leaves clicks to the tile's buttons, and a control inside a tile
    /// that drags (a slider) takes precedence over this gesture.
    private func reorderGesture(for id: String) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.stackSpace))
            .updating($draggingID) { _, dragging, _ in
                dragging = id
            }
            .onChanged { value in
                dragChanged(id, value)
            }
            .onEnded { _ in
                dragEnded(id)
            }
    }

    private func dragChanged(_ id: String, _ value: DragGesture.Value) {
        if reorder?.id != id {
            guard let start = state.tileIDs.firstIndex(of: id) else { return }
            let present = Set(state.tileIDs)
            reorder = DockBarReorder(
                id: id,
                origins: slots.filter { present.contains($0.key) },
                start: start,
                target: start
            )
            actions.reorder(true)
        }
        guard var current = reorder else { return }
        current.translation = value.translation
        current.isOutside = isOutside(value.location, current)
        let target = current.isOutside ? current.start : insertionIndex(current)
        guard target != current.target else {
            reorder = current
            return
        }
        current.target = target
        withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
            reorder = current
        }
    }

    /// Letting go on the bar moves the tile; off the bar it springs back.
    private func dragEnded(_ id: String) {
        guard let ended = reorder, ended.id == id else { return }
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
            reorder = nil
            if !ended.isOutside {
                actions.move(id, ended.target)
            }
        }
        actions.reorder(false)
    }

    /// A gesture cancelled without ending (its view went away) puts the
    /// tile back.
    private func draggingDidChange(_ id: String?) {
        guard id == nil, let stale = reorder?.id else { return }
        // `onEnded` runs around the same time; only clean up after it.
        Task { @MainActor in
            guard draggingID == nil, reorder?.id == stale else { return }
            withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                reorder = nil
            }
            actions.reorder(false)
        }
    }

    /// The index among the bar's tiles the dragged tile's centre falls at:
    /// past the middle of a tile along a row, below a whole row in a column.
    /// Measured against where tiles sat when the drag began, so a tile that
    /// moves out of the way never moves back under the pointer.
    private func insertionIndex(_ reorder: DockBarReorder) -> Int {
        guard let start = reorder.origins[reorder.id] else { return reorder.target }
        let center = CGPoint(x: start.midX + reorder.translation.width, y: start.midY + reorder.translation.height)
        return state.tileIDs.reduce(0) { count, other in
            guard other != reorder.id, let frame = reorder.origins[other] else { return count }
            let before = position.isVertical
                ? frame.maxY <= center.y || (frame.minY < center.y && frame.midX < center.x)
                : frame.midX < center.x
            return before ? count + 1 : count
        }
    }

    /// Dragged well past the bar's sides (above or below a row, beside a
    /// column).
    private func isOutside(_ point: CGPoint, _ reorder: DockBarReorder) -> Bool {
        let bounds = reorder.origins.values.reduce(CGRect.null) { $0.union($1) }
        guard !bounds.isNull else { return false }
        let reach = Self.cancelReach
        return position.isVertical
            ? point.x < bounds.minX - reach || point.x > bounds.maxX + reach
            : point.y < bounds.minY - reach || point.y > bounds.maxY + reach
    }
}

/// The left/right bar: tiles keep the user's order but are packed into rows
/// that all span the column, so the edges line up instead of a ragged stack
/// of different widths. The column is as wide as the widest tile; small
/// neighbours share a row (a clock beside the date), and every row's tiles
/// grow in proportion to fill it.
struct DockColumnLayout: Layout {
    var spacing: CGFloat

    struct Cache {
        var width: CGFloat = 0
        var rows: [[Int]] = []
        var ideals: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        var cache = Cache()
        cache.ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        cache.width = cache.ideals.map(\.width).max() ?? 0
        var row: [Int] = []
        var used: CGFloat = 0
        for (index, size) in cache.ideals.enumerated() {
            let needed = row.isEmpty ? size.width : used + spacing + size.width
            if !row.isEmpty, needed > cache.width + 0.5 {
                cache.rows.append(row)
                row = [index]
                used = size.width
            } else {
                row.append(index)
                used = needed
            }
        }
        if !row.isEmpty { cache.rows.append(row) }
        return cache
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache = makeCache(subviews: subviews)
    }

    private func rowHeight(_ row: [Int], _ cache: Cache) -> CGFloat {
        row.map { cache.ideals[$0].height }.max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let heights = cache.rows.map { rowHeight($0, cache) }
        let height = heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0))
        return CGSize(width: cache.width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        var y = bounds.minY
        for row in cache.rows {
            let height = rowHeight(row, cache)
            let natural = row.map { cache.ideals[$0].width }
            let total = natural.reduce(0, +)
            let extra = max(0, bounds.width - total - spacing * CGFloat(row.count - 1))
            var x = bounds.minX
            for (slot, index) in row.enumerated() {
                let width = natural[slot] + (total > 0 ? extra * natural[slot] / total : 0)
                subviews[index].place(
                    at: CGPoint(x: x + width / 2, y: y + height / 2),
                    anchor: .center,
                    proposal: ProposedViewSize(width: width, height: height)
                )
                x += width + spacing
            }
            y += height + spacing
        }
    }
}

/// One bar tile with its edit-mode remove badge.
private struct DockBarTileHost: View {
    let id: String
    let isEditing: Bool
    let isSelected: Bool
    let actions: DockBarActions

    var body: some View {
        if let spec = TileCatalog.spec(id: id) {
            spec.make()
                .environment(\.openTileSettings, { [actions, id] in actions.openSettings(id) })
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: TileMetrics.corner, style: .continuous)
                            .strokeBorder(TilePalette.focus, lineWidth: 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isEditing {
                        DockBarRemoveBadge { actions.remove(id) }
                            .offset(x: 2, y: -2)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.3, bounce: 0.3), value: isEditing)
                .onHover { actions.hover(id, $0) }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    actions.frame(id, frame)
                }
        }
    }
}

/// The small gear in the bar's top-right corner: opens Settings.
private struct DockBarSettingsButton: View {
    static let diameter: CGFloat = 15

    let action: @MainActor () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(TilePalette.ink.opacity(isHovering ? 0.95 : 0.6))
                .frame(width: Self.diameter, height: Self.diameter)
                .background { Circle().fill(TilePalette.tileFill) }
                .overlay { Circle().strokeBorder(TilePalette.tileBorder, lineWidth: 1) }
                .scaleEffect(isHovering ? 1.12 : 1)
                .contentShape(Circle().inset(by: -3))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .help("Settings")
    }
}

/// The circular minus badge of edit mode (video f10–f53).
private struct DockBarRemoveBadge: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus")
                .font(.system(size: 7.5, weight: .black))
                .foregroundStyle(TilePalette.onFocus)
                .frame(width: 13, height: 13)
                .background { Circle().fill(TilePalette.destructive) }
                .contentShape(Circle().inset(by: -3))
        }
        .buttonStyle(.plain)
        .help("Remove")
    }
}

// MARK: - Tooltip

/// The accent capsule naming the hovered tile, on the bar's inner side. A
/// separate click-through window, so the bar's own window stays exactly the
/// size of the bar.
@MainActor
private final class DockBarTooltip {
    /// Space between the bar and the tooltip.
    private static let gap: CGFloat = 5

    private let panel: NSPanel
    private let host = NSHostingView(rootView: DockBarTooltipView(title: ""))

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 22),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: DockBarController.level.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        host.sizingOptions = []
        panel.contentView = host
    }

    /// Shows `title` beside `tile` (in screen space), on the inner side of
    /// `bar`.
    func show(_ title: String, beside tile: NSRect, bar: NSRect, position: DockPosition) {
        host.rootView = DockBarTooltipView(title: title)
        let bounds = NSScreen.showing(bar)?.visibleFrame ?? bar
        let frame = position.frame(
            ofSize: host.fittingSize,
            beside: bar,
            centredOn: tile,
            gap: Self.gap,
            within: bounds,
            margin: 4
        )
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private struct DockBarTooltipView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.tileText(11, weight: .semibold))
            .foregroundStyle(TilePalette.onFocus)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background { Capsule().fill(TilePalette.focus) }
    }
}
