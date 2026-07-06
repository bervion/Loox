import Foundation

/// Presentation for a `PersonaKind`: a Polaris icon asset + a localized label.
/// Kept in the app module (references `Icons`); `PersonaKind` itself stays in Core.
enum PersonaKindStyle {
    static func icon(_ kind: PersonaKind) -> String {
        switch kind {
        case .personal:      return Icons.person
        case .professional:  return Icons.organization
        case .pseudonymous:  return Icons.hide
        case .anonymous:     return Icons.personLockFilled
        case .custom:        return Icons.apps
        }
    }

    static func label(_ kind: PersonaKind) -> String {
        switch kind {
        case .personal:      return appString("Personal")
        case .professional:  return appString("Professional")
        case .pseudonymous:  return appString("Pseudonymous")
        case .anonymous:     return appString("Anonymous")
        case .custom:        return appString("Custom")
        }
    }
}
