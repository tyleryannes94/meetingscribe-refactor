import Foundation

/// User-defined database property types (NP-1) — the primitive that turns a
/// project from "a task list" into a real Notion-style database where each
/// project defines its own columns.
enum PropertyType: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case text, number, select, checkbox, date, url
    var id: String { rawValue }
    var label: String {
        switch self {
        case .text: return "Text"
        case .number: return "Number"
        case .select: return "Select"
        case .checkbox: return "Checkbox"
        case .date: return "Date"
        case .url: return "URL"
        }
    }
    var systemImage: String {
        switch self {
        case .text: return "textformat"
        case .number: return "number"
        case .select: return "chevron.down.circle"
        case .checkbox: return "checkmark.square"
        case .date: return "calendar"
        case .url: return "link"
        }
    }
}

/// One column definition on a project's task database.
struct PropertyDefinition: Identifiable, Codable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var type: PropertyType
    /// Option labels for `.select`.
    var options: [String] = []
}

/// A typed value a task holds for a given `PropertyDefinition`.
enum PropertyValue: Codable, Hashable, Sendable {
    case text(String)
    case number(Double)
    case select(String)
    case checkbox(Bool)
    case date(Date)
    case url(String)

    /// Human-readable rendering for chips / cells.
    func displayString(_ formatter: DateFormatter = PropertyValue.dateFormatter) -> String {
        switch self {
        case .text(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .select(let s): return s
        case .checkbox(let b): return b ? "Yes" : "No"
        case .date(let d): return formatter.string(from: d)
        case .url(let u): return u
        }
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()
}
