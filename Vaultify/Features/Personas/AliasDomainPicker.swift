import SwiftUI

/// The user's preferred mail domain for NEW aliases. Precedence at create
/// time: the picker's explicit selection (which persists here) → this stored
/// default → the registry's primary choice. Existing aliases never move when
/// the default changes — an alias's domain is part of its external identity.
enum PrivateEmailDomainDefault {
    private static let key = "private_email_default_domain_id"

    static var domainID: String {
        get {
            // A stored ID survives only while the registry still offers that
            // domain for creation; otherwise fall back to the registry default
            // (e.g. the stored domain moved to createDisabled/retiring).
            if let stored = UserDefaults.standard.string(forKey: key),
               AuxiliaryDomainRegistry.creatableEmailDomains.contains(where: { $0.id == stored }) {
                return stored
            }
            return AuxiliaryDomainRegistry.defaultEmailDomainID
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Form section offering the mail-domain choice for a new alias. Renders
/// nothing while only one domain is creatable — the single-domain vault keeps
/// its current zero-question create flow, and the picker appears the day the
/// registry offers a second active domain.
struct AliasDomainPickerSection: View {
    @Binding var domainID: String
    /// Optional explainer under the section (e.g. the default-domain row on
    /// the Private Email screen says what the choice applies to).
    var footer: LocalizedStringKey?

    private var choices: [AuxiliaryDomainDescriptor] {
        AuxiliaryDomainRegistry.creatableEmailDomains
    }

    var body: some View {
        if choices.count > 1 {
            Section {
                Picker("Email Domain", selection: $domainID) {
                    ForEach(choices) { domain in
                        // Display names come from the trusted registry verbatim
                        // (product names, not translatable copy).
                        VStack(alignment: .leading) {
                            Text(verbatim: domain.displayName)
                            if let host = domain.emailAddressDomain {
                                Text(verbatim: "@" + host)
                                    .vaultType(.footnote).themedForeground(.secondary)
                            }
                        }
                        .tag(domain.id)
                    }
                }
                .onChange(of: domainID) { _, selected in
                    // An explicit pick becomes the remembered default for the
                    // next alias ("remember my choice", not a one-off).
                    PrivateEmailDomainDefault.domainID = selected
                }
            } footer: {
                // No section header: the picker row already says "Email Domain" —
                // header + row label doubled the same words two lines apart.
                if let footer { Text(footer) }
            }
        }
    }
}
