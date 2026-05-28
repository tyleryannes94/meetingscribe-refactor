import Foundation

/// A person record coming from an external source (Apple/iCloud Contacts,
/// Gmail / People API, a vCard/CSV file, or calendar attendees). Fed into
/// `PeopleStore.importPeople`, which dedupes against existing people and either
/// merges (union of emails/phones/addresses, fill empty scalars) or creates.
struct PersonImport {
    var displayName: String
    var emails: [String] = []
    var phones: [String] = []
    var company: String = ""
    var role: String = ""
    var birthday: Date?
    var addresses: [String] = []
    var contactIdentifier: String?
    /// Optional photo bytes (e.g. CNContact.thumbnailImageData) + extension.
    var photoData: Data?
    var photoExt: String = "jpg"
    /// Provenance tag stored on the resulting person: "contacts", "gmail",
    /// "calendar", "vcard", "csv".
    var source: String

    var trimmedName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum PersonMatching {
    /// Last-10-digits comparison so "+1 (555) 123-4567" == "5551234567".
    static func normalizePhone(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        return String(digits.suffix(10))
    }

    static func normalizeEmail(_ email: String) -> String {
        email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeName(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
