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

/// A short row opens the full domain list. Long suffixes wrap on their own
/// line; unavailable signed entries explain readiness without enabling create.
struct AliasDomainPickerSection: View {
    @Binding var domainID: String
    var footer: LocalizedStringKey?
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let _ = env.domainRegistry.appliedRevision
        Section {
            NavigationLink { AliasDomainPickerScreen(domainID: $domainID) } label: {
                PrivateEmailFieldValue(label: "Email Domain",
                    value: AuxiliaryDomainRegistry.emailDomain(forDomainID: domainID).map { "@" + $0 }
                           ?? appString("No domains available for new addresses"))
            }
            if !AuxiliaryDomainRegistry.creatableEmailDomains.contains(where: { $0.id == domainID }) {
                Text("Select an available domain before creating an address.")
                    .vaultType(.footnote).themedForeground(.warningBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: { if let footer { Text(footer).themedForeground(.secondaryBody) } }
    }
}

private struct AliasDomainPickerScreen: View {
    @Binding var domainID: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = env.domainRegistry.appliedRevision
        List {
            Section {
                ForEach(AuxiliaryDomainRegistry.current.filter(\.offersPrivateEmail)) { domain in
                    Button {
                        guard domain.lifecycle.allowsCreation,
                              AuxiliaryDomainRegistry.creatableEmailDomains.contains(where: { $0.id == domain.id }) else { return }
                        domainID = domain.id
                        PrivateEmailDomainDefault.domainID = domain.id
                        Haptics.tap()
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: Space.s3) {
                            VStack(alignment: .leading, spacing: Space.s1) {
                                Text(verbatim: "@" + (domain.emailAddressDomain ?? ""))
                                    .vaultType(.body).themedForeground(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(verbatim: domain.displayName).vaultType(.caption).themedForeground(.secondaryBody)
                                if !domain.lifecycle.allowsCreation {
                                    Text("Not ready for new addresses").vaultType(.footnote).themedForeground(.secondaryBody)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if domain.lifecycle.allowsCreation && domainID == domain.id {
                                VaultIcon(Icons.check, size: Metric.iconInline).themedForeground(.accentText)
                            }
                        }.frame(minHeight: Metric.hitMin)
                    }.buttonStyle(.plain).disabled(!domain.lifecycle.allowsCreation)
                }
                if AuxiliaryDomainRegistry.creatableEmailDomains.isEmpty {
                    Text("No domains available for new addresses").vaultType(.subhead).themedForeground(.secondaryBody)
                }
            } footer: { Text("Existing addresses keep their original domain.").themedForeground(.secondaryBody) }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        .navigationTitle(Text("Email Domain"))
        .platformNavigationBarTitleDisplayMode(.inline)
    }
}
