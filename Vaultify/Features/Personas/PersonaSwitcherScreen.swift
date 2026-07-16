import SwiftUI

/// Persona ("identity") switcher: list, switch, create, edit, and delete
/// personas — including the isolation policy that drives suggestion/search
/// isolation. Avatars remain out of scope.
struct PersonaSwitcherScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var editorTarget: PersonaEditorTarget?
    @State private var blockedReason: PersonaRemovalGate?
    @State private var pendingDelete: Persona?
    @State private var paywallContext: LooxPaywallContext?

    var body: some View {
        List {
            Section {
                ForEach(env.repository.personas) { persona in
                    Button { select(persona) } label: { row(persona) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { attemptDelete(persona) } label: {
                                Label { Text("Delete") } icon: { PolarisIcon(Icons.trash) }
                            }
                            Button { editorTarget = .edit(persona) } label: {
                                Label { Text("Edit") } icon: { PolarisIcon(Icons.edit) }
                            }
                            .tint(Color(rgb: env.theme.active.accent))
                        }
                }
            }
            .listRowBackground(VaultColors.surface)

            Section {
                Button { attemptCreate() } label: {
                    Label { Text("Add persona") } icon: { PolarisIcon(Icons.addCircle) }
                }
            }
            .listRowBackground(VaultColors.surface)
        }
        .navigationTitle(Text("Personas"))
        .sheet(item: $editorTarget) { PersonaEditorSheet(target: $0) }
        .sheet(item: $paywallContext) { context in NavigationStack { LooxPaywallScreen(context: context) } }
        .alert(Text("Can’t delete this identity"), isPresented: blockedBinding, presenting: blockedReason) { _ in
            Button("OK", role: .cancel) {}
        } message: { reason in
            Text(reason == .lastPersona
                 ? "You need at least one identity."
                 : "Make another identity the default first.")
        }
        .confirmationDialog("Delete this identity permanently?", isPresented: deleteBinding,
                            titleVisibility: .visible, presenting: pendingDelete) { persona in
            Button("Delete permanently", role: .destructive) {
                Haptics.error()
                try? env.repository.deletePersona(persona)
            }
        } message: { _ in
            Text("This also permanently deletes its private email addresses. Its logins and other items move to your default identity.")
        }
    }

    /// Over-quota upsell gate (§5.3): fires only at the create action, only
    /// once purchases are live. Editing/switching existing personas never gates.
    private func attemptCreate() {
        if env.entitlements.purchasesEnabled,
           case .needsUpgrade = LooxGate.canCreatePersona(
               tier: env.entitlements.tier, current: env.repository.personas.count) {
            paywallContext = .personaLimit
        } else {
            editorTarget = .create
        }
    }

    private func row(_ persona: Persona) -> some View {
        Label {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(persona.displayName).themedForeground(.primary)
                    if persona.isolationPolicy != .standard {
                        Text(PersonaKindStyle.policyLabel(persona.isolationPolicy))
                            .vaultType(.caption).themedForeground(.secondary)
                    }
                }
                Spacer()
                if persona.id == env.repository.activePersona?.id {
                    PolarisIcon(Icons.checkCircle).themedForeground(.accentText)
                }
            }
        } icon: {
            PolarisIcon(PersonaKindStyle.icon(persona.kind)).themedForeground(.iconSecondary)
        }
    }

    private func select(_ persona: Persona) {
        env.repository.setActivePersona(persona.id)
        dismiss()
    }

    private func attemptDelete(_ persona: Persona) {
        let gate = env.repository.personaRemovalGate(persona)
        if gate == .ok {
            pendingDelete = persona
        } else {
            blockedReason = gate
        }
    }

    private var blockedBinding: Binding<Bool> {
        Binding(get: { blockedReason != nil }, set: { if !$0 { blockedReason = nil } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }
}

/// Whether the editor is creating a new persona or editing an existing one.
enum PersonaEditorTarget: Identifiable {
    case create
    case edit(Persona)
    var id: String { if case .edit(let p) = self { return p.id } else { return "create" } }
}

/// Create/edit sheet: name, kind, and isolation policy.
private struct PersonaEditorSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let target: PersonaEditorTarget

    @State private var name = ""
    @State private var kind: PersonaKind = .personal
    @State private var policy: PersonaIsolationPolicy = .standard

    private var isEditing: Bool { if case .edit = target { return true } else { return false } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach(PersonaKind.allCases, id: \.self) { Text(PersonaKindStyle.label($0)).tag($0) }
                    }
                }
                Section {
                    Picker("Privacy", selection: $policy) {
                        ForEach(PersonaIsolationPolicy.allCases, id: \.self) {
                            Text(PersonaKindStyle.policyLabel($0)).tag($0)
                        }
                    }
                } footer: {
                    Text(PersonaKindStyle.policyDescription(policy))
                }
            }
            .navigationTitle(Text(isEditing ? "Edit persona" : "New persona"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: seed)
        }
    }

    private func seed() {
        if case .edit(let persona) = target {
            name = persona.displayName
            kind = persona.kind
            policy = persona.isolationPolicy
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        switch target {
        case .create:
            if let id = try? env.repository.addPersona(displayName: trimmed, kind: kind, isolationPolicy: policy) {
                env.repository.setActivePersona(id)
            }
        case .edit(let persona):
            var updated = persona
            updated.displayName = trimmed
            updated.kind = kind
            updated.isolationPolicy = policy
            try? env.repository.updatePersona(updated)
        }
        dismiss()
    }
}
