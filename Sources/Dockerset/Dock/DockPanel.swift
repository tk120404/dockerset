import AppKit
import Combine
import SwiftUI

final class DockPanel: NSPanel {
    // Lets popovers (folder stacks, calendar details) receive keyboard and scroll input.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the borderless panel that hosts the custom Dock and keeps it pinned to a screen edge.
@MainActor
final class DockPanelController {
    private let panel: DockPanel
    private let state: AppState
    private var contentSize: CGSize = .zero
    private var cancellables = Set<AnyCancellable>()
    private var autoHideTimer: Timer?
    private var revealed = true
    private var lastHover = Date()
    private var nativeGeometry = NativeDock.Geometry.current
    private var nativeTimer: Timer?

    init(state: AppState) {
        self.state = state
        panel = DockPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // SwiftUI draws the shadow, so it follows the rounded shape
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // Only this controller sizes the panel. The hosting view must not drive the window size: when both did,
        // they fought during layout and AppKit threw ("more Update Constraints passes than views").
        let hosting = NSHostingView(rootView: DockView { [weak self] size in self?.contentSizeChanged(size) }
            .environmentObject(state))
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.width, .height]
        let container = NSView(frame: panel.contentLayoutRect)
        hosting.frame = container.bounds
        container.addSubview(hosting)
        panel.contentView = container

        state.$config
            .map(\.mode)
            .removeDuplicates()
            .sink { [weak self] mode in self?.updateVisibility(mode) }
            .store(in: &cancellables)
        state.$config
            .map(\.appearance)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.layoutPanel(animated: false) }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutPanel(animated: false) }
        }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickAutoHide() }
        }
        // Follow changes made to the macOS Dock elsewhere (System Settings, ⌥⌘D).
        nativeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let current = NativeDock.Geometry.current
                if current != self.nativeGeometry {
                    self.nativeGeometry = current
                    self.layoutPanel(animated: true)
                }
            }
        }
    }

    private var screen: NSScreen? { NSScreen.screens.first }

    private func updateVisibility(_ mode: DockMode) {
        if mode == .native {
            panel.orderOut(nil)
        } else {
            layoutPanel(animated: false)
            panel.orderFrontRegardless()
        }
    }

    private func contentSizeChanged(_ size: CGSize) {
        let size = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        guard size.width > 0, size.height > 0, size != contentSize else { return }
        contentSize = size
        // Never resize the window from inside SwiftUI's layout pass.
        DispatchQueue.main.async { [weak self] in
            self?.fitToScreen()
            self?.layoutPanel(animated: false)
        }
    }

    /// Shrinks the icons when the Dock is longer than the screen edge, and grows them back when there's room.
    /// Paddings don't scale, so it can take a couple of passes; the 92–100% band keeps it from oscillating.
    private func fitToScreen() {
        guard let screen else { return }
        let vertical = state.config.appearance.position != .bottom
        let available = (vertical ? screen.visibleFrame.height : screen.visibleFrame.width) - 16
        let length = vertical ? contentSize.height : contentSize.width
        guard length > 0 else { return }
        var scale = state.fitScale
        if length > available {
            scale = max(0.4, scale * available / length * 0.98)
        } else if scale < 1 && length < available * 0.92 {
            scale = min(1, scale * available / length * 0.95)
        } else {
            return
        }
        if abs(scale - state.fitScale) > 0.005 { state.fitScale = scale }
    }

    private func layoutPanel(animated: Bool) {
        guard let screen, contentSize != .zero else { return }
        let a = state.config.appearance
        // visibleFrame excludes the menu bar and a pinned macOS Dock, but not an auto-hiding one,
        // which would slide up on top of us. In "Both" mode, keep clear of where it appears.
        var visible = screen.visibleFrame
        let full = screen.frame
        if state.config.mode == .both, nativeGeometry.autohide, nativeGeometry.orientation == a.position {
            let inset = nativeGeometry.footprint
            switch a.position {
            case .bottom:
                visible.origin.y = max(visible.minY, full.minY + inset)
                visible.size.height = full.maxY - visible.origin.y - (full.maxY - screen.visibleFrame.maxY)
            case .left:
                visible.origin.x = max(visible.minX, full.minX + inset)
            case .right:
                visible.size.width = min(visible.maxX, full.maxX - inset) - visible.minX
            }
        }
        let s = contentSize
        let hidden = a.autoHide && !revealed

        var origin: CGPoint
        switch a.position {
        case .bottom:
            origin = CGPoint(x: visible.midX - s.width / 2, y: hidden ? full.minY - s.height : visible.minY)
        case .left:
            origin = CGPoint(x: hidden ? full.minX - s.width : visible.minX, y: visible.midY - s.height / 2)
        case .right:
            origin = CGPoint(x: hidden ? full.maxX : visible.maxX - s.width, y: visible.midY - s.height / 2)
        }
        let frame = NSRect(origin: origin, size: s).integral
        guard frame != panel.frame else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func tickAutoHide() {
        let a = state.config.appearance
        guard state.config.mode != .native, a.autoHide, let screen else {
            if !revealed {
                revealed = true
                layoutPanel(animated: true)
            }
            return
        }
        let mouse = NSEvent.mouseLocation
        let f = screen.frame
        let atEdge: Bool = switch a.position {
        case .bottom: mouse.y <= f.minY + 2 && mouse.x >= f.minX && mouse.x <= f.maxX
        case .left: mouse.x <= f.minX + 2 && mouse.y >= f.minY && mouse.y <= f.maxY
        case .right: mouse.x >= f.maxX - 2 && mouse.y >= f.minY && mouse.y <= f.maxY
        }
        let overPanel = revealed && panel.frame.insetBy(dx: -8, dy: -8).contains(mouse)
        let popoverOpen = !(panel.childWindows ?? []).isEmpty

        if atEdge || overPanel || popoverOpen {
            lastHover = Date()
            if !revealed {
                revealed = true
                layoutPanel(animated: true)
            }
        } else if revealed && Date().timeIntervalSince(lastHover) > 0.7 {
            revealed = false
            layoutPanel(animated: true)
        }
    }
}
