import SwiftUI

/// Home layout editor — the in-place edit mode reached from the Home header's edit button.
/// Lists every customizable `HomeSection` as a reorderable row with a leading visibility
/// checkmark; order and hidden-set persist to `SettingsStore` as the user edits.
///
/// Reorder reuses the `List` + `.onMove` pattern from `ManageFoldersScreen`; edit mode
/// surfaces the trailing drag handles without an explicit Edit button (the header's
/// Done button exits). A checkmark-styled `Toggle` (not a bare `Button`) keeps the
/// show/hide control interactive inside the active edit mode.
struct HomeLayoutEditor: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Starts INACTIVE and animates to active after the insertion transition:
    /// a List born with `.constant(.active)` gets UIKit's editing layout in
    /// late, non-animated passes that land as two visible snaps right after
    /// the Home fade/scale settles (frame-verified on the iOS 27 runtime).
    /// Activating inside `withAnimation` turns that into one deliberate
    /// Reminders-style handle slide instead.
    @State private var editMode: EditMode = .inactive

    /// Height reserved at the top so the first row clears the floating header overlay —
    /// mirrors `VaultHeaderScrollSpacer`'s inset so the editor lines up with the feed.
    private var headerInset: CGFloat { Metric.hitMin + Space.s6 }

    private var sections: [HomeSection] {
        HomeSection.ordered(savedOrder: env.settings.homeSectionOrder)
    }

    var body: some View {
        List {
            Section {
                ForEach(sections) { section in
                    row(section)
                }
                .onMove(perform: move)
                .listRowBackground(VaultColors.surface)
            } footer: {
                Text("Show, hide, and reorder the sections on your Home screen.")
                    .vaultType(.footnote)
                    .themedForeground(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, headerInset, for: .scrollContent)
        // Binding (not a selection binding) keeps rows tappable and the
        // checkmark toggle working while the handles are up.
        .environment(\.editMode, $editMode)
        .onAppear {
            guard editMode != .active else { return }
            guard !reduceMotion else {
                editMode = .active
                return
            }
            // Waits out the header's Motion.spring insertion, then slides the
            // handles in as their own beat.
            withAnimation(Motion.standard.delay(0.3)) { editMode = .active }
        }
    }

    private func row(_ section: HomeSection) -> some View {
        Toggle(isOn: visibility(of: section)) {
            HStack(spacing: Space.s3) {
                PolarisIcon(section.icon, size: Metric.iconInline)
                    .themedForeground(.iconSecondary)
                    .frame(width: Metric.iconUtility, height: Metric.iconUtility)
                Text(section.title)
                    .vaultType(.body)
                    .themedForeground()
            }
        }
        .toggleStyle(HomeSectionVisibilityToggleStyle())
    }

    /// Visibility as a binding over the persisted hidden-set (true = shown on Home).
    private func visibility(of section: HomeSection) -> Binding<Bool> {
        Binding(
            get: { !env.settings.homeHiddenSections.contains(section.rawValue) },
            set: { shown in
                var hidden = Set(env.settings.homeHiddenSections)
                if shown { hidden.remove(section.rawValue) } else { hidden.insert(section.rawValue) }
                env.settings.homeHiddenSections = Array(hidden)
            }
        )
    }

    /// Persist the new order as the flat identifier list Home reads back.
    private func move(from source: IndexSet, to destination: Int) {
        var ids = sections.map(\.rawValue)
        ids.move(fromOffsets: source, toOffset: destination)
        env.settings.homeSectionOrder = ids
    }
}

/// Renders a `Toggle` as a Reminders-style leading checkmark (accent-filled circle when on,
/// a hairline ring when off) followed by the label. Implemented as a `Toggle` style rather
/// than a plain button so the whole row stays interactive inside the List's active edit mode.
private struct HomeSectionVisibilityToggleStyle: ToggleStyle {
    @Environment(AppEnvironment.self) private var env

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(Motion.standard) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: Space.s3) {
                checkmark(on: configuration.isOn)
                configuration.label
                Spacer(minLength: Space.s2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Announce show/hide state to VoiceOver via the selection trait (no extra strings).
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }

    private func checkmark(on: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Color(rgb: env.theme.active.separatorOpaque), lineWidth: 1.5)
                .opacity(on ? 0 : 1)
            Circle()
                .fill(env.theme.active.color(.accent))
                .opacity(on ? 1 : 0)
                .overlay {
                    // Force white (not `.onAccent`, which resolves dark on lighter accents) so
                    // the tick matches the header Done button.
                    PolarisIcon(Icons.check, size: 13)
                        .foregroundStyle(.white)
                        .opacity(on ? 1 : 0)
                }
        }
        .frame(width: 22, height: 22)
        .animation(Motion.standard, value: on)
    }
}
