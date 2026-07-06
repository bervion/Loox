import SwiftUI

/// Minimal persona ("identity") switcher: list personas, switch the active one,
/// and create a new one. Edit, delete, avatars, and isolation policy are deferred
/// — this is the thin first cut that makes personas real end-to-end.
struct PersonaSwitcherScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var showingCreate = false
    @State private var newName = ""
    @State private var newKind: PersonaKind = .personal

    var body: some View {
        List {
            Section {
                ForEach(env.repository.personas) { persona in
                    Button { select(persona) } label: { row(persona) }
                }
            }
            .listRowBackground(VaultColors.surface)

            Section {
                Button { showingCreate = true } label: {
                    Label { Text("Add persona") } icon: { PolarisIcon(Icons.addCircle) }
                }
            }
            .listRowBackground(VaultColors.surface)
        }
        .navigationTitle(Text("Personas"))
        .sheet(isPresented: $showingCreate) { createSheet }
    }

    private func row(_ persona: Persona) -> some View {
        Label {
            HStack {
                Text(persona.displayName).themedForeground(.primary)
                Spacer()
                if persona.id == env.repository.activePersona?.id {
                    PolarisIcon(Icons.checkCircle).themedForeground(.accent)
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

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $newName)
                    Picker("Type", selection: $newKind) {
                        ForEach(PersonaKind.allCases, id: \.self) { kind in
                            Text(PersonaKindStyle.label(kind)).tag(kind)
                        }
                    }
                }
            }
            .navigationTitle(Text("New persona"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingCreate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { create() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let id = try? env.repository.addPersona(displayName: name, kind: newKind) {
            env.repository.setActivePersona(id)
        }
        newName = ""
        newKind = .personal
        showingCreate = false
        dismiss()
    }
}
