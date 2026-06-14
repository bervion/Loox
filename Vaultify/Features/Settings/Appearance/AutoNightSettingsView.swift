import SwiftUI

/// Configure when the app switches to the night theme: never, follow the system,
/// a daily schedule, or below a brightness threshold. Mirrors Telegram's auto-night.
struct AutoNightSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var fromMinutes = 22 * 60
    @State private var toMinutes = 7 * 60
    @State private var threshold = 0.4
    @State private var seeded = false

    private var setting: AutoNightSetting { env.theme.settings.autoNight }

    private enum Mode: Hashable { case off, system, scheduled, brightness }
    private var mode: Mode {
        switch setting {
        case .off: return .off
        case .system: return .system
        case .time: return .scheduled
        case .brightness: return .brightness
        }
    }

    var body: some View {
        Form {
            Section {
                modeRow(Text("Off"), .off)
                modeRow(Text("System"), .system)
                modeRow(Text("Scheduled"), .scheduled)
                modeRow(Text("Brightness"), .brightness)
            }

            if mode == .scheduled {
                Section {
                    DatePicker(selection: fromBinding, displayedComponents: .hourAndMinute) { Text("From") }
                    DatePicker(selection: toBinding, displayedComponents: .hourAndMinute) { Text("To") }
                }
            }

            if mode == .brightness {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Dark below brightness")
                            Spacer()
                            Text(verbatim: "\(Int(threshold * 100))%").foregroundStyle(.secondary)
                        }
                        Slider(value: brightnessBinding, in: 0...1)
                    }
                }
            }

            if mode != .off {
                Section {
                    Picker(selection: Binding(get: { env.theme.settings.nightTheme },
                                              set: { env.theme.setNightTheme($0) })) {
                        ForEach([BuiltinTheme.night, .nightTinted], id: \.self) { builtin in
                            Text(builtin.displayName).tag(AppThemeReference.builtin(builtin))
                        }
                    } label: {
                        Text("Night Theme")
                    }
                } header: {
                    Text("Night Theme")
                }
            }
        }
        .navigationTitle("Automatic Dark Mode")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: seed)
    }

    private func modeRow(_ title: Text, _ value: Mode) -> some View {
        Button { apply(value) } label: {
            HStack {
                title.foregroundStyle(.primary)
                Spacer()
                if mode == value { PolarisIcon(Icons.checkCircle, size: 20).foregroundStyle(Color.accentColor) }
            }
        }
        .buttonStyle(.plain)
    }

    private func seed() {
        guard !seeded else { return }
        seeded = true
        if case .time(let from, let to) = setting { fromMinutes = from; toMinutes = to }
        if case .brightness(let value) = setting { threshold = value }
    }

    private func apply(_ mode: Mode) {
        switch mode {
        case .off: env.theme.setAutoNight(.off)
        case .system: env.theme.setAutoNight(.system)
        case .scheduled: env.theme.setAutoNight(.time(fromMinutes: fromMinutes, toMinutes: toMinutes))
        case .brightness: env.theme.setAutoNight(.brightness(threshold: threshold))
        }
    }

    // Date <-> minutes-of-day plumbing for the schedule pickers.
    private var fromBinding: Binding<Date> {
        Binding(get: { Self.date(minutes: fromMinutes) },
                set: { fromMinutes = Self.minutes(from: $0)
                       env.theme.setAutoNight(.time(fromMinutes: fromMinutes, toMinutes: toMinutes)) })
    }
    private var toBinding: Binding<Date> {
        Binding(get: { Self.date(minutes: toMinutes) },
                set: { toMinutes = Self.minutes(from: $0)
                       env.theme.setAutoNight(.time(fromMinutes: fromMinutes, toMinutes: toMinutes)) })
    }

    private var brightnessBinding: Binding<Double> {
        Binding(get: { threshold },
                set: { threshold = $0; env.theme.setAutoNight(.brightness(threshold: $0)) })
    }

    private static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }
    private static func minutes(from date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }
}
