import SwiftUI

/// Payment — a list of the ACTIVE persona's saved cards (brand + masked number). Tap a card
/// to view it; Add card opens the editor. Scoped to the active persona, so an anonymous
/// persona's cards never appear here (fixes the previously unscoped Profile query — INV-R03).
struct PaymentCardsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var editing: EditorTarget?

    /// Cards for the ACTIVE persona only — never `repository.items` (which would leak other
    /// personas' cards into this profile).
    private var cards: [VaultItem] {
        guard let persona = env.repository.activePersona else {
            return env.repository.items.filter { $0.category == .card }
        }
        return env.repository.items(for: persona).filter { $0.category == .card }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s5) {
                if cards.isEmpty {
                    emptyState
                } else {
                    ProfileGroupCard {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                            cardRow(card)
                            if index < cards.count - 1 {
                                Rectangle()
                                    .fill(Color(rgb: env.theme.active.separator))
                                    .frame(height: 0.5)
                                    .padding(.leading, Space.s4 + 40 + Space.s3)
                            }
                        }
                    }
                }
                addButton
            }
            .padding(Space.gutter)
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle("Payment")
        .platformNavigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { ItemEditorScreen(target: $0) }
    }

    private func cardRow(_ card: VaultItem) -> some View {
        NavigationLink(value: card.id) {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(rgb: env.theme.active.accentSoft))
                        .frame(width: 40, height: 40)
                    VaultIcon(Icons.creditCard, size: 20).themedForeground(.accentText)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: cardTitle(card)).vaultType(.body).themedForeground().lineLimit(1)
                    Text(verbatim: maskedNumber(card))
                        .vaultType(.subhead).themedForeground(.secondary).monospacedDigit()
                }
                Spacer(minLength: Space.s2)
                if let brand = brandName(card) {
                    Text(verbatim: brand).vaultType(.caption).themedForeground(.tertiary)
                }
                VaultIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
            }
            .padding(.horizontal, Space.s4)
            .frame(minHeight: Metric.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button { editing = .new(.card) } label: {
            HStack(spacing: Space.s2) {
                VaultIcon(Icons.addCircle, size: Metric.iconInline)
                Text("Add card")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.themedProminent)
    }

    private var emptyState: some View {
        VStack(spacing: Space.s4) {
            ZStack {
                Circle().fill(Color(rgb: env.theme.active.accentSoft)).frame(width: 92, height: 92)
                VaultIcon(Icons.creditCard, size: 40).themedForeground(.accent)
            }
            VStack(spacing: Space.s2) {
                Text("No payment card yet").vaultType(.headline).themedForeground()
                Text("Add a card to keep it handy for autofill.")
                    .vaultType(.callout).themedForeground(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s8)
    }

    // MARK: Field helpers — stable English labels, the same source the card editors key off.

    private func field(_ card: VaultItem, _ label: String) -> String? {
        let value = card.fields.first(where: { $0.label == label })?.value
        return (value?.isEmpty == false) ? value : nil
    }
    private func cardTitle(_ card: VaultItem) -> String {
        if !card.title.isEmpty { return card.title }
        return field(card, "Cardholder") ?? appString("Card")
    }
    private func maskedNumber(_ card: VaultItem) -> String {
        guard let raw = field(card, "Card Number") else { return "••••" }
        let last4 = String(PaymentCard.digitsOnly(raw).suffix(4))
        return last4.isEmpty ? "••••" : "•••• \(last4)"
    }
    private func brandName(_ card: VaultItem) -> String? {
        guard let raw = field(card, "Card Number") else { return nil }
        return PaymentCard.brand(for: raw)?.displayName
    }
}
