import AppKit
import SwiftUI

/// The launch splash (video f01–f06): a black screen, the app mark alone,
/// then the mark slides left as "Strata" fades in beside it, then the
/// whole screen fades away.
@MainActor
final class SplashController {
    private var window: NSWindow?

    /// Mark alone, then the name joins it.
    private static let markAlone: Duration = .milliseconds(1100)
    /// Mark and name together before the fade.
    private static let hold: Duration = .milliseconds(1500)
    private static let fadeOut: TimeInterval = 0.7

    /// Shows the splash; `onFinish` runs as it starts fading out, so the bar
    /// can come in underneath.
    func show(onFinish: @escaping @MainActor () -> Void) {
        guard let screen = NSScreen.screens.first else {
            onFinish()
            return
        }
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false

        let model = SplashModel()
        window.contentView = NSHostingView(rootView: SplashView(model: model))
        window.setFrame(screen.frame, display: true)
        window.alphaValue = 0
        window.orderFrontRegardless()
        self.window = window

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            window.animator().alphaValue = 1
        }

        Task { @MainActor [weak self] in
            withAnimation(.spring(duration: 0.6, bounce: 0.2)) {
                model.showsMark = true
            }
            try? await Task.sleep(for: Self.markAlone)
            withAnimation(.spring(duration: 0.75, bounce: 0.12)) {
                model.showsName = true
            }
            try? await Task.sleep(for: Self.hold)
            onFinish()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeOut
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    window.orderOut(nil)
                    self?.window = nil
                }
            }
        }
    }
}

@MainActor
@Observable
private final class SplashModel {
    var showsMark = false
    var showsName = false
}

private struct SplashView: View {
    let model: SplashModel

    private static let markSize: CGFloat = 96
    private static let spacing: CGFloat = 32

    @State private var nameWidth: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black
            HStack(spacing: Self.spacing) {
                SplashMark(size: Self.markSize)
                    .scaleEffect(model.showsMark ? 1 : 0.86)
                    .opacity(model.showsMark ? 1 : 0)
                // The wordmark: light capitals, widely spaced.
                Text("STRATA")
                    .font(.system(size: 44, weight: .light))
                    .tracking(18)
                    .foregroundStyle(Color(white: 0.93))
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { nameWidth = $0 }
                    .opacity(model.showsName ? 1 : 0)
                    .offset(x: model.showsName ? 0 : -18)
            }
            // While the name is hidden the mark sits alone in the centre;
            // as the name fades in the pair centres together.
            .offset(x: model.showsName ? 0 : (nameWidth + Self.spacing) / 2)
        }
        .ignoresSafeArea()
    }
}

/// The app mark: the bundle's icon, the Strata squircle.
private struct SplashMark: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            // The icon art leaves the standard macOS margin around the
            // squircle; scale it so the squircle itself is `size` wide.
            .frame(width: size / 0.805, height: size / 0.805)
            .frame(width: size, height: size)
    }
}
