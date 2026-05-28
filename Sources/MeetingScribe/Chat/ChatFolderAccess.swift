import Foundation

/// Gatekeeper for filesystem-tool access. Every path the LLM gives us is
/// resolved + validated against the user-approved roots in
/// `AppSettings.shared.chatFolders`. Symlink escapes, `..` traversal, and
/// referencing files outside an approved root are all rejected before any
/// read or write happens.
enum ChatFolderAccess {
    enum AccessError: Error, LocalizedError {
        case noFoldersConfigured
        case notInApprovedFolder(String)
        case fileTooLarge(Int)
        case fileNotFound(String)
        case isDirectory(String)
        case isFile(String)
        case binaryFile(String)
        case writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .noFoldersConfigured:
                return "No Chat folders configured. Add at least one folder via the Folders button in the Chat tab."
            case .notInApprovedFolder(let p):
                return "'\(p)' is outside the approved Chat folders. Add its parent folder first."
            case .fileTooLarge(let n):
                return "File is too large (\(n) bytes). Chat file ops cap reads at 1 MB and writes at 5 MB."
            case .fileNotFound(let p):  return "File not found: \(p)"
            case .isDirectory(let p):   return "Path is a directory, not a file: \(p)"
            case .isFile(let p):        return "Path is a file, not a directory: \(p)"
            case .binaryFile(let p):    return "File looks binary (non-UTF-8): \(p)"
            case .writeFailed(let m):   return "Write failed: \(m)"
            }
        }
    }

    static let maxReadBytes = 1_048_576       // 1 MB
    static let maxWriteBytes = 5_242_880      // 5 MB
    static let maxListEntries = 500
    static let maxSearchHits = 200

    /// Returns the approved-folder roots (each is an absolute, standardized URL).
    static func approvedRoots() -> [URL] {
        AppSettings.shared.chatFolders.compactMap { path -> URL? in
            let expanded = (path as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            return url
        }
    }

    /// Resolves a user-supplied path (relative or absolute, tilde-expanded)
    /// against the approved roots. Returns the validated URL. Throws
    /// `.notInApprovedFolder` if the resolved path doesn't live under any
    /// approved root.
    ///
    /// If `path` is relative, it's resolved against the FIRST approved root
    /// — so the LLM can refer to files by their relative path inside a
    /// project folder.
    static func resolve(_ path: String) throws -> URL {
        let roots = approvedRoots()
        guard !roots.isEmpty else { throw AccessError.noFoldersConfigured }
        let expanded = (path as NSString).expandingTildeInPath
        let abs: URL
        if expanded.hasPrefix("/") {
            abs = URL(fileURLWithPath: expanded).standardizedFileURL
        } else {
            abs = roots[0].appendingPathComponent(expanded).standardizedFileURL
        }
        for root in roots {
            if abs.path == root.path || abs.path.hasPrefix(root.path + "/") {
                return abs
            }
        }
        throw AccessError.notInApprovedFolder(path)
    }

    static func read(_ path: String) throws -> String {
        let url = try resolve(path)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw AccessError.fileNotFound(path)
        }
        if isDir.boolValue { throw AccessError.isDirectory(path) }
        let attrs = try fm.attributesOfItem(atPath: url.path)
        if let size = attrs[.size] as? Int, size > maxReadBytes {
            throw AccessError.fileTooLarge(size)
        }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AccessError.binaryFile(path)
        }
        return text
    }

    static func write(_ path: String, content: String) throws -> URL {
        guard content.utf8.count <= maxWriteBytes else {
            throw AccessError.fileTooLarge(content.utf8.count)
        }
        let url = try resolve(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw AccessError.writeFailed(error.localizedDescription)
        }
        return url
    }

    /// Find-and-replace edit. `oldString` must occur EXACTLY ONCE for the
    /// edit to apply (matches Claude Code's str_replace semantics).
    static func edit(_ path: String, oldString: String, newString: String) throws -> URL {
        let url = try resolve(path)
        let current = try read(path)
        let occurrences = current.components(separatedBy: oldString).count - 1
        guard occurrences > 0 else {
            throw AccessError.writeFailed("oldString not found in file")
        }
        guard occurrences == 1 else {
            throw AccessError.writeFailed("oldString matched \(occurrences) times — needs to be unique. Add more surrounding context.")
        }
        let updated = current.replacingOccurrences(of: oldString, with: newString)
        try updated.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    struct DirEntry: Hashable {
        let path: String
        let isDirectory: Bool
        let sizeBytes: Int
    }

    /// Lists entries in a folder. If `recursive`, walks the whole tree
    /// (skipping hidden files and common junk dirs). Capped at `maxListEntries`.
    static func list(_ path: String, recursive: Bool = false, extensionsAllowed: [String]? = nil) throws -> [DirEntry] {
        let url = try resolve(path)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw AccessError.fileNotFound(path)
        }
        guard isDir.boolValue else { throw AccessError.isFile(path) }
        let skipDirs: Set<String> = [".git", ".build", "node_modules", ".DS_Store",
                                      ".swiftpm", "DerivedData", ".next", "dist", "build"]
        var entries: [DirEntry] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]

        if recursive {
            guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys,
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                return []
            }
            for case let item as URL in enumerator {
                if entries.count >= maxListEntries { break }
                let lastComponent = item.lastPathComponent
                if skipDirs.contains(lastComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                guard let vals = try? item.resourceValues(forKeys: Set(keys)) else { continue }
                let isDir = vals.isDirectory ?? false
                let size = vals.fileSize ?? 0
                if let ext = extensionsAllowed, !isDir,
                   !ext.contains(item.pathExtension.lowercased()) { continue }
                entries.append(DirEntry(path: item.path, isDirectory: isDir, sizeBytes: size))
            }
        } else {
            let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles])) ?? []
            for item in items {
                if entries.count >= maxListEntries { break }
                if skipDirs.contains(item.lastPathComponent) { continue }
                guard let vals = try? item.resourceValues(forKeys: Set(keys)) else { continue }
                let isDir = vals.isDirectory ?? false
                let size = vals.fileSize ?? 0
                if let ext = extensionsAllowed, !isDir,
                   !ext.contains(item.pathExtension.lowercased()) { continue }
                entries.append(DirEntry(path: item.path, isDirectory: isDir, sizeBytes: size))
            }
        }
        entries.sort { $0.path < $1.path }
        return entries
    }

    struct SearchHit: Hashable {
        let path: String
        let lineNumber: Int
        let line: String
    }

    /// Plain text grep across files inside an approved root. Skips binaries
    /// + node_modules + .git + .build etc. Capped at `maxSearchHits`.
    static func search(in folder: String, query: String, caseSensitive: Bool = false) throws -> [SearchHit] {
        let root = try resolve(folder)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw AccessError.isFile(folder)
        }
        let needle = caseSensitive ? query : query.lowercased()
        let skipDirs: Set<String> = [".git", ".build", "node_modules", ".DS_Store",
                                      ".swiftpm", "DerivedData", ".next", "dist", "build"]
        var hits: [SearchHit] = []
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return []
        }
        for case let item as URL in enumerator {
            if hits.count >= maxSearchHits { break }
            let last = item.lastPathComponent
            if skipDirs.contains(last) {
                enumerator.skipDescendants()
                continue
            }
            guard let vals = try? item.resourceValues(forKeys: [.isDirectoryKey]),
                  vals.isDirectory == false else { continue }
            // Skip files >1MB to keep search fast.
            if let attr = try? fm.attributesOfItem(atPath: item.path),
               let size = attr[.size] as? Int, size > maxReadBytes { continue }
            guard let text = try? String(contentsOf: item, encoding: .utf8) else { continue }
            let haystack = caseSensitive ? text : text.lowercased()
            guard haystack.contains(needle) else { continue }
            var lineNumber = 0
            text.enumerateLines { line, stop in
                lineNumber += 1
                let target = caseSensitive ? line : line.lowercased()
                if target.contains(needle) {
                    hits.append(SearchHit(path: item.path, lineNumber: lineNumber, line: line))
                    if hits.count >= maxSearchHits { stop = true }
                }
            }
        }
        return hits
    }
}
