import AppKit
import SwiftUI

/// The menu-bar panel's window (fork-017): hung under the status item like a
/// SwiftUI `MenuBarExtra` in `.window` style — no arrow, a slab of Liquid
/// Glass (`NSGlassEffectView`, macOS 26+; a blurred material before) with
/// the SwiftUI content on it. `MenuBarExtra` itself needs a SwiftUI `App`,
/// and Parrot is an AppKit app; `NSPopover` brought an arrow and an opaque
/// background.
///
/// What the popover did for free, done here: the height follows the
/// content's `preferredContentSize` (top edge fixed), a click elsewhere or
/// Escape closes it, it fades in.
@MainActor
final class MenuBarPanel: NSPanel {
    /// The gap between the menu bar and the panel's top edge.
    static let gap: CGFloat = 5

    private let host: SizingController

    init(content: NSViewController) {
        host = SizingController(content: content)
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        // An NSPanel hides when its app stops being the active one: a click
        // in another app closes it, as the popover's `.transient` did.
        hidesOnDeactivate = true
        contentViewController = host
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
    }

    // A borderless window refuses key status by default; the panel needs it
    // for Escape and to close when it loses it.
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    /// Shows the panel under `anchor` (the status item's window, in screen
    /// coordinates), its left edge on the item's, kept on the screen.
    func show(under anchor: NSRect) {
        host.view.layoutSubtreeIfNeeded()
        let size = host.contentSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        var x = anchor.minX
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        let top = anchor.minY - Self.gap
        setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        // The shadow from the rounded content, not the default window shape.
        invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
    }

    /// Resizes to `size`, the top edge fixed — at once: a window resize
    /// can't run alongside SwiftUI's animations (docs/fork-ui-notes.md §2).
    fileprivate func fit(_ size: NSSize) {
        guard size != frame.size else { return }
        setFrame(NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
        invalidateShadow()
    }
}

/// Holds the SwiftUI content on the glass and follows its size: the hosting
/// controller (`sizingOptions = .preferredContentSize`) publishes its ideal
/// size, and AppKit tells the parent through
/// `preferredContentSizeDidChange(for:)`.
@MainActor
private final class SizingController: NSViewController {
    private let content: NSViewController

    init(content: NSViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        addChild(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var contentSize: NSSize { content.preferredContentSize }

    override func loadView() {
        let inner = content.view
        inner.autoresizingMask = [.width, .height]
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = PanelStyle.panelRadius
            glass.contentView = inner
            view = Self.rounded(glass)
        } else {
            let material = NSVisualEffectView()
            material.material = .popover
            material.state = .active
            material.blendingMode = .behindWindow
            material.maskImage = PanelStyle.roundedMask(radius: PanelStyle.panelRadius)
            inner.frame = material.bounds
            material.addSubview(inner)
            view = Self.rounded(material)
        }
    }

    /// `view` clipped to the glass's corners. Only the glass was rounded, so
    /// the window server drew the shadow and its 1 pt rim on a plain
    /// window's shape: square at the bottom, small corners at the top, out
    /// past the glass (photographed in quill with and without the shadow,
    /// 2026-11-24).
    private static func rounded(_ view: NSView) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = PanelStyle.panelRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        return container
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        (view.window as? MenuBarPanel)?.fit(viewController.preferredContentSize)
    }
}
