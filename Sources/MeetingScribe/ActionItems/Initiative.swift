import Foundation

/// Top tier of the workspace hierarchy: Initiative › Project › Task.
/// A high-level, longer-term area that usually spans several projects
/// (e.g. "Q2 Analytics Improvements"). Persisted in `<storageDir>/initiatives.json`.
struct Initiative: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    /// Optional SF Symbol page icon.
    var icon: String?
    var colorHex: String?
    /// Markdown overview body for the initiative page.
    var body: String = ""
    /// Workspace context (Work / Personal / …) this initiative belongs to (1-1).
    /// Tasks inherit their context from their project's initiative. Optional +
    /// defaulted so old initiatives.json decodes.
    var contextID: String? = nil
    var status: Status = .active
    var sortIndex: Double?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    enum Status: String, Codable, CaseIterable, Identifiable {
        case active, archived
        var id: String { rawValue }
        var label: String { self == .active ? "Active" : "Archived" }
    }
}
