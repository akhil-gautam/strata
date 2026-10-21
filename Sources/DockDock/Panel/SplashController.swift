import AppKit
import SwiftUI

/// The launch splash (video f01–f06): a black screen, the app mark alone,
/// then the mark slides left as "DockDock" fades in beside it, then the
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
                Text("DockDock")
                    .font(.system(size: 56, weight: .semibold))
                    .tracking(-0.8)
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

/// The app mark: a black rounded square with a light pill near its bottom —
/// a dock.
private struct SplashMark: View {
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        shape
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.13), Color(white: 0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.97), Color(white: 0.74)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.72, height: size * 0.185)
                    .shadow(color: .white.opacity(0.18), radius: 4)
                    .padding(.bottom, size * 0.13)
            }
            .frame(width: size, height: size)
    }
}
