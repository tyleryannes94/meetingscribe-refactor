import Foundation

/// Resolves the `attendees: [String]` already stored on past meetings into
/// person records (audit §5.3 / Phase C). Attendee strings come from EventKit
/// and look like "Jane Smith", "jane@acme.com", or "Jane Smith <jane@acme.com>".
enum CalendarAttendeeImporter {
    /// Names/emails that are the user — skip so we don't import ourselves.
    private static let selfTokens: Set<String> = ["me", "tyler", "tyler yannes"]

    static func candidates(from meetings: [Meeting]) -> [PersonImport] {
        var byKey: [String: PersonImport] = [:]
        for meeting in meetings {
            for raw in meeting.attendees {
                guard let parsed = parse(raw) else { continue }
                // Dedup within this batch by email (preferred) or lowercased name.
                let key = parsed.emails.first?.lowercased() ?? parsed.displayName.lowercased()
                if var existing = byKey[key] {
                    existing.emails = Array(Set(existing.emails + parsed.emails))
                    byKey[key] = existing
                } else {
                    byKey[key] = parsed
                }
            }
        }
        return Array(byKey.values)
    }

    private static func parse(_ raw: String) -> PersonImport? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        var name = ""
        var email = ""
        if let lt = s.firstIndex(of: "<"), let gt = s.firstIndex(of: ">"), lt < gt {
            name = String(s[..<lt]).trimmingCharacters(in: .whitespacesAndNewlines)
            email = String(s[s.index(after: lt)..<gt]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if s.contains("@"), !s.contains(" ") {
            email = s
        } else {
            name = s
        }

        let display = name.isEmpty ? localPart(of: email) : name
        guard !display.isEmpty else { return nil }
        if selfTokens.contains(display.lowercased()) { return nil }
        if let at = email.split(separator: "@").first, selfTokens.contains(String(at).lowercased()) { return nil }

        return PersonImport(displayName: display,
                            emails: email.isEmpty ? [] : [email],
                            source: "calendar")
    }

    /// "jane.smith@acme.com" → "Jane Smith" (a readable stub name).
    private static func localPart(of email: String) -> String {
        guard let local = email.split(separator: "@").first else { return email }
        return local
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
