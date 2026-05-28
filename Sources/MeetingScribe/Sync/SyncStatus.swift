import Foundation

/// High-level state of the iCloud sync engine, surfaced to the UI.
enum SyncStatus {
    case idle
    case syncing
    case error(Error)
    case upToDate

    /// Human-readable one-liner for the settings row / status pill.
    var label: String {
        switch self {
        case .idle:        return "Off"
        case .syncing:     return "Syncing…"
        case .upToDate:    return "Up to date"
        case .error(let e): return "Error: \(e.localizedDescription)"
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}
