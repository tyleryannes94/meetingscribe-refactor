import SwiftUI

/// UserDefaults-backed settings for Compliance Mode.
struct ComplianceSettings {
    private let defaults = UserDefaults.standard

    enum Jurisdiction: String, CaseIterable, Identifiable, Sendable {
        case us = "US"
        case eu = "EU"
        case custom = "Custom"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .us:     return "United States (one-party consent default)"
            case .eu:     return "European Union (GDPR / all-party consent)"
            case .custom: return "Custom"
            }
        }
        /// Default disclaimer wording for the jurisdiction.
        var defaultDisclaimer: String {
            switch self {
            case .us:
                return "Heads up — this meeting is being recorded and transcribed for note-taking."
            case .eu:
                return "This meeting is being recorded and transcribed. Please confirm everyone consents before continuing."
            case .custom:
                return "This meeting is being recorded."
            }
        }
    }

    private enum Keys {
        static let enabled = "complianceEnabled"
        static let jurisdiction = "complianceJurisdiction"
        static let customDisclaimer = "complianceCustomDisclaimer"
    }

    var enabled: Bool {
        get { defaults.bool(forKey: Keys.enabled) }
        nonmutating set { defaults.set(newValue, forKey: Keys.enabled) }
    }

    var jurisdiction: Jurisdiction {
        get { Jurisdiction(rawValue: defaults.string(forKey: Keys.jurisdiction) ?? "") ?? .us }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Keys.jurisdiction) }
    }

    var customDisclaimer: String {
        get { defaults.string(forKey: Keys.customDisclaimer) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Keys.customDisclaimer) }
    }

    /// The disclaimer text actually shown — custom override when set & in
    /// custom mode, otherwise the jurisdiction default.
    var disclaimerText: String {
        if jurisdiction == .custom, !customDisclaimer.trimmingCharacters(in: .whitespaces).isEmpty {
            return customDisclaimer
        }
        return jurisdiction.defaultDisclaimer
    }
}

/// Settings section for Compliance Mode: toggle, jurisdiction picker, and a
/// custom-disclaimer field when "Custom" is selected.
@available(macOS 14.0, *)
struct ComplianceSettingsView: View {
    @AppStorage("complianceEnabled") private var enabled = false
    @AppStorage("complianceJurisdiction") private var jurisdictionRaw = ComplianceSettings.Jurisdiction.us.rawValue
    @AppStorage("complianceCustomDisclaimer") private var customDisclaimer = ""

    private var jurisdiction: ComplianceSettings.Jurisdiction {
        .init(rawValue: jurisdictionRaw) ?? .us
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compliance Mode")
                    Text("Show a recording disclaimer when capture starts and log a timestamped consent record.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Picker("Jurisdiction", selection: $jurisdictionRaw) {
                ForEach(ComplianceSettings.Jurisdiction.allCases) { j in
                    Text(j.label).tag(j.rawValue)
                }
            }
            .disabled(!enabled)

            if jurisdiction == .custom {
                TextField("Custom disclaimer", text: $customDisclaimer, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .disabled(!enabled)
            } else {
                Text(jurisdiction.defaultDisclaimer)
                    .font(.caption).foregroundStyle(.secondary)
                    .italic()
            }
        }
        .opacity(enabled ? 1 : 0.6)
    }
}
