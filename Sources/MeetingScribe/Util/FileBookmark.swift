import AppKit

/// Tiny helper for remembering and opening a user-selected local file across
/// launches. The app is NOT sandboxed (see ScribeCore.entitlements —
/// `app-sandbox = false`), so a plain bookmark is enough to survive moves and
/// renames, and `NSWorkspace.open` works on any resolved path. The
/// security-scope calls are harmless no-ops today but keep this forward
/// compatible if the app is ever sandboxed (then `make` would use
/// `.withSecurityScope`).
enum FileBookmark {
    /// Create a bookmark for a file the user just picked.
    static func make(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolve a stored bookmark back to a URL (nil if the file is gone).
    static func resolve(_ data: Data) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [],
                        relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// Open a bookmarked file in its default app (Finder/Preview/Figma/etc.).
    @discardableResult
    static func open(_ data: Data) -> Bool {
        guard let url = resolve(data) else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return NSWorkspace.shared.open(url)
    }
}
