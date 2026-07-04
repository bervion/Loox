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
    /// the real value and flashes the copy toast).
    @ViewBuilder private func fieldRows(_ item: VaultItem) -> some View {
        let fields = item.fields.filter { !$0.isEmpty }
        ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
            if index > 0 { Divider().background(Color(rgb: env.theme.active.separatorOpaque)) }
            Button {
                env.clipboard.copy(field.value, label: appLabel(field.label))
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: appLabel(field.label)).vaultType(.caption).themedForeground(.secondary)
                        Text(verbatim: field.protected ? "••••••••" : field.value)
                            .vaultType(.body).themedForeground().lineLimit(1)
                    }
                    Spacer()
                    PolarisIcon(Icons.copy, size: 18).themedForeground(.secondary)
                }
                .padding(Space.gutter)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        HStack(spacing: Space.s3) {
            PolarisIcon(icon, size: Metric.iconTile)
                .foregroundStyle(Color(rgb: env.theme.active.accent))
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
        .padding(Space.gutter)
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
            .padding(Space.gutter)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}
