import Foundation
import Contacts
import OSLog

/// Imports Apple Contacts (which include iCloud contacts synced to the Mac)
/// into the People graph via `CNContactStore`. One-way, read-only — the app
/// never writes back to the address book (audit §5.3).
enum ContactsImporter {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "ContactsImporter")

    static var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    /// True if we can read contacts right now.
    static var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    /// Requests access if needed, then returns mapped import candidates.
    static func fetchAll() async throws -> [PersonImport] {
        let store = CNContactStore()
        if !isAuthorized {
            let granted = try await store.requestAccess(for: .contacts)
            guard granted else { return [] }
        }

        var keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactMiddleNameKey,
            CNContactOrganizationNameKey, CNContactJobTitleKey,
            CNContactEmailAddressesKey, CNContactPhoneNumbersKey,
            CNContactPostalAddressesKey, CNContactBirthdayKey,
            CNContactThumbnailImageDataKey, CNContactIdentifierKey
        ] as [CNKeyDescriptor]
        keys.append(CNContactFormatter.descriptorForRequiredKeys(for: .fullName))

        let request = CNContactFetchRequest(keysToFetch: keys)
        var out: [PersonImport] = []
        try store.enumerateContacts(with: request) { contact, _ in
            if let candidate = map(contact) { out.append(candidate) }
        }
        log.info("Fetched \(out.count) contacts")
        return out
    }

    private static func map(_ contact: CNContact) -> PersonImport? {
        let name = CNContactFormatter.string(from: contact, style: .fullName)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let emails = contact.emailAddresses.map { ($0.value as String) }
        let phones = contact.phoneNumbers.map { $0.value.stringValue }
        // Skip empty shells (no name and no contact info).
        guard !name.isEmpty || !emails.isEmpty || !phones.isEmpty else { return nil }

        let addresses = contact.postalAddresses.map {
            CNPostalAddressFormatter.string(from: $0.value, style: .mailingAddress)
                .replacingOccurrences(of: "\n", with: ", ")
        }
        var birthday: Date?
        if let comps = contact.birthday {
            var c = comps
            if c.year == nil { c.year = 2000 } // contacts often omit year
            birthday = Calendar.current.date(from: c)
        }

        return PersonImport(
            displayName: name.isEmpty ? (emails.first ?? phones.first ?? "Unknown") : name,
            emails: emails,
            phones: phones,
            company: contact.organizationName,
            role: contact.jobTitle,
            birthday: birthday,
            addresses: addresses,
            contactIdentifier: contact.identifier,
            photoData: contact.thumbnailImageData,
            photoExt: "jpg",
            source: "contacts"
        )
    }

    // MARK: - vCard parsing (shared with the file importer)

    static func parseVCard(data: Data) -> [PersonImport] {
        guard let contacts = try? CNContactVCardSerialization.contacts(with: data) else { return [] }
        return contacts.compactMap { map($0) }.map {
            var c = $0; c.source = "vcard"; return c
        }
    }
}

// MARK: - Phase 7-B — CNContact → Person mapping & meeting cross-reference

extension ContactsImporter {
    /// Maps a single `CNContact` directly to a `Person` (not persisted — the
    /// caller decides whether to save). Mirrors `map(_:)` but returns the
    /// first-class model the People graph stores.
    static func importContact(_ contact: CNContact) -> Person {
        guard let candidate = map(contact) else {
            return Person(displayName: "Unknown", importSources: ["contacts"])
        }
        return person(from: candidate)
    }

    /// Searches Contacts for `query` (name / company / email substring) and
    /// returns mapped `Person` records — a batch import preview.
    static func importAll(matching query: String) async -> [Person] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidates = (try? await fetchAll()) ?? []
        let filtered = q.isEmpty ? candidates : candidates.filter {
            $0.displayName.lowercased().contains(q)
                || $0.company.lowercased().contains(q)
                || $0.emails.contains(where: { $0.lowercased().contains(q) })
        }
        return filtered.map { person(from: $0) }
    }

    /// Cross-references meeting participant names against Contacts and returns
    /// the matching `CNContact`s — candidates worth importing.
    ///
    /// Design note: the spec lists `suggestFromMeetings() -> [CNContact]` with no
    /// args, but the suggestion needs the meeting roster to match against, so we
    /// take the participant names explicitly and resolve against Contacts here.
    static func suggestFromMeetings(participantNames: [String]) async -> [CNContact] {
        let wanted = Set(participantNames
            .map { PersonMatching.normalizeName($0) }
            .filter { !$0.isEmpty })
        guard !wanted.isEmpty else { return [] }

        let store = CNContactStore()
        if !isAuthorized {
            guard (try? await store.requestAccess(for: .contacts)) == true else { return [] }
        }
        var keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey,
            CNContactPhoneNumbersKey, CNContactOrganizationNameKey, CNContactJobTitleKey,
            CNContactPostalAddressesKey, CNContactBirthdayKey, CNContactThumbnailImageDataKey,
            CNContactIdentifierKey
        ] as [CNKeyDescriptor]
        keys.append(CNContactFormatter.descriptorForRequiredKeys(for: .fullName))

        var matches: [CNContact] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        try? store.enumerateContacts(with: request) { contact, _ in
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            if wanted.contains(PersonMatching.normalizeName(name)) {
                matches.append(contact)
            }
        }
        log.info("Suggested \(matches.count) contacts from \(wanted.count) meeting participants")
        return matches
    }

    /// Shared `PersonImport` → `Person` conversion used by the Phase 7 helpers.
    private static func person(from c: PersonImport) -> Person {
        Person(displayName: c.trimmedName.isEmpty ? "Unknown" : c.trimmedName,
               company: c.company,
               role: c.role,
               emails: c.emails,
               phones: c.phones,
               birthday: c.birthday,
               addresses: c.addresses,
               contactIdentifier: c.contactIdentifier,
               importSources: ["contacts"])
    }
}
