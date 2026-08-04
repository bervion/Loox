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
            // Apple grouped-card divider: inset to the text's leading edge,
            // running through to the trailing edge — never full-bleed left.
            Divider().background(Color(rgb: env.theme.active.separatorOpaque))
                .padding(.leading, Space.s4)
            chooseRow
        }
        .background(VaultColors.surface)
        // CLIP, not just a background shape: a row's copy flash paints edge to edge, so
        // without this the square flash overhangs the card's rounded corners.
        .vaultCornerRadius(Radius.md)
    }

    /// Each non-empty field, rendered by the SAME row the item-detail screen uses. This card
    /// used to carry its own simplified copy row, which drifted: notes collapsed to one inline
    /// line with no Markdown, and the flash used the theme accent instead of the app's fixed
    /// copy-flash pair. Sharing the real row keeps identity fields rendering exactly like the
    /// vault — Markdown notes, per-kind value treatment, reveal for protected values.
    ///
    /// `readOnly`: the card has its own Edit button, so the row's mutation affordances
    /// ("Protect…") stay out; copy, reveal, and Large Type remain.
    @ViewBuilder private func fieldRows(_ item: VaultItem) -> some View {
        let fields = item.fields.filter { !$0.isEmpty }
        ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
            if index > 0 {
                Divider().background(Color(rgb: env.theme.active.separatorOpaque))
                    .padding(.leading, Space.s4)
            }
            DetailFieldRow(field: field, category: item.category, readOnly: true)
        }
    }

    private var emptyState: some View {
        HStack(spacing: Space.s3) {
            VaultIcon(icon, size: Metric.iconTile)
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
                        Text(verbatim: candidate.title.isEmpty ? appString("Untitled") : candidate.title)
                    } icon: {
                        if candidate.id == selected?.id { VaultIcon(Icons.checkCircle) }
                    }
                }
            }
            if !pool.isEmpty { Divider() }
            Button(action: onCreate) { Label { Text("Create new") } icon: { VaultIcon(Icons.add) } }
        } label: {
            HStack(spacing: Space.s3) {
                VaultIcon(icon, size: Metric.iconInline).themedForeground(.secondary)
                Text(chooseLabel).vaultType(.body).themedForeground()
                Spacer()
                VaultIcon(Icons.chevronDown, size: 13).themedForeground(.tertiary)
            }
            .padding(Space.s4)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}
