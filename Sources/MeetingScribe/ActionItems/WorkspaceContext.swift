import Foundation

/// A top-level life context — "Work", "Personal", … — that partitions the
/// whole Tasks workspace (1-1, the audit's #1 convergence theme). Initiatives
/// (and, optionally, individual tasks) carry a `contextID`; the sidebar context
/// switcher, Today view, Home board, and color coding all scope by it.
///
/// Persisted to `<storageDir>/contexts.json`. Two are seeded on first launch
/// (Work / Personal); the user can add, rename, recolor, or delete more.
struct WorkspaceContext: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    /// Hex like "#4F8DFD". Drives the context pill, row bar, and card stripe.
    var colorHex: String?
    var sortIndex: Double?
    var createdAt: Date = Date()

    /// The two contexts every workspace starts with.
    static let seededWorkName = "Work"
    static let seededPersonalName = "Personal"
    static func seedDefaults() -> [WorkspaceContext] {
        [
            WorkspaceContext(name: seededWorkName, colorHex: "#4F8DFD", sortIndex: 0),
            WorkspaceContext(name: seededPersonalName, colorHex: "#34C759", sortIndex: 1),
        ]
    }
}
