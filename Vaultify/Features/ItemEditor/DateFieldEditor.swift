import Foundation
import SwiftUI

/// Editor for `.date`-kind dynamic fields (e.g. Identity's "Date of Birth"). The
/// field predates any picker — existing stored values are whatever the user typed
/// into a plain `TextField` (there is no dedicated date-kind rendering anywhere else
/// in the app, confirmed against `DetailFieldRow`). Storage is therefore genuinely
/// freeform text, not a fixed format.
///
/// To keep round-trip compatibility with those pre-existing values while still
/// giving new entries a real `DatePicker`:
/// - A stored value that matches one of `knownFormats` parses into the picker; saving
///   re-serializes with that SAME format, so the on-screen shape never changes for a
///   value that already round-tripped once.
/// - An empty value (new field) adopts the canonical `fallbackFormat` going forward.
/// - A non-empty value that matches no known format is left as free text — reformatting
///   something we can't confidently reparse would risk silently corrupting a real date
///   the user typed in an format we don't recognize (e.g. a fully spelled-out or
///   non-English format). The plain `TextField` stays for that edge case.
struct DateFieldEditor: View {
    @Binding var value: String

    var body: some View {
        if Self.parsedDate(for: value) != nil {
            DatePicker("", selection: dateBinding, in: Self.range, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
        } else {
            TextField("Enter value", text: $value)
                .vaultType(.body)
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { Self.parsedDate(for: value) ?? Self.emptyAnchor },
            set: { newDate in
                let format = Self.matchedFormat(for: value) ?? Self.fallbackFormat
                value = Self.formatter(format).string(from: newDate)
            }
        )
    }

    // MARK: - Format detection (pure, no state — safe to call during body evaluation)

    /// Canonical format for values with nothing to preserve (new/empty fields).
    /// ISO date-only: locale-independent, unambiguous, sorts naturally as text.
    private static let fallbackFormat = "yyyy-MM-dd"

    /// Parse candidates, tried in order: unambiguous ISO first, then the numeric
    /// slash formats most likely typed via a default keyboard (US month/day, then
    /// day/month), then English long-form month names.
    private static let knownFormats = [
        "yyyy-MM-dd", "yyyy/MM/dd",
        "MM/dd/yyyy", "M/d/yyyy",
        "dd/MM/yyyy", "d/M/yyyy",
        "MMMM d, yyyy", "MMM d, yyyy",
    ]

    /// Stable "today" anchor for an empty field so the picker has something to show
    /// before the user has chosen anything; storage stays empty until they do.
    private static var emptyAnchor: Date { Calendar.current.startOfDay(for: Date()) }

    /// Wide enough to never clip a legitimate date-kind value (birth dates,
    /// anniversaries, expiries all use this same generic kind), narrow enough to
    /// keep the wheel/compact picker usable.
    private static var range: ClosedRange<Date> {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let past = calendar.date(byAdding: .year, value: -150, to: now) ?? .distantPast
        let future = calendar.date(byAdding: .year, value: 50, to: now) ?? .distantFuture
        return past...future
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }

    /// The first known format that parses `text`, or nil if none match.
    private static func matchedFormat(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return knownFormats.first { formatter($0).date(from: trimmed) != nil }
    }

    /// The `Date` to show in the picker, or nil to fall back to the plain `TextField`
    /// (empty values get a stable anchor; non-empty values must match a known format).
    private static func parsedDate(for text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return emptyAnchor }
        guard let format = matchedFormat(for: trimmed) else { return nil }
        return formatter(format).date(from: trimmed)
    }
}
