import AppKit
import SwiftUI

/// The menu-bar panel's look (fork-017): grouped cards inset from the
/// popover's edge, small grey section titles, an SF Symbol per row, and
/// Liquid Glass buttons on macOS 26+ (materials-era pills before). The
/// glass slab under it all is `MenuBarPanel`'s, so nothing here paints the
/// panel's background. Upstream's `Pill.swift` stays for the onboarding and
/// Settings windows.
enum PanelStyle {
    /// The glass slab's corners (`MenuBarPanel`).
    static let panelRadius: CGFloat = 18
    /// Cards sit this far from the glass's edge.
    static let inset: CGFloat = 8
    /// Concentric with the glass's corners: its radius minus the inset.
    static let cardRadius: CGFloat = panelRadius - inset
    /// A card's fill: darker than the glass in dark mode, lighter in light
    /// mode, so the glass shows as a rim around the cards (as RunCat Neo's
    /// `MenuBarExtra`).
    static let cardFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.black.withAlphaComponent(0.22)
            : NSColor.white.withAlphaComponent(0.55)
    })
    static let rowHeight: CGFloat = 34
    /// Rows' leading edge after the icon column, for dividers.
    static let textLeading: CGFloat = 38
}

/// A small grey title above a card, as in Control Center and Settings.
struct PanelSectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 8)
    }
}

extension PanelSectionTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title, trailing: { EmptyView() })
    }
}

/// A rounded group of rows on the glass: a fill that sets it apart from the
/// glass rim, and a hairline. Content, not a control: no glass of its own
/// (Apple: glass is for the controls layer; glass on glass muddies).
struct PanelCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: PanelStyle.cardRadius, style: .continuous)
                .fill(PanelStyle.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PanelStyle.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

/// One line of a card: an icon, a label, and a control on the right.
struct PanelRow<Control: View>: View {
    let icon: String
    let label: String
    @ViewBuilder var control: () -> Control

    init(_ label: String, icon: String, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.icon = icon
        self.control = control
    }

    var body: some View {
        HStack(spacing: 10) {
            PanelIcon(name: icon)
            Text(label)
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: PanelStyle.rowHeight + 6)
    }
}

/// The SF Symbol at the start of a row, in a fixed column.
struct PanelIcon: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 18)
    }
}

/// A divider between rows, starting after the icon column.
struct PanelDivider: View {
    var body: some View {
        Divider().padding(.leading, PanelStyle.textLeading)
    }
}

extension View {
    /// Liquid Glass on macOS 26+, the pill before.
    @ViewBuilder
    func panelButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            buttonStyle(PillButtonStyle(primary: prominent))
        }
    }
}

/// A pop-up menu shown as a glass button: the hotkey.
struct PanelMenu<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26, *) {
            Menu(content: content) {
                Text(title)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .fixedSize()
        } else {
            PillMenu(title: title, content: content)
        }
    }
}
