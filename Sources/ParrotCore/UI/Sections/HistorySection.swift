import AppKit
import SwiftUI

/// Dernières dictées (the panel, fork-015): the last day's dictations, to
/// copy one again. Folded, the card shows the latest; unfolded, the others
/// slide in under it, in a list that scrolls. A click on a dictation copies
/// it. Styled as the panel's other cards (fork-017).
struct HistorySection: View {
    @ObservedObject var history: DictationHistory
    /// Held by the panel's model, which lives as long as Parrot: the
    /// section opens as it was left.
    @Binding var expanded: Bool
    @State private var copied: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            title
            if history.entries.isEmpty {
                PanelCard {
                    HStack(spacing: 10) {
                        PanelIcon(name: "clock")
                        Text("Tes dictées des dernières 24 h apparaîtront ici.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: PanelStyle.rowHeight + 6)
                }
            } else if let latest = history.entries.first {
                // The latest stays in place; unfolding slides the others in
                // under it.
                PanelCard {
                    row(latest, lines: expanded ? 2 : 1)
                    if expanded, history.entries.count > 1 {
                        rest
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: PanelStyle.cardRadius, style: .continuous))
                // Animated here, not with `withAnimation` around the toggle:
                // a global transaction also animated the popover's resize,
                // sliding the whole panel from a centred position
                // (docs/fork-ui-notes.md).
                .animation(.easeInOut(duration: 0.25), value: expanded)
            }
        }
    }

    /// The section's title, which folds and unfolds it.
    private var title: some View {
        Button {
            expanded.toggle()
        } label: {
            PanelSectionTitle(title: "Dernières dictées") {
                if history.entries.count > 1 {
                    Text("\(history.entries.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.25), value: expanded)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(history.entries.count < 2)
    }

    /// All but the latest, scrolling past about four.
    @ViewBuilder
    private var rest: some View {
        let scrolls = history.entries.count > 5
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(history.entries.dropFirst()) { entry in
                    Divider().padding(.horizontal, 10)
                    row(entry, lines: 2)
                }
            }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: 220)
        // Rows fade at the bottom edge instead of being cut.
        .mask {
            if scrolls {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.9),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            } else {
                Rectangle()
            }
        }
    }

    private func row(_ entry: DictationHistory.Entry, lines: Int) -> some View {
        HistoryRow(entry: entry, lines: lines, copied: copied == entry.date) { copy(entry) }
    }

    private func copy(_ entry: DictationHistory.Entry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        copied = entry.date
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copied == entry.date { copied = nil }
        }
    }
}

/// One dictation in the card, its time on the right — a copy icon on
/// hover, a check once copied. A click anywhere on the row copies.
private struct HistoryRow: View {
    let entry: DictationHistory.Entry
    let lines: Int
    let copied: Bool
    let copy: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: copy) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry.text)
                    .lineLimit(lines)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // The time, or on hover what a click does.
                Group {
                    if copied {
                        Label("Copié", systemImage: "checkmark").foregroundStyle(Color.accentColor)
                    } else if hovering {
                        Label("Copier", systemImage: "doc.on.doc").foregroundStyle(.secondary)
                    } else {
                        Text(DictationHistory.label(entry.date, now: Date())).foregroundStyle(.tertiary)
                    }
                }
                .font(.caption.monospacedDigit())
                .labelStyle(.iconOnly)
                .frame(minWidth: 34, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: PanelStyle.cardRadius - 3, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.07 : 0))
                    .padding(3)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
