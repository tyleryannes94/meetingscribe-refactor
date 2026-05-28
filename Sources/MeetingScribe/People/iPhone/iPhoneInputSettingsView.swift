import SwiftUI
import UniformTypeIdentifiers

/// Phase 7-B aggregator (Settings → People): the QR/iPhone server, the Contacts
/// importer, and a CSV bulk import — all in one pane.
@available(macOS 14.0, *)
struct iPhoneInputSettingsView: View {
    @EnvironmentObject var people: PeopleStore
    @EnvironmentObject var peopleTags: PeopleTagStore

    @State private var showContactsImport = false
    @State private var showCSVPicker = false
    @State private var csvStatus: String?
    @State private var notesFolder = AppleNotesImporter.defaultFolder
    @State private var notesStatus: String?
    @State private var importingNotes = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section(title: "Add via iPhone",
                        subtitle: "Scan a QR code to open a mobile form on your phone.") {
                    iPhoneInputQRView()
                }

                section(title: "Import from iPhone via Apple Notes",
                        subtitle: "No Wi-Fi needed — add people on your iPhone in a Notes folder; they sync via iCloud and import here.") {
                    appleNotesContent
                }

                section(title: "Import from Contacts",
                        subtitle: "Pull people from the macOS Contacts app (read-only).") {
                    Button {
                        showContactsImport = true
                    } label: {
                        Label("Open Contacts Importer…", systemImage: "person.crop.circle.badge.plus")
                    }
                }

                section(title: "Bulk Import (CSV)",
                        subtitle: "Columns: name, role, company, email, tags.") {
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            showCSVPicker = true
                        } label: {
                            Label("Choose CSV File…", systemImage: "tablecells")
                        }
                        if let csvStatus {
                            Text(csvStatus).font(NDS.tiny).foregroundStyle(NDS.textSecondary)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: 620, alignment: .leading)
        }
        .sheet(isPresented: $showContactsImport) {
            ContactsImportView().environmentObject(people)
        }
        .fileImporter(isPresented: $showCSVPicker,
                      allowedContentTypes: [.commaSeparatedText, .plainText],
                      allowsMultipleSelection: false) { result in
            handleCSV(result)
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, subtitle: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(subtitle).font(NDS.tiny).foregroundStyle(NDS.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(NDS.sidebarBg, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Apple Notes

    @ViewBuilder
    private var appleNotesContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Notes folder").font(NDS.small).foregroundStyle(NDS.textSecondary)
                TextField("MeetingScribe", text: $notesFolder)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                Button {
                    runNotesImport()
                } label: {
                    if importingNotes {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Import from Apple Notes", systemImage: "note.text")
                    }
                }
                .disabled(importingNotes || notesFolder.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let notesStatus {
                Text(notesStatus).font(NDS.tiny).foregroundStyle(NDS.textSecondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("On your iPhone: make a Notes folder named “\(notesFolder)”, then add one note per person. The title is their name; the body uses simple lines:")
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                Text("Role: …   Company: …   Email: …   Phone: …   Tags: a, b   Notes: …")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(NDS.textTertiary)
                Text("Re-importing is safe — existing people are updated, not duplicated. First run asks permission to control Notes.")
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
            }
        }
    }

    private func runNotesImport() {
        importingNotes = true
        notesStatus = nil
        // NSAppleScript runs synchronously on the main thread; defer one runloop
        // tick so the spinner paints before it blocks.
        DispatchQueue.main.async {
            let folder = notesFolder.trimmingCharacters(in: .whitespaces)
            let result = AppleNotesImporter.importToStore(folder: folder,
                                                          store: people,
                                                          tagStore: peopleTags)
            importingNotes = false
            if let err = result.error {
                notesStatus = "⚠️ \(err)"
            } else {
                notesStatus = "Imported \(result.created) new, updated \(result.updated) (scanned \(result.scanned) note\(result.scanned == 1 ? "" : "s"))."
            }
        }
    }

    // MARK: - CSV

    private func handleCSV(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            csvStatus = "Couldn't read that file."
            return
        }
        let rows = Self.parseCSV(text)
        guard let headerRow = rows.first else { csvStatus = "Empty file."; return }
        let header = headerRow.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func col(_ name: String) -> Int? { header.firstIndex(of: name) }
        let nameIdx = col("name")
        guard let nameIdx else { csvStatus = "No 'name' column found."; return }
        let roleIdx = col("role"), companyIdx = col("company")
        let emailIdx = col("email"), tagsIdx = col("tags")

        var created = 0
        for row in rows.dropFirst() {
            func value(_ idx: Int?) -> String {
                guard let idx, idx < row.count else { return "" }
                return row[idx].trimmingCharacters(in: .whitespaces)
            }
            let name = value(nameIdx)
            guard !name.isEmpty else { continue }
            let tagNames = value(tagsIdx).split(separator: ";").flatMap { $0.split(separator: ",") }
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let tagIDs = Set(tagNames.map { peopleTags.createTag(name: $0).id })
            // Direct create (supports tags); user can "Merge duplicates" after.
            people.createPerson(displayName: name,
                                company: value(companyIdx),
                                role: value(roleIdx),
                                email: value(emailIdx),
                                tagIDs: tagIDs)
            created += 1
        }
        csvStatus = created == 0 ? "No rows imported." : "Imported \(created) \(created == 1 ? "person" : "people")."
    }

    /// Minimal RFC-4180-ish CSV parser: handles quoted fields, escaped quotes,
    /// and commas/newlines inside quotes.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r":
                    if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                    row.append(field); field = ""
                    if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                    row = []
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        }
        return rows
    }
}
