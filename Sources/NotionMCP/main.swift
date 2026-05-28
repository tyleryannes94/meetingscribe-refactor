// NotionMCP — a Model Context Protocol server that wraps the Notion API.
//
// Newline-delimited JSON-RPC 2.0 over stdin/stdout, identical wire shape to
// MeetingScribeMCP. Reads its integration token from NOTION_API_KEY.
//
// Tools exposed:
//   - notion_search           : workspace search
//   - notion_get_page         : page metadata + child block content
//   - notion_get_block_children : child blocks of an arbitrary block id
//   - notion_query_database   : query a database with optional filter + sort
//   - notion_create_page      : create a new page under a parent
//   - notion_append_blocks    : append blocks (paragraphs / headings / lists)
//                               to a page

import Foundation
import VaultKit

// MARK: - Config

let NOTION_API = URL(string: "https://api.notion.com/v1")!
let NOTION_VERSION = "2022-06-28"

let apiKey: String? = {
    if let k = ProcessInfo.processInfo.environment["NOTION_API_KEY"], !k.isEmpty {
        return k
    }
    return nil
}()

// MARK: - JSON
//
// `JSONValue` lives in MeetingScribeShared — single canonical implementation
// shared with MeetingScribeMCP and the main app (audit 9.2).
// Alias kept for source-compat with the rest of this file.
typealias JSON = JSONValue

// MARK: - Notion HTTP helper

enum NotionError: Error, CustomStringConvertible {
    case missingKey
    case http(Int, String)
    case decode(String)
    var description: String {
        switch self {
        case .missingKey: return "NOTION_API_KEY env var not set. Pass it through Claude Desktop config or your shell."
        case .http(let c, let body): return "Notion HTTP \(c): \(body.prefix(400))"
        case .decode(let s): return "Notion decode error: \(s)"
        }
    }
}

func notionRequest(method: String, path: String, body: [String: Any]? = nil) async throws -> Any {
    guard let key = apiKey else { throw NotionError.missingKey }
    var req = URLRequest(url: NOTION_API.appendingPathComponent(path))
    req.httpMethod = method
    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    req.setValue(NOTION_VERSION, forHTTPHeaderField: "Notion-Version")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let body {
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (data, response) = try await URLSession.shared.data(for: req)
    guard let http = response as? HTTPURLResponse else {
        throw NotionError.http(-1, "no http")
    }
    guard (200..<300).contains(http.statusCode) else {
        let s = String(data: data, encoding: .utf8) ?? ""
        throw NotionError.http(http.statusCode, s)
    }
    let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    return json
}

// MARK: - Tool catalog

let toolList: [JSON] = [
    .object([
        "name": .string("notion_search"),
        "description": .string("Search the user's Notion workspace by text. Returns matched pages and databases with id + title."),
        "inputSchema": .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Text to search for.")
                ]),
                "filter_object_type": .object([
                    "type": .string("string"),
                    "description": .string("Optional: 'page' or 'database' to restrict results.")
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "default": .int(20)
                ])
            ]),
            "required": .array([.string("query")])
        ])
    ]),
    .object([
        "name": .string("notion_get_page"),
        "description": .string("Fetch a page's properties + its rendered child block content as Markdown."),
        "inputSchema": .object([
            "type": .string("object"),
            "required": .array([.string("page_id")]),
            "properties": .object([
                "page_id": .object(["type": .string("string")])
            ])
        ])
    ]),
    .object([
        "name": .string("notion_get_block_children"),
        "description": .string("List the direct children of any Notion block (page, toggle, column, etc.) as raw block objects."),
        "inputSchema": .object([
            "type": .string("object"),
            "required": .array([.string("block_id")]),
            "properties": .object([
                "block_id": .object(["type": .string("string")])
            ])
        ])
    ]),
    .object([
        "name": .string("notion_query_database"),
        "description": .string("Query a Notion database. Returns rows (each is a page) with their properties."),
        "inputSchema": .object([
            "type": .string("object"),
            "required": .array([.string("database_id")]),
            "properties": .object([
                "database_id": .object(["type": .string("string")]),
                "page_size": .object(["type": .string("integer"), "default": .int(50)]),
                "filter": .object([
                    "type": .string("object"),
                    "description": .string("Optional Notion filter object (see Notion API docs).")
                ])
            ])
        ])
    ]),
    .object([
        "name": .string("notion_create_page"),
        "description": .string("Create a new Notion page under a parent (page or database). Title goes in `title`. Body paragraphs go in `markdown`."),
        "inputSchema": .object([
            "type": .string("object"),
            "required": .array([.string("parent_id"), .string("title")]),
            "properties": .object([
                "parent_id": .object([
                    "type": .string("string"),
                    "description": .string("ID of the parent page or database.")
                ]),
                "parent_type": .object([
                    "type": .string("string"),
                    "description": .string("'page' or 'database'. Default: 'page'.")
                ]),
                "title": .object(["type": .string("string")]),
                "markdown": .object([
                    "type": .string("string"),
                    "description": .string("Optional initial body. Headings (#, ##, ###) and bullet points (- or *) are rendered as Notion blocks; everything else becomes paragraphs.")
                ])
            ])
        ])
    ]),
    .object([
        "name": .string("notion_append_blocks"),
        "description": .string("Append blocks of content to an existing page or block. `markdown` is parsed into Notion paragraph/heading/bullet blocks."),
        "inputSchema": .object([
            "type": .string("object"),
            "required": .array([.string("block_id"), .string("markdown")]),
            "properties": .object([
                "block_id": .object(["type": .string("string")]),
                "markdown": .object(["type": .string("string")])
            ])
        ])
    ])
]

// MARK: - Tool implementations

func tool_search(_ args: [String: Any]) async throws -> Any {
    guard let q = args["query"] as? String else { throw NotionError.http(400, "query required") }
    var body: [String: Any] = ["query": q, "page_size": (args["limit"] as? Int) ?? 20]
    if let kind = args["filter_object_type"] as? String {
        body["filter"] = ["value": kind, "property": "object"]
    }
    let result = try await notionRequest(method: "POST", path: "search", body: body)
    return summarizeSearchResults(result)
}

func summarizeSearchResults(_ raw: Any) -> Any {
    guard let dict = raw as? [String: Any],
          let results = dict["results"] as? [[String: Any]] else {
        return raw
    }
    let trimmed: [[String: Any]] = results.map { obj in
        var out: [String: Any] = [
            "id": obj["id"] as? String ?? "",
            "object": obj["object"] as? String ?? "",
            "url": obj["url"] as? String ?? ""
        ]
        out["title"] = titleFromProperties(obj)
        out["last_edited_time"] = obj["last_edited_time"] as? String ?? ""
        return out
    }
    return ["count": trimmed.count, "results": trimmed]
}

func titleFromProperties(_ obj: [String: Any]) -> String {
    // Pages: look in properties.* for a title-type property.
    if let props = obj["properties"] as? [String: Any] {
        for (_, value) in props {
            if let v = value as? [String: Any],
               (v["type"] as? String) == "title",
               let titleArray = v["title"] as? [[String: Any]] {
                return titleArray.compactMap { ($0["plain_text"] as? String) }.joined()
            }
        }
    }
    // Databases use a top-level title array.
    if let titleArray = obj["title"] as? [[String: Any]] {
        return titleArray.compactMap { ($0["plain_text"] as? String) }.joined()
    }
    return "(untitled)"
}

func tool_getPage(_ args: [String: Any]) async throws -> Any {
    guard let id = args["page_id"] as? String else { throw NotionError.http(400, "page_id required") }
    let pageMeta = try await notionRequest(method: "GET", path: "pages/\(id)")
    let children = try await notionRequest(method: "GET", path: "blocks/\(id)/children?page_size=100")
    let md = renderBlocksAsMarkdown(children)
    var dict: [String: Any] = ["id": id]
    if let p = pageMeta as? [String: Any] {
        dict["url"] = p["url"] ?? ""
        dict["title"] = titleFromProperties(p)
        dict["properties"] = compactProperties(p["properties"] as? [String: Any] ?? [:])
    }
    dict["markdown"] = md
    return dict
}

func tool_getBlockChildren(_ args: [String: Any]) async throws -> Any {
    guard let id = args["block_id"] as? String else { throw NotionError.http(400, "block_id required") }
    return try await notionRequest(method: "GET", path: "blocks/\(id)/children?page_size=100")
}

func tool_queryDatabase(_ args: [String: Any]) async throws -> Any {
    guard let id = args["database_id"] as? String else {
        throw NotionError.http(400, "database_id required")
    }
    var body: [String: Any] = ["page_size": (args["page_size"] as? Int) ?? 50]
    if let f = args["filter"] as? [String: Any] { body["filter"] = f }
    let result = try await notionRequest(method: "POST", path: "databases/\(id)/query", body: body)
    guard let dict = result as? [String: Any],
          let results = dict["results"] as? [[String: Any]] else { return result }
    let trimmed: [[String: Any]] = results.map { row in
        [
            "id": row["id"] as? String ?? "",
            "url": row["url"] as? String ?? "",
            "properties": compactProperties(row["properties"] as? [String: Any] ?? [:])
        ]
    }
    return ["count": trimmed.count, "rows": trimmed]
}

func tool_createPage(_ args: [String: Any]) async throws -> Any {
    guard let parentID = args["parent_id"] as? String,
          let title = args["title"] as? String else {
        throw NotionError.http(400, "parent_id + title required")
    }
    let parentType = (args["parent_type"] as? String) ?? "page"
    let parent: [String: Any] = parentType == "database"
        ? ["database_id": parentID]
        : ["page_id": parentID]
    var properties: [String: Any] = [:]
    if parentType == "page" {
        properties["title"] = ["title": [["text": ["content": title]]]]
    } else {
        // For database pages we have to know the title property name — use
        // "Name" by default, fall through if not found.
        properties["Name"] = ["title": [["text": ["content": title]]]]
    }
    var body: [String: Any] = ["parent": parent, "properties": properties]
    if let md = args["markdown"] as? String, !md.isEmpty {
        body["children"] = markdownToNotionBlocks(md)
    }
    return try await notionRequest(method: "POST", path: "pages", body: body)
}

func tool_appendBlocks(_ args: [String: Any]) async throws -> Any {
    guard let blockID = args["block_id"] as? String,
          let md = args["markdown"] as? String else {
        throw NotionError.http(400, "block_id + markdown required")
    }
    let children = markdownToNotionBlocks(md)
    return try await notionRequest(
        method: "PATCH",
        path: "blocks/\(blockID)/children",
        body: ["children": children]
    )
}

// MARK: - Block render / parse helpers

func renderBlocksAsMarkdown(_ raw: Any) -> String {
    guard let dict = raw as? [String: Any],
          let results = dict["results"] as? [[String: Any]] else { return "" }
    var lines: [String] = []
    for block in results {
        guard let type = block["type"] as? String,
              let inner = block[type] as? [String: Any] else { continue }
        let rich = inner["rich_text"] as? [[String: Any]] ?? []
        let text = rich.compactMap { $0["plain_text"] as? String }.joined()
        switch type {
        case "heading_1": lines.append("# \(text)")
        case "heading_2": lines.append("## \(text)")
        case "heading_3": lines.append("### \(text)")
        case "bulleted_list_item": lines.append("- \(text)")
        case "numbered_list_item": lines.append("1. \(text)")
        case "to_do":
            let checked = inner["checked"] as? Bool ?? false
            lines.append("- [\(checked ? "x" : " ")] \(text)")
        case "quote":     lines.append("> \(text)")
        case "code":      lines.append("```\n\(text)\n```")
        case "paragraph": lines.append(text)
        case "divider":   lines.append("---")
        default:
            if !text.isEmpty { lines.append(text) }
        }
    }
    return lines.joined(separator: "\n\n")
}

func markdownToNotionBlocks(_ markdown: String) -> [[String: Any]] {
    var blocks: [[String: Any]] = []
    for line in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }
        if trimmed.hasPrefix("### ") {
            blocks.append(notionTextBlock("heading_3", text: String(trimmed.dropFirst(4))))
        } else if trimmed.hasPrefix("## ") {
            blocks.append(notionTextBlock("heading_2", text: String(trimmed.dropFirst(3))))
        } else if trimmed.hasPrefix("# ") {
            blocks.append(notionTextBlock("heading_1", text: String(trimmed.dropFirst(2))))
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            blocks.append(notionTextBlock("bulleted_list_item", text: String(trimmed.dropFirst(2))))
        } else if trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
            let dotIdx = trimmed.firstIndex(of: ".")!
            let after = trimmed.index(dotIdx, offsetBy: 2, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            blocks.append(notionTextBlock("numbered_list_item", text: String(trimmed[after...])))
        } else if trimmed.hasPrefix("> ") {
            blocks.append(notionTextBlock("quote", text: String(trimmed.dropFirst(2))))
        } else if trimmed == "---" || trimmed == "***" {
            blocks.append(["object": "block", "type": "divider", "divider": [String: Any]()])
        } else {
            blocks.append(notionTextBlock("paragraph", text: trimmed))
        }
    }
    return blocks
}

func notionTextBlock(_ type: String, text: String) -> [String: Any] {
    [
        "object": "block",
        "type": type,
        type: ["rich_text": [["type": "text", "text": ["content": text]]]]
    ]
}

func compactProperties(_ props: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    for (name, value) in props {
        guard let v = value as? [String: Any], let type = v["type"] as? String else { continue }
        switch type {
        case "title":
            let arr = v["title"] as? [[String: Any]] ?? []
            out[name] = arr.compactMap { $0["plain_text"] as? String }.joined()
        case "rich_text":
            let arr = v["rich_text"] as? [[String: Any]] ?? []
            out[name] = arr.compactMap { $0["plain_text"] as? String }.joined()
        case "select":
            if let sel = v["select"] as? [String: Any] { out[name] = sel["name"] ?? "" }
        case "multi_select":
            if let arr = v["multi_select"] as? [[String: Any]] {
                out[name] = arr.compactMap { $0["name"] as? String }
            }
        case "date":
            if let d = v["date"] as? [String: Any] { out[name] = d }
        case "checkbox":
            out[name] = v["checkbox"] as? Bool ?? false
        case "number":
            out[name] = v["number"] as? Double ?? 0
        case "url":
            out[name] = v["url"] as? String ?? ""
        case "email":
            out[name] = v["email"] as? String ?? ""
        case "people":
            if let arr = v["people"] as? [[String: Any]] {
                out[name] = arr.compactMap { ($0["name"] as? String) ?? ($0["id"] as? String) }
            }
        default:
            out[name] = type
        }
    }
    return out
}

// MARK: - Tool dispatcher + JSON-RPC

func runTool(name: String, args: [String: Any]) async -> Any {
    do {
        switch name {
        case "notion_search":             return try await tool_search(args)
        case "notion_get_page":           return try await tool_getPage(args)
        case "notion_get_block_children": return try await tool_getBlockChildren(args)
        case "notion_query_database":     return try await tool_queryDatabase(args)
        case "notion_create_page":        return try await tool_createPage(args)
        case "notion_append_blocks":      return try await tool_appendBlocks(args)
        default: return ["error": "unknown tool: \(name)"]
        }
    } catch {
        return ["error": String(describing: error)]
    }
}

func writeResponse(id: Any?, result: JSON? = nil, error: (Int, String)? = nil) {
    var resp: [String: JSON] = ["jsonrpc": .string("2.0")]
    if let i = id as? Int { resp["id"] = .int(i) }
    else if let s = id as? String { resp["id"] = .string(s) }
    else { resp["id"] = .null }
    if let result { resp["result"] = result }
    if let error {
        resp["error"] = .object(["code": .int(error.0), "message": .string(error.1)])
    }
    let env = JSON.object(resp)
    let enc = JSONEncoder()
    if let data = try? enc.encode(env), let line = String(data: data, encoding: .utf8) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}

func jsonContentResult(_ value: Any) -> JSON {
    let data = (try? JSONSerialization.data(
        withJSONObject: value,
        options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])) ?? Data()
    let text = String(data: data, encoding: .utf8) ?? "{}"
    return .object([
        "content": .array([
            .object(["type": .string("text"), "text": .string(text)])
        ])
    ])
}

let serverInfo: JSON = .object([
    "protocolVersion": .string("2024-11-05"),
    "capabilities": .object(["tools": .object([:])]),
    "serverInfo": .object([
        "name": .string("notion"),
        "version": .string("0.1.0")
    ])
])

func handle(line: String) async {
    guard let data = line.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return
    }
    let id = obj["id"]
    let method = obj["method"] as? String ?? ""
    let params = obj["params"] as? [String: Any] ?? [:]

    switch method {
    case "initialize":
        writeResponse(id: id, result: serverInfo)
    case "initialized", "notifications/initialized":
        return
    case "tools/list":
        writeResponse(id: id, result: .object(["tools": .array(toolList)]))
    case "tools/call":
        guard let name = params["name"] as? String else {
            writeResponse(id: id, error: (-32602, "Missing tool name")); return
        }
        let args = (params["arguments"] as? [String: Any]) ?? [:]
        let result = await runTool(name: name, args: args)
        writeResponse(id: id, result: jsonContentResult(result))
    case "shutdown":
        writeResponse(id: id, result: .null); exit(0)
    case "ping":
        writeResponse(id: id, result: .object([:]))
    default:
        if id != nil {
            writeResponse(id: id, error: (-32601, "Method not found: \(method)"))
        }
    }
}

// Blocking stdin loop. For each line, run the async tool handler to
// completion before reading the next request — MCP is request/response so
// serializing is correct.
setbuf(stdout, nil)
while let line = readLine(strippingNewline: true) {
    if line.isEmpty { continue }
    let sem = DispatchSemaphore(value: 0)
    Task {
        await handle(line: line)
        sem.signal()
    }
    sem.wait()
}
