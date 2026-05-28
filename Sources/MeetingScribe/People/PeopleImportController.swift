import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Orchestrates the Phase C import sources into `PeopleStore`, publishing a
/// short status line + a busy flag for the UI.
@available(macOS 14.0, *)
@MainActor
final class PeopleImportController: ObservableObject {
    @Published var isWorking = false
    @Published var status: String?

    private func report(_ result: (created: Int, merged: Int), source: String) {
        status = "\(source): \(result.created) added, \(result.merged) updated."
    }

    func importAppleContacts() async {
        isWorking = true
        status = "Reading Apple/iCloud Contacts…"
        defer { isWorking = false }
        do {
            let candidates = try await ContactsImporter.fetchAll()
            guard !candidates.isEmpty else { status = "No contacts found (or access denied)."; return }
            report(PeopleStore.shared.importPeople(candidates), source: "Contacts")
        } catch {
            status = "Contacts import failed: \(error.localizedDescription)"
        }
    }

    func importCalendarAttendees(from meetings: [Meeting]) {
        isWorking = true
        defer { isWorking = false }
        let candidates = CalendarAttendeeImporter.candidates(from: meetings)
        guard !candidates.isEmpty else { status = "No calendar attendees found."; return }
        report(PeopleStore.shared.importPeople(candidates), source: "Calendar attendees")
    }

    func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "vcf"),
                                     UTType(filenameExtension: "vcard"),
                                     UTType.commaSeparatedText].compactMap { $0 }
        panel.message = "Choose a vCard (.vcf) or CSV file to import contacts from"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isWorking = true
        defer { isWorking = false }
        let candidates = FileContactImporter.candidates(fromFileAt: url)
        guard !candidates.isEmpty else { status = "No importable rows found in \(url.lastPathComponent)."; return }
        report(PeopleStore.shared.importPeople(candidates), source: url.lastPathComponent)
    }

    func importGmail() async {
        isWorking = true
        status = "Fetching Google contacts…"
        defer { isWorking = false }
        let candidates = await GmailContactsService.shared.importAllContacts()
        guard !candidates.isEmpty else {
            status = GmailContactsService.shared.lastStatus ?? "No Gmail contacts (connect an account first)."
            return
        }
        report(PeopleStore.shared.importPeople(candidates), source: "Gmail")
    }
}
