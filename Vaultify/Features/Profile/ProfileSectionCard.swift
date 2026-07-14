import SwiftUI

/// One Profile section (Identity or Payment): a titled card that shows the selected vault
/// item's tap-to-copy fields — or an empty state — with an Edit affordance in the header and
/// a trailing "choose" row that picks which vault item of this type to show (or creates one).
///
/// Both sections are symmetric, so this is shared: the caller wires the selection source
/// (synced default identity vs device-local card preference) via the closures.
struct ProfileSectionCard: View {
    let title: LocalizedStringKey
    /// Shown when nothing is selected (no item of this type is chosen yet).
    let emptyTitle: LocalizedStringKey
    /// Label of the trailing picker row, e.g. "Change identity" / "Choose a card".
    let chooseLabel: LocalizedStringKey
    /// Section glyph (person / credit card) used in the picker row and empty state.
    let icon: String
    let selected: VaultItem?
    /// All vault items of this type — the picker menu's choices.
    let pool: [VaultItem]
    let onEdit: () -> Void
    let onChoose: (VaultItem) -> Void
    let onCreate: () -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            header
            card
        }
    }

    // MARK: Header (title + edit)

    private var header: some View {
        HStack {
            Text(title).vaultType(.sectionLabel).themedForeground(.secondary)
            Spacer()
            if selected != nil {
                Button(action: onEdit) {
                    Text("Edit")
                        .vaultType(.subhead)
                        .foregroundStyle(env.theme.uiTint)
                        .frame(minHeight: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Card body

    private var card: some View {
        VStack(spacing: 0) {
            if let selected {
                fieldRows(selected)
            } else {
                emptyState
            }
            Divider().background(Color(rgb: env.theme.active.separatorOpaque))
            chooseRow
        }
        .background(VaultColors.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Each non-empty field as a tap-to-copy row (protected values stay masked; the tap copies
    /// the real value and flashes the same accent feedback as the item-detail rows).
    @ViewBuilder private func fieldRows(_ item: VaultItem) -> some View {
        let fields = item.fields.filter { !$0.isEmpty }
        ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
            if index > 0 { Divider().background(Color(rgb: env.theme.active.separatorOpaque)) }
            ProfileCopyFieldRow(label: appLabel(field.label),
                                value: field.value,
                                protected: field.protected)
        }
    }

    private var emptyState: some View {
        HStack(spacing: Space.s3) {
            PolarisIcon(icon, size: Metric.iconTile)
                .foregroundStyle(Color(rgb: env.theme.active.accentText))
                .frame(width: Metric.controlLarge, height: Metric.controlLarge)
                .background(Color(rgb: env.theme.active.accentSoft),
                            in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(emptyTitle).vaultType(.body).themedForeground()
                Text("Choose one below or add a new one.")
                    .vaultType(.caption).themedForeground(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
    }

    /// Trailing picker row — a menu listing every vault item of this type (checkmark on the
    /// current one) plus a "Create new" action, so the user can switch or add from here.
    private var chooseRow: some View {
        Menu {
            ForEach(pool) { candidate in
                Button { onChoose(candidate) } label: {
                    Label {
                        Text(verbatim: candidate.title.isEmpty ? "Untitled" : candidate.title)
                    } icon: {
                        if candidate.id == selected?.id { PolarisIcon(Icons.checkCircle) }
                    }
                }
            }
            if !pool.isEmpty { Divider() }
            Button(action: onCreate) { Label { Text("Create new") } icon: { PolarisIcon(Icons.add) } }
        } label: {
            HStack(spacing: Space.s3) {
                PolarisIcon(icon, size: Metric.iconInline).themedForeground(.secondary)
                Text(chooseLabel).vaultType(.body).themedForeground()
                Spacer()
                PolarisIcon(Icons.chevronDown, size: 13).themedForeground(.tertiary)
            }
            .padding(Space.s4)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

/// Tap-to-copy row with the SAME feedback vocabulary as the item-detail rows:
/// accent flash, value line swaps to "Copied", the copy glyph morphs to a
/// check, then everything settles back after 1.2 s. The clipboard service owns
/// the haptic — the row never fires its own.
private struct ProfileCopyFieldRow: View {
    @Environment(AppEnvironment.self) private var env
    let label: String
    let value: String
    let protected: Bool

    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        let theme = env.theme.active
        Button {
            env.clipboard.copy(value, label: label)
            copied = true
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeOut(duration: 0.3)) { copied = false }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: label)
                        .vaultType(.caption)
                        .foregroundStyle(copied ? theme.color(.onAccent).opacity(0.85)
                                                : theme.color(.secondary))
                    Text(verbatim: copied ? appString("Copied")
                                          : (protected ? "••••••••" : value))
                        .vaultType(.body)
                        .foregroundStyle(copied ? theme.color(.onAccent) : theme.color(.primary))
                        .lineLimit(1)
                }
                Spacer()
                CopyMorphIcon(copied: copied, size: 18)
                    .foregroundStyle(copied ? theme.color(.onAccent) : theme.color(.secondary))
            }
            .padding(Space.s4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(copied ? theme.color(.accent) : Color.clear)
        .animation(.easeOut(duration: 0.18), value: copied)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityHint(Text("Double tap to copy"))
    }
}
