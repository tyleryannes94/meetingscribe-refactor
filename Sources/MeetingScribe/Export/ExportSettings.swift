import Foundation

/// User-configurable export preferences (Obsidian vault location + an optional
/// filename template). Backed by `UserDefaults` so it can be read from anywhere
/// without threading state through the app graph.
struct ExportSettings {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let vaultPath = "obsidianVaultPath"
        static let filenameTemplate = "obsidianFilenameTemplate"
    }

    /// Absolute path to the Obsidian vault folder (or a subfolder within it).
    /// Empty/unset means "ask with a save panel on export".
    var vaultPath: String {
        get { defaults.string(forKey: Keys.vaultPath) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Keys.vaultPath) }
    }

    var vaultURL: URL? {
        let p = vaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return nil }
        return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
    }

    /// Filename template. Supported tokens: `{date}`, `{title}`, `{slug}`.
    /// Defaults to the meeting slug.
    var filenameTemplate: String {
        get { defaults.string(forKey: Keys.filenameTemplate) ?? "{slug}" }
        nonmutating set { defaults.set(newValue, forKey: Keys.filenameTemplate) }
    }

    /// Resolve the template for a given meeting into a filesystem-safe basename.
    func filename(forSlug slug: String, title: String, date: Date) -> String {
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let resolved = filenameTemplate
            .replacingOccurrences(of: "{date}", with: df.string(from: date))
            .replacingOccurrences(of: "{title}", with: title)
            .replacingOccurrences(of: "{slug}", with: slug)
        let safe = resolved.replacingOccurrences(of: "/", with: "-")
        return safe.isEmpty ? slug : safe
    }
}
