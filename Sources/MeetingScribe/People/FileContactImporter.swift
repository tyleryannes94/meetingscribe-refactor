import Foundation
import OSLog

/// Bulk import from a `.vcf` (vCard) or `.csv` file chosen in an open panel.
enum FileContactImporter {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "FileImport")

    static let supportedExtensions = ["vcf", "vcard", "csv"]

    static func candidates(fromFileAt url: URL) -> [PersonImport] {
        let ext = url.pathExtension.lowercased()
        guard let data = try? Data(contentsOf: url) else {
            log.error("Could not read import file at \(url.path, privacy: .public)")
            return []
        }
        switch ext {
        case "vcf", "vcard":
            return ContactsImporter.parseVCard(data: data)
        case "csv":
            return parseCSV(String(decoding: data, as: UTF8.self))
        default:
            return []
        }
    }

    // MARK: - CSV

    private static func parseCSV(_ text: String) -> [PersonImport] {
        var rows = parseRows(text)
        guard rows.count > 1 else { return [] }
        let header = rows.removeFirst().map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        func col(_ candidates: [String]) -> Int? {
            for c in candidates { if let i = header.firstIndex(of: c) { return i } }
            // Fuzzy contains match (e.g. "e-mail 1 - value" from Google export).
            for (i, h) in header.enumerated() where candidates.contains(where: { h.contains($0) }) { return i }
            return nil
        }

        let nameIdx = col(["name", "full name", "display name", "first name"])
        let lastIdx = col(["last name", "family name"])
        let emailIdx = col(["email", "e-mail", "email address"])
        let phoneIdx = col(["phone", "phone number", "mobile", "phone 1 - value"])
        let companyIdx = col(["company", "organization", "organization name"])
        let roleIdx = col(["title", "role", "job title"])
        let addressIdx = col(["address", "street", "address 1 - formatted"])

        func field(_ row: [String], _ idx: Int?) -> String {
            guard let idx, idx < row.count else { return "" }
            return row[idx].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var out: [PersonImport] = []
        for row in rows {
            var name = field(row, nameIdx)
            let last = field(row, lastIdx)
            if !last.isEmpty { name = "\(name) \(last)".trimmingCharacters(in: .whitespaces) }
            let email = field(row, emailIdx)
            let phone = field(row, phoneIdx)
            if name.isEmpty && email.isEmpty && phone.isEmpty { continue }
            out.append(PersonImport(
                displayName: name.isEmpty ? email : name,
                emails: email.isEmpty ? [] : [email],
                phones: phone.isEmpty ? [] : [phone],
                company: field(row, companyIdx),
                role: field(row, roleIdx),
                addresses: field(row, addressIdx).isEmpty ? [] : [field(row, addressIdx)],
                source: "csv"
            ))
        }
        log.info("Parsed \(out.count) rows from CSV")
        return out
    }

    /// Minimal RFC-4180-ish parser: handles quoted fields with embedded commas,
    /// quotes ("") and newlines.
    private static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else { field.append(ch) }
            } else {
                switch ch {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r":
                    if ch == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                    row.append(field); field = ""
                    if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                    row = []
                default: field.append(ch)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
