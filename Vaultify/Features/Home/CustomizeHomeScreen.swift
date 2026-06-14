import SwiftUI

/// Toggle the optional Home sections (Recently Used / Recently Modified). The
/// four default sections always show when they have items.
struct CustomizeHomeScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = env.settings
        NavigationStack {
            Form {
                Section {
                    Toggle("Recently Used", isOn: $settings.homeShowRecentlyUsed)
                    Toggle("Recently Modified", isOn: $settings.homeShowRecentlyModified)
                } header: {
                    Text("Optional sections")
                } footer: {
                    Text("Pinned, Favorites, Recently Created, and Frequently Used always appear when they have items.")
                }
            }
            .navigationTitle("Customize Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
