import Foundation
import VaultKit

/// Chat tools that read and write files inside the user's approved Chat
/// folders. Every path is sandboxed by `ChatFolderAccess` — escapes (../, /etc/,
/// symlinks pointing outside) error out rather than silently traversing.
///
/// Tools owned by this class:
///   list_chat_folders, list_files, read_file, write_file, edit_file,
///   search_files
///
/// This class doesn't need a `MeetingManager` — it operates purely on
/// `ChatFolderAccess`. It still lives on the main actor because the
/// approved-roots set is read on the main thread.
@MainActor
final class FileChatTools {

    init() {}

    // MARK: - Tool catalog

    var tools: [AnthropicClient.Tool] {
        [
            .init(
                name: "list_chat_folders",
                description: "List the user's approved Chat folders. Every file tool below is sandboxed to paths INSIDE these roots — you can't escape them.",
                input_schema: .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ])
            ),
            .init(
                name: "list_files",
                description: "List files in an approved Chat folder. Pass `recursive: true` to walk the whole tree (.git, node_modules, .build are auto-skipped). Optional `extensions: [\"md\", \"swift\"]` filters by extension.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("folder")]),
                    "properties": .object([
                        "folder": .object([
                            "type": .string("string"),
                            "description": .string("Absolute path or path relative to the first approved Chat folder.")
                        ]),
                        "recursive": .object([
                            "type": .string("boolean"),
                            "default": .bool(false)
                        ]),
                        "extensions": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("string")])
                        ])
                    ])
                ])
            ),
            .init(
                name: "read_file",
                description: "Read the full UTF-8 contents of a file inside an approved Chat folder. Cap: 1 MB.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("path")]),
                    "properties": .object([
                        "path": .object(["type": .string("string")])
                    ])
                ])
            ),
            .init(
                name: "write_file",
                description: "Overwrite or create a file at `path`. The parent directory must be inside an approved Chat folder. Cap: 5 MB. USE SPARINGLY — prefer `edit_file` for targeted changes.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("path"), .string("content")]),
                    "properties": .object([
                        "path": .object(["type": .string("string")]),
                        "content": .object(["type": .string("string")])
                    ])
                ])
            ),
            .init(
                name: "edit_file",
                description: "Find-and-replace edit. `old_string` must appear EXACTLY ONCE in the file (or the call errors out). Provide enough surrounding context to make `old_string` unique. The file must be inside an approved Chat folder.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("path"), .string("old_string"), .string("new_string")]),
                    "properties": .object([
                        "path": .object(["type": .string("string")]),
                        "old_string": .object(["type": .string("string")]),
                        "new_string": .object(["type": .string("string")])
                    ])
                ])
            ),
            .init(
                name: "search_files",
                description: "Plain-text grep across an approved Chat folder. Returns `[{path, lineNumber, line}]` — capped at 200 hits.",
                input_schema: .object([
                    "type": .string("object"),
                    "required": .array([.string("folder"), .string("query")]),
                    "properties": .object([
                        "folder": .object(["type": .string("string")]),
                        "query":  .object(["type": .string("string")]),
                        "case_sensitive": .object([
                            "type": .string("boolean"),
                            "default": .bool(false)
                        ])
                    ])
                ])
            )
        ]
    }

    // MARK: - Tool dispatcher

    func run(name: String, input: [String: JSONValue]) async -> Result<String, Error>? {
        switch name {
        case "list_chat_folders": return .success(listChatFolders())
        case "list_files":        return listFiles(input)
        case "read_file":         return readFile(input)
        case "write_file":        return writeFile(input)
        case "edit_file":         return editFile(input)
        case "search_files":      return searchFiles(input)
        default:                  return nil
        }
    }

    // MARK: - Tool bodies

    private func listChatFolders() -> String {
        let roots = ChatFolderAccess.approvedRoots()
        let rows = roots.map { ["path": $0.path] }
        return ChatToolHelpers.jsonString([
            "folders": rows,
            "count": rows.count,
            "note": rows.isEmpty
                ? "No folders configured. The user needs to add one via the Folders sheet in the Chat tab."
                : "All file operations are sandboxed to paths inside these roots."
        ])
    }

    private func listFiles(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let folder = input["folder"]?.asString else {
            return .failure(AnthropicClient.ClientError.toolExecutionFailed("list_files", "folder is required"))
        }
        let recursive: Bool = {
            if case let .bool(b) = input["recursive"] ?? .null { return b }
            return false
        }()
        var allowedExts: [String]? = nil
        if case let .array(arr) = input["extensions"] ?? .null {
            allowedExts = arr.compactMap { $0.asString?.lowercased() }
        }
        do {
            let entries = try ChatFolderAccess.list(folder,
                                                       recursive: recursive,
                                                       extensionsAllowed: allowedExts)
            let rows: [[String: Any]] = entries.map {
                ["path": $0.path, "isDirectory": $0.isDirectory, "sizeBytes": $0.sizeBytes]
            }
            return .success(ChatToolHelpers.jsonString([
                "folder": folder,
                "recursive": recursive,
                "count": rows.count,
                "entries": rows
            ]))
        } catch {
            return .failure(error)
        }
    }

    private func readFile(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let path = input["path"]?.asString else {
            return .failure(AnthropicClient.ClientError.toolExecutionFailed("read_file", "path is required"))
        }
        do {
            let text = try ChatFolderAccess.read(path)
            return .success(ChatToolHelpers.jsonString(["path": path, "content": text]))
        } catch {
            return .failure(error)
        }
    }

    private func writeFile(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let path = input["path"]?.asString,
              let content = input["content"]?.asString else {
            return .failure(AnthropicClient.ClientError.toolExecutionFailed("write_file", "path + content required"))
        }
        do {
            let url = try ChatFolderAccess.write(path, content: content)
            return .success(ChatToolHelpers.jsonString([
                "ok": true,
                "path": url.path,
                "bytesWritten": content.utf8.count
            ]))
        } catch {
            return .failure(error)
        }
    }

    private func editFile(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let path = input["path"]?.asString,
              let oldS = input["old_string"]?.asString,
              let newS = input["new_string"]?.asString else {
            return .failure(AnthropicClient.ClientError.toolExecutionFailed("edit_file", "path, old_string, new_string required"))
        }
        do {
            let url = try ChatFolderAccess.edit(path, oldString: oldS, newString: newS)
            return .success(ChatToolHelpers.jsonString(["ok": true, "path": url.path]))
        } catch {
            return .failure(error)
        }
    }

    private func searchFiles(_ input: [String: JSONValue]) -> Result<String, Error> {
        guard let folder = input["folder"]?.asString,
              let query = input["query"]?.asString else {
            return .failure(AnthropicClient.ClientError.toolExecutionFailed("search_files", "folder + query required"))
        }
        let caseSensitive: Bool = {
            if case let .bool(b) = input["case_sensitive"] ?? .null { return b }
            return false
        }()
        do {
            let hits = try ChatFolderAccess.search(in: folder, query: query, caseSensitive: caseSensitive)
            let rows: [[String: Any]] = hits.map {
                ["path": $0.path, "lineNumber": $0.lineNumber, "line": $0.line]
            }
            return .success(ChatToolHelpers.jsonString([
                "folder": folder, "query": query,
                "count": rows.count, "hits": rows
            ]))
        } catch {
            return .failure(error)
        }
    }
}
