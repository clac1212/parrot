import AppKit
import SwiftUI

/// The small glass panel that offers to learn a correction (fork-019), at the
/// top of the screen under the menu bar, where the dictation indicator is.
///
/// It never takes the keyboard: a non-activating panel that can't become
/// key, so the field being edited keeps the focus (and `CorrectionWatch`
/// keeps watching it); its buttons answer the first click. It leaves on its
/// own after `duration`, held while the pointer is over it.
@MainActor
final class CorrectionOfferPanel {
    /// Long enough to read two words and decide; FluidVoice's is 10 s.
    nonisolated static let duration: TimeInterval = 8
    /// After the pointer leaves it.
    nonisolated static let lingerAfterHover: TimeInterval = 3
    static let radius: CGFloat = 16

    private var window: NSPanel?
    private var answer: ((Bool) -> Void)?
    /// Bumped by every show, hover and answer, so a timer only closes its own.
    private var generation = 0

    /// Shows `wrong → right`, replacing any offer still up (which counts as
    /// no answer). `answered(true)` on Ajouter; `false` on the close button or
    /// when it times out.
    func show(wrong: String, right: String, answered: @escaping (Bool) -> Void) {
        answer = nil
        let view = CorrectionOfferView(
            wrong: wrong, right: right,
            add: { [weak self] in self?.close(accepted: true) },
            dismiss: { [weak self] in self?.close(accepted: false) },
            hover: { [weak self] inside in self?.hovered(inside) }
        )
        let window = self.window ?? Self.makeWindow()
        self.window = window
        let host = FirstClickHostingView(rootView: view)
        let size = host.fittingSize
        Self.contain(host, in: window)
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        window.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.maxY - 10 - size.height,
                               width: size.width, height: size.height), display: true)
        answer = answered
        if !window.isVisible {
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
        // Also when an offer replaces one fading out.
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; window.animator().alphaValue = 1 }
        closeLater(after: Self.duration)
    }

    private func hovered(_ inside: Bool) {
        generation += 1
        if !inside { closeLater(after: Self.lingerAfterHover) }
    }

    private func closeLater(after delay: TimeInterval) {
        generation += 1
        let shown = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == shown else { return }
                self.close(accepted: false)
            }
        }
    }

    private func close(accepted: Bool) {
        generation += 1
        let answer = self.answer
        self.answer = nil
        answer?(accepted)
        guard let window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Shown again meanwhile: stay.
                guard self?.answer == nil else { return }
                window.orderOut(nil)
            }
        }
    }

    private static func makeWindow() -> NSPanel {
        let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.becomesKeyOnlyIfNeeded = true
        return window
    }

    /// Glass on macOS 26+, a blurred material before, as `MenuBarPanel`.
    private static func contain(_ host: NSView, in window: NSPanel) {
        host.autoresizingMask = [.width, .height]
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = radius
            glass.contentView = host
            window.contentView = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .popover
            material.state = .active
            material.blendingMode = .behindWindow
            material.maskImage = PanelStyle.roundedMask(radius: radius)
            material.addSubview(host)
            window.contentView = material
            host.frame = material.bounds
        }
    }
}

/// Buttons in a panel that is never key answer the first click instead of
/// spending it on focusing the window.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct CorrectionOfferView: View {
    let wrong: String
    let right: String
    var add: () -> Void = {}
    var dismiss: () -> Void = {}
    var hover: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(wrong).strikethrough().foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    Text(right).fontWeight(.semibold)
                }
                .lineLimit(1)
                Text("Ajouter au dictionnaire ?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Ajouter", action: add)
                .panelButton(prominent: true)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Ne pas ajouter")
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .onHover(perform: hover)
    }
}
