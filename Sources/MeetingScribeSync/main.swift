// MeetingScribeSync — hub-side ingestion / merge engine.
//
// Reads work-device files that a transport (rsync / Syncthing / Git / in-app
// push) has deposited in the hub's quarantine namespace:
//
//     <vault>/_remote/<device>/…   (a faithful copy of the work Mac's vault)
//
// …and ADDITIVELY merges them into the hub's live second brain WITHOUT ever
// overwriting or deleting a record that already exists. New meetings are copied
// into a clearly-namespaced `_imported-<device>/<slug>/` folder (which the app's
// depth-3 scanner discovers on its next index rebuild); people / tasks / tags are
// union-merged by patching the raw on-disk JSON (the same lossless approach the
// MCP write tools use — we never decode-and-re-encode through a lossy DTO).
//
// SAFETY: default mode is a DRY RUN that only reports what *would* change. Nothing
// touches the live vault unless you pass `--apply`. Even with `--apply`, the engine
// has no delete path and never overwrites an existing meeting/person/task — it only
// adds new records and unions new sub-data into existing ones. Re-runs are cheap and
// idempotent via a content-hash ledger at `<vault>/_remote/.import-ledger.json`.
//
// Usage:
//   MeetingScribeSync [--apply] [--device NAME] [--storage PATH] [--verbose]
//   MeetingScribeSync --self-test     # run in-memory assertions on the merge logic
//   MeetingScribeSync --help
//
// Storage is resolved from: --storage → $MEETINGSCRIBE_STORAGE → the iCloud default.
// Intended to run ON THE HUB, e.g. from a launchd job after the rsync transport lands
// new files. It only ever reads from `_remote/` and writes into the live vault + the
// ledger; it never modifies the staged source files.

import Foundation
import VaultKit

// MARK: - Constants

let peopleSchemaVersion = 1
let meetingSchemaVersion = 2
let actionItemSchemaVersion = 1

/// Folders the live-vault scan must never treat as meeting groupings. Mirrors
/// MeetingStore.reservedFolders + our own staging/landing namespaces.
let reservedScanFolders: Set<String> = ["models", "QuickNotes", "logs", "diagnostics", "chunks", "_remote"]

// MARK: - CLI

struct Options {
    var apply = false
    var device: String?
    var storage: String?
    var verbose = false
    var selfTest = false
    var help = false
}

func parseOptions() -> Options {
    var o = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--apply": o.apply = true
        case "--dry-run", "-n": o.apply = false
        case "--verbose", "-v": o.verbose = true
        case "--self-test": o.selfTest = true
        case "--help", "-h": o.help = true
        case "--device": o.device = it.next()
        case "--storage": o.storage = it.next()
        default: FileHandle.standardError.write("warning: unknown argument \(a)\n".data(using: .utf8)!)
        }
    }
    return o
}

let helpText = """
MeetingScribeSync — fold a work device's backup into your hub's second brain.

USAGE
  MeetingScribeSync [options]

OPTIONS
  --apply            Actually perform the merge. Without this it's a DRY RUN
                     (reports what would change; writes nothing).
  --device NAME      Only ingest <vault>/_remote/NAME (default: every device).
  --storage PATH     Hub vault root. Default: $MEETINGSCRIBE_STORAGE or iCloud.
  --verbose, -v      Print every record decision.
  --self-test        Run in-memory assertions on the merge logic and exit.
  --help, -h         Show this help.

SAFETY
  • Default is dry-run — nothing changes until you pass --apply.
  • No delete path: work-side deletions never propagate.
  • Never overwrites an existing meeting/person/task; only adds + unions.
  • New meetings land in _imported-<device>/<slug>/ (a sibling of your own data).
  • Idempotent via a content-hash ledger; re-running is a cheap no-op.
"""

// MARK: - Storage resolution

func resolveStorage(_ opts: Options) -> URL {
    if let s = opts.storage, !s.isEmpty {
        return URL(fileURLWithPath: (s as NSString).expandingTildeInPath)
    }
    if let env = ProcessInfo.processInfo.environment["MEETINGSCRIBE_STORAGE"], !env.isEmpty {
        return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
    }
    return VaultPaths.defaultVaultURL
}

/// Containment guard (mirrors the MCP server's resolveInsideVault). Returns the
/// standardized URL only when it resolves to a path inside `root`.
func insideVault(_ url: URL, root: URL) -> Bool {
    let base = root.standardizedFileURL.path
    let p = url.standardizedFileURL.path
    if p == base { return true }
    let prefix = base.hasSuffix("/") ? base : base + "/"
    return p.hasPrefix(prefix)
}

// MARK: - Content hashing (FNV-1a 64-bit — no external dependency)

func fnv1a(_ data: Data) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    let prime: UInt64 = 0x100000001b3
    data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
        for b in buf { hash = (hash ^ UInt64(b)) &* prime }
    }
    return String(hash, radix: 16)
}

func fileHash(_ url: URL) -> String {
    guard let d = try? Data(contentsOf: url) else { return "0" }
    return fnv1a(d)
}

// MARK: - Import ledger (idempotency)

struct Ledger: Codable {
    var schemaVersion = 1
    var records: [String: String] = [:]   // namespaced key -> last-imported content hash

    static func url(in storage: URL) -> URL {
        storage.appendingPathComponent("_remote/.import-ledger.json")
    }
    static func load(in storage: URL) -> Ledger {
        guard let d = try? Data(contentsOf: url(in: storage)),
              let l = try? JSONDecoder().decode(Ledger.self, from: d) else { return Ledger() }
        return l
    }
    func save(in storage: URL) {
        let u = Ledger.url(in: storage)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(self) { try? d.write(to: u, options: .atomic) }
    }
}

// MARK: - Raw JSON helpers (lossless patching — never round-trip through DTOs)

func readObject(_ url: URL) -> [String: Any]? {
    guard let d = try? Data(contentsOf: url),
          let o = try? JSONSerialization.jsonObject(with: d) else { return nil }
    return o as? [String: Any]
}

/// Unwrap a SchemaEnvelope `{schemaVersion, data:{…}}` to its payload object,
/// tolerating a legacy bare object.
func objectPayload(_ obj: [String: Any]) -> [String: Any] {
    if let data = obj["data"] as? [String: Any] { return data }
    return obj
}

func writeEnvelopeObject(_ payload: [String: Any], schemaVersion: Int, to url: URL) throws {
    let env: [String: Any] = ["schemaVersion": schemaVersion, "data": payload]
    guard JSONSerialization.isValidJSONObject(env) else { throw Err.invalidJSON(url.lastPathComponent) }
    let data = try JSONSerialization.data(withJSONObject: env, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
}

enum Err: Error { case invalidJSON(String) }

// MARK: - Union helpers

func unionStrings(_ a: Any?, _ b: Any?) -> [String] {
    var seen = Set<String>(); var out: [String] = []
    for v in ((a as? [String]) ?? []) + ((b as? [String]) ?? []) where seen.insert(v).inserted {
        out.append(v)
    }
    return out
}

func unionByID(_ a: Any?, _ b: Any?, key: String = "id") -> [[String: Any]] {
    var seen = Set<String>(); var out: [[String: Any]] = []
    for item in ((a as? [[String: Any]]) ?? []) + ((b as? [[String: Any]]) ?? []) {
        let k = (item[key] as? String) ?? UUID().uuidString
        if seen.insert(k).inserted { out.append(item) }
    }
    return out
}

/// Union emails case-insensitively, keeping the first (live) display form so
/// "jane@acme.com" + "JANE@acme.com" collapse to one. Blank values dedupe as-is.
func unionEmails(_ a: Any?, _ b: Any?) -> [String] {
    var seen = Set<String>(); var out: [String] = []
    for v in ((a as? [String]) ?? []) + ((b as? [String]) ?? []) {
        let n = normEmail(v)
        let key = n.isEmpty ? v : n
        if seen.insert(key).inserted { out.append(v) }
    }
    return out
}

/// Union phones by last-10-digits, keeping the first (live) display form so
/// "+1 (555) 123-4567" and "5551234567" collapse to one.
func unionPhones(_ a: Any?, _ b: Any?) -> [String] {
    var seen = Set<String>(); var out: [String] = []
    for v in ((a as? [String]) ?? []) + ((b as? [String]) ?? []) {
        let n = normPhone(v)
        let key = n.count >= 7 ? n : v
        if seen.insert(key).inserted { out.append(v) }
    }
    return out
}

func nonEmptyString(_ v: Any?) -> Bool { if let s = v as? String { return !s.isEmpty }; return false }

let isoFormatter = ISO8601DateFormatter()
func isoNow() -> String { isoFormatter.string(from: Date()) }

/// Lexicographic max of two ISO-8601 date strings (ISO-8601 sorts correctly).
func maxISO(_ a: Any?, _ b: Any?) -> String? {
    switch (a as? String, b as? String) {
    case let (x?, y?): return x >= y ? x : y
    case let (x?, nil): return x
    case let (nil, y?): return y
    default: return nil
    }
}

func normEmail(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
func normPhone(_ s: String) -> String { String(s.filter(\.isNumber).suffix(10)) }
func normName(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }

// MARK: - Report

final class Report {
    var meetingsImported = 0, meetingsSkipped = 0
    var peopleCreated = 0, peopleMerged = 0, peopleSkipped = 0
    var actionItemsAdded = 0, tagsAdded = 0, tagAssignmentsAdded = 0
    var conflicts: [String] = []
    var changed = false

    func print(dryRun: Bool) {
        let mode = dryRun ? "DRY RUN (no changes written — pass --apply to perform)" : "APPLIED"
        Swift.print("""

        ── MeetingScribeSync — \(mode) ──
        Meetings : \(meetingsImported) imported, \(meetingsSkipped) already present
        People   : \(peopleCreated) created, \(peopleMerged) merged, \(peopleSkipped) unchanged
        Tasks    : \(actionItemsAdded) added
        Tags     : \(tagsAdded) new tag(s), \(tagAssignmentsAdded) assignment(s)
        """)
        if !conflicts.isEmpty {
            Swift.print("Conflicts (left for review, not applied):")
            for c in conflicts { Swift.print("  • \(c)") }
        }
        Swift.print("────────────────────────────────────────\n")
    }
}

// MARK: - Directory walking

/// Find every directory containing `meeting.json` under `root`, depth-limited,
/// skipping reserved + landing folders and anything hidden.
func findMeetingDirs(under root: URL, skipImported: Bool = false) -> [URL] {
    let fm = FileManager.default
    var out: [URL] = []
    func walk(_ dir: URL, depth: Int) {
        let entries = (try? fm.contentsOfDirectory(at: dir,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for url in entries {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let name = url.lastPathComponent
            if reservedScanFolders.contains(name) { continue }
            if skipImported && name.hasPrefix("_imported-") { continue }
            if fm.fileExists(atPath: url.appendingPathComponent("meeting.json").path) {
                out.append(url); continue   // a meeting dir won't contain nested meeting dirs
            }
            if depth > 0 { walk(url, depth: depth - 1) }
        }
    }
    walk(root, depth: 4)
    return out
}

/// Collect the ids of meetings already present in the LIVE vault (includes
/// previously-imported ones so re-runs don't duplicate; excludes the staging tree).
func liveMeetingIDs(storage: URL) -> Set<String> {
    var ids = Set<String>()
    for dir in findMeetingDirs(under: storage) {
        if let obj = readObject(dir.appendingPathComponent("meeting.json")),
           let id = objectPayload(obj)["id"] as? String {
            ids.insert(id)
        }
    }
    return ids
}

func uniqueDestination(_ base: URL) -> URL {
    let fm = FileManager.default
    if !fm.fileExists(atPath: base.path) { return base }
    var n = 2
    while true {
        let candidate = base.deletingLastPathComponent()
            .appendingPathComponent("\(base.lastPathComponent)-\(n)")
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        n += 1
    }
}

// MARK: - Meetings ingest

func ingestMeetings(deviceRoot: URL, device: String, storage: URL,
                    liveIDs: inout Set<String>, ledger: inout Ledger,
                    opts: Options, report: Report) {
    let fm = FileManager.default
    let landing = storage.appendingPathComponent("_imported-\(device)", isDirectory: true)

    for src in findMeetingDirs(under: deviceRoot, skipImported: true) {
        let mjson = src.appendingPathComponent("meeting.json")
        guard let obj = readObject(mjson) else { continue }
        let payload = objectPayload(obj)
        guard let id = payload["id"] as? String else { continue }

        let key = "\(device)/meeting:\(id)"
        let hash = fileHash(mjson)
        if ledger.records[key] == hash { continue }   // unchanged since last run

        if liveIDs.contains(id) {
            report.meetingsSkipped += 1
            if opts.verbose { print("  meeting \(id): already present — skip") }
            ledger.records[key] = hash
            continue
        }

        let slug = src.lastPathComponent
        let dest = uniqueDestination(landing.appendingPathComponent(slug, isDirectory: true))
        let rel = "_imported-\(device)/\(dest.lastPathComponent)"
        if opts.verbose { print("  meeting \(id): import -> \(rel)") }

        if opts.apply {
            guard insideVault(dest, root: storage) else { report.conflicts.append("meeting \(id) path escape"); continue }
            do {
                try fm.createDirectory(at: landing, withIntermediateDirectories: true)
                try fm.copyItem(at: src, to: dest)
                // Patch the copied meeting.json so it resolves on the hub.
                var patched = payload
                patched["relativeFolderPath"] = rel
                patched["isImported"] = true
                try writeEnvelopeObject(patched, schemaVersion: meetingSchemaVersion,
                                        to: dest.appendingPathComponent("meeting.json"))
            } catch {
                report.conflicts.append("meeting \(id) copy failed: \(error.localizedDescription)")
                continue
            }
        }
        liveIDs.insert(id)
        ledger.records[key] = hash
        report.meetingsImported += 1
        report.changed = true
    }
}

// MARK: - People ingest

struct LivePerson { let dir: URL; let payload: [String: Any] }

func loadLivePeople(storage: URL) -> [LivePerson] {
    let root = storage.appendingPathComponent("people", isDirectory: true)
    let fm = FileManager.default
    guard let dirs = try? fm.contentsOfDirectory(at: root,
        includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
    var out: [LivePerson] = []
    for dir in dirs {
        guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
        if let obj = readObject(dir.appendingPathComponent("person.json")) {
            out.append(LivePerson(dir: dir, payload: objectPayload(obj)))
        }
    }
    return out
}

/// Find the live person this staged record refers to: same id, else shared
/// email/phone, else exact (normalized) name. Returns nil for a brand-new person.
func matchLivePerson(_ staged: [String: Any], in live: [LivePerson]) -> LivePerson? {
    let sid = staged["id"] as? String
    if let sid, let m = live.first(where: { ($0.payload["id"] as? String) == sid }) { return m }

    let sEmails = Set(((staged["emails"] as? [String]) ?? []).map(normEmail).filter { !$0.isEmpty })
    let sPhones = Set(((staged["phones"] as? [String]) ?? []).map(normPhone).filter { $0.count >= 7 })
    if !sEmails.isEmpty || !sPhones.isEmpty {
        if let m = live.first(where: { lp in
            let le = Set(((lp.payload["emails"] as? [String]) ?? []).map(normEmail))
            let lph = Set(((lp.payload["phones"] as? [String]) ?? []).map(normPhone))
            return !le.isDisjoint(with: sEmails) || !lph.isDisjoint(with: sPhones)
        }) { return m }
    }
    if let sName = (staged["displayName"] as? String).map(normName), !sName.isEmpty {
        if let m = live.first(where: { (($0.payload["displayName"] as? String).map(normName)) == sName }) { return m }
    }
    return nil
}

/// Additive union-merge of a staged person payload into a live one. Starts from
/// the LIVE payload so unknown fields (photos, contactIdentifier, …) are preserved;
/// only adds. Returns the merged payload.
func mergePersonPayload(live: [String: Any], staged: [String: Any], device: String) -> [String: Any] {
    var m = live
    m["emails"] = unionEmails(live["emails"], staged["emails"])
    m["phones"] = unionPhones(live["phones"], staged["phones"])
    m["addresses"] = unionStrings(live["addresses"], staged["addresses"])
    m["favorites"] = unionStrings(live["favorites"], staged["favorites"])
    m["tagIDs"] = unionStrings(live["tagIDs"], staged["tagIDs"])
    m["meetingMentions"] = unionStrings(live["meetingMentions"], staged["meetingMentions"])
    m["photoRelativePaths"] = unionStrings(live["photoRelativePaths"], staged["photoRelativePaths"])
    m["memories"] = unionByID(live["memories"], staged["memories"])
    m["relationships"] = unionByID(live["relationships"], staged["relationships"])
    m["attachedNotes"] = unionByID(live["attachedNotes"], staged["attachedNotes"])

    var sources = unionStrings(live["importSources"], staged["importSources"])
    if !sources.contains(device) { sources.append(device) }
    m["importSources"] = sources

    for k in ["company", "role", "bio"] where !nonEmptyString(m[k]) && nonEmptyString(staged[k]) {
        m[k] = staged[k]
    }
    if m["birthday"] == nil, let b = staged["birthday"] { m["birthday"] = b }
    if let li = maxISO(live["lastInteractionAt"], staged["lastInteractionAt"]) { m["lastInteractionAt"] = li }
    m["updatedAt"] = isoNow()
    return m
}

func ingestPeople(deviceRoot: URL, device: String, storage: URL,
                  ledger: inout Ledger, opts: Options, report: Report) {
    let fm = FileManager.default
    let stagedRoot = deviceRoot.appendingPathComponent("people", isDirectory: true)
    guard let dirs = try? fm.contentsOfDirectory(at: stagedRoot,
        includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }

    var live = loadLivePeople(storage: storage)   // refreshed lazily after creates
    let peopleRoot = storage.appendingPathComponent("people", isDirectory: true)

    for dir in dirs {
        guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
        let pjson = dir.appendingPathComponent("person.json")
        guard let obj = readObject(pjson) else { continue }
        let staged = objectPayload(obj)
        guard let id = staged["id"] as? String else { continue }

        let key = "\(device)/person:\(id)"
        let hash = fileHash(pjson)
        if ledger.records[key] == hash { report.peopleSkipped += 1; continue }

        if let match = matchLivePerson(staged, in: live) {
            if opts.verbose { print("  person \(id) (\(staged["displayName"] as? String ?? "?")): merge into \(match.dir.lastPathComponent)") }
            if opts.apply {
                let merged = mergePersonPayload(live: match.payload, staged: staged, device: device)
                guard insideVault(match.dir, root: storage) else { report.conflicts.append("person \(id) path escape"); continue }
                do { try writeEnvelopeObject(merged, schemaVersion: peopleSchemaVersion,
                                             to: match.dir.appendingPathComponent("person.json")) }
                catch { report.conflicts.append("person \(id) merge failed: \(error.localizedDescription)"); continue }
            }
            report.peopleMerged += 1
            report.changed = true
        } else {
            // New person — copy the whole folder verbatim (lossless), then stamp provenance.
            let dest = uniqueDestination(peopleRoot.appendingPathComponent(dir.lastPathComponent, isDirectory: true))
            if opts.verbose { print("  person \(id) (\(staged["displayName"] as? String ?? "?")): create -> \(dest.lastPathComponent)") }
            if opts.apply {
                guard insideVault(dest, root: storage) else { report.conflicts.append("person \(id) path escape"); continue }
                do {
                    try fm.createDirectory(at: peopleRoot, withIntermediateDirectories: true)
                    try fm.copyItem(at: dir, to: dest)
                    var stamped = staged
                    var sources = (stamped["importSources"] as? [String]) ?? []
                    if !sources.contains(device) { sources.append(device) }
                    stamped["importSources"] = sources
                    try writeEnvelopeObject(stamped, schemaVersion: peopleSchemaVersion,
                                            to: dest.appendingPathComponent("person.json"))
                    live.append(LivePerson(dir: dest, payload: stamped))   // so later staged dupes merge
                } catch { report.conflicts.append("person \(id) copy failed: \(error.localizedDescription)"); continue }
            }
            report.peopleCreated += 1
            report.changed = true
        }
        ledger.records[key] = hash
    }
}

// MARK: - Action items ingest

func loadActionItemsRaw(_ url: URL) -> (version: Int, items: [[String: Any]]) {
    guard let data = try? Data(contentsOf: url),
          let top = try? JSONSerialization.jsonObject(with: data) else { return (actionItemSchemaVersion, []) }
    if let dict = top as? [String: Any], let arr = dict["data"] as? [[String: Any]] {
        return (dict["schemaVersion"] as? Int ?? actionItemSchemaVersion, arr)
    }
    if let arr = top as? [[String: Any]] { return (actionItemSchemaVersion, arr) }
    return (actionItemSchemaVersion, [])
}

func ingestActionItems(deviceRoot: URL, device: String, storage: URL,
                       ledger: inout Ledger, opts: Options, report: Report) {
    let stagedURL = deviceRoot.appendingPathComponent("action_items.json")
    guard FileManager.default.fileExists(atPath: stagedURL.path) else { return }
    let key = "\(device)/action_items"
    let hash = fileHash(stagedURL)
    if ledger.records[key] == hash { return }

    let liveURL = storage.appendingPathComponent("action_items.json")
    let (_, stagedItems) = loadActionItemsRaw(stagedURL)
    var (_, liveItems) = loadActionItemsRaw(liveURL)
    let liveIDs = Set(liveItems.compactMap { $0["id"] as? String })

    var added = 0
    for original in stagedItems {
        guard let id = original["id"] as? String, !liveIDs.contains(id) else { continue }
        var item = original
        if (item["source"] as? String) == nil { item["source"] = "remote:\(device)" }
        liveItems.append(item)
        added += 1
    }
    if added > 0 {
        if opts.verbose { print("  action items: +\(added)") }
        if opts.apply {
            let env: [String: Any] = ["schemaVersion": actionItemSchemaVersion, "data": liveItems]
            if JSONSerialization.isValidJSONObject(env),
               let data = try? JSONSerialization.data(withJSONObject: env, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: liveURL, options: .atomic)
            }
        }
        report.actionItemsAdded += added
        report.changed = true
    }
    ledger.records[key] = hash
}

// MARK: - Tags ingest

func ingestTags(deviceRoot: URL, device: String, storage: URL,
                ledger: inout Ledger, opts: Options, report: Report) {
    let stagedURL = deviceRoot.appendingPathComponent("tags.json")
    guard let stagedTop = readObject(stagedURL) else { return }
    let key = "\(device)/tags"
    let hash = fileHash(stagedURL)
    if ledger.records[key] == hash { return }

    let liveURL = storage.appendingPathComponent("tags.json")
    let enveloped = (readObject(liveURL)?["data"] as? [String: Any]) != nil
                 || (stagedTop["data"] as? [String: Any]) != nil
    var live = readObject(liveURL).map(objectPayload) ?? ["tags": [], "meetingTags": [:], "seriesTags": [:]]
    let staged = objectPayload(stagedTop)

    // Union tag definitions by id (keep the hub's entry on collision — preserves symbol/color).
    let liveTagIDs = Set(((live["tags"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String })
    var tags = (live["tags"] as? [[String: Any]]) ?? []
    var newTags = 0
    for t in (staged["tags"] as? [[String: Any]]) ?? [] {
        if let tid = t["id"] as? String, !liveTagIDs.contains(tid) { tags.append(t); newTags += 1 }
    }
    live["tags"] = tags

    // Union the per-meeting / per-series assignment lists.
    var assignments = 0
    func mergeAssignments(_ field: String) {
        var liveMap = (live[field] as? [String: [String]]) ?? [:]
        for (mid, ids) in (staged[field] as? [String: [String]]) ?? [:] {
            let before = Set(liveMap[mid] ?? [])
            let merged = unionStrings(liveMap[mid], ids)
            assignments += merged.count - before.count
            liveMap[mid] = merged
        }
        live[field] = liveMap
    }
    mergeAssignments("meetingTags")
    mergeAssignments("seriesTags")

    if newTags > 0 || assignments > 0 {
        if opts.verbose { print("  tags: +\(newTags) tag(s), +\(assignments) assignment(s)") }
        if opts.apply {
            do {
                if enveloped {
                    try writeEnvelopeObject(live, schemaVersion: 1, to: liveURL)
                } else if JSONSerialization.isValidJSONObject(live) {
                    let data = try JSONSerialization.data(withJSONObject: live, options: [.prettyPrinted, .sortedKeys])
                    try data.write(to: liveURL, options: .atomic)
                }
            } catch { report.conflicts.append("tags write failed: \(error.localizedDescription)") }
        }
        report.tagsAdded += newTags
        report.tagAssignmentsAdded += assignments
        report.changed = true
    }
    ledger.records[key] = hash
}

// MARK: - Derived-cache invalidation

/// After importing, drop the rebuildable caches so the app/MCP regenerate them
/// from the now-updated truth (the "rebuild, don't merge" principle), and signal
/// a running app to reload.
func invalidateDerivedCaches(storage: URL) {
    let fm = FileManager.default
    for name in [".meeting-index.json", "_recent.json", "_people-cache.json"] {
        try? fm.removeItem(at: storage.appendingPathComponent(name))
    }
    DarwinNotifier.post(DarwinNotifier.vaultChanged)
}

// MARK: - Device discovery + run

func deviceDirectories(storage: URL, only: String?) -> [URL] {
    let remote = storage.appendingPathComponent("_remote", isDirectory: true)
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(at: remote,
        includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
    let skip: Set<String> = ["_conflicts", "_undo", "processed"]
    return entries.filter { url in
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
        let name = url.lastPathComponent
        if name.hasPrefix(".") || skip.contains(name) { return false }
        if let only, name != only { return false }
        return true
    }
}

func run(_ opts: Options) -> Int32 {
    let storage = resolveStorage(opts)
    guard FileManager.default.fileExists(atPath: storage.path) else {
        FileHandle.standardError.write("error: vault not found at \(storage.path)\n".data(using: .utf8)!)
        return 1
    }
    let devices = deviceDirectories(storage: storage, only: opts.device)
    if devices.isEmpty {
        print("Nothing to ingest: no device folders under \(storage.appendingPathComponent("_remote").path)")
        return 0
    }

    var ledger = Ledger.load(in: storage)
    var liveIDs = liveMeetingIDs(storage: storage)
    let report = Report()

    for deviceDir in devices {
        let device = deviceDir.lastPathComponent
        print("Ingesting device: \(device)")
        ingestMeetings(deviceRoot: deviceDir, device: device, storage: storage,
                       liveIDs: &liveIDs, ledger: &ledger, opts: opts, report: report)
        ingestPeople(deviceRoot: deviceDir, device: device, storage: storage,
                     ledger: &ledger, opts: opts, report: report)
        ingestActionItems(deviceRoot: deviceDir, device: device, storage: storage,
                          ledger: &ledger, opts: opts, report: report)
        ingestTags(deviceRoot: deviceDir, device: device, storage: storage,
                   ledger: &ledger, opts: opts, report: report)
    }

    if opts.apply {
        if report.changed { invalidateDerivedCaches(storage: storage) }
        ledger.save(in: storage)
    }
    report.print(dryRun: !opts.apply)
    return 0
}

// MARK: - Self-test (runnable on the user's Mac: `MeetingScribeSync --self-test`)

func selfTest() -> Int32 {
    var failures = 0
    func check(_ cond: Bool, _ msg: String) {
        if cond { print("  ok: \(msg)") } else { print("  FAIL: \(msg)"); failures += 1 }
    }
    print("MeetingScribeSync self-test")

    // Union semantics
    check(unionStrings(["a", "b"], ["b", "c"]) == ["a", "b", "c"], "unionStrings dedupes")
    let byid = unionByID([["id": "1", "v": "live"]], [["id": "1", "v": "work"], ["id": "2"]])
    check(byid.count == 2 && (byid.first?["v"] as? String) == "live", "unionByID keeps first (live) on id clash")

    // Person merge: additive, fill-empty, never drops live fields
    let live: [String: Any] = ["id": "p1", "displayName": "Jane", "company": "Acme",
                               "emails": ["jane@acme.com"], "memories": [["id": "m1", "text": "a"]],
                               "secret": "keepme", "importSources": ["contacts"]]
    let staged: [String: Any] = ["id": "p1", "displayName": "Jane", "company": "",
                                 "role": "Eng", "emails": ["JANE@acme.com", "jane@personal.com"],
                                 "memories": [["id": "m2", "text": "b"]], "importSources": ["work-macbook"]]
    let merged = mergePersonPayload(live: live, staged: staged, device: "work-macbook")
    check((merged["secret"] as? String) == "keepme", "merge preserves unknown live fields")
    check((merged["company"] as? String) == "Acme", "merge keeps non-empty live scalar")
    check((merged["role"] as? String) == "Eng", "merge fills empty scalar from staged")
    let mEmails = merged["emails"] as? [String] ?? []
    check(mEmails.count == 2 && Set(mEmails.map(normEmail)) == ["jane@acme.com", "jane@personal.com"],
          "merge unions emails case-insensitively (no near-dup)")
    check((merged["memories"] as? [[String: Any]])?.count == 2, "merge unions memories by id")
    check(Set(merged["importSources"] as? [String] ?? []) == ["contacts", "work-macbook"], "merge stamps provenance")

    // Matching
    let livePeople = [LivePerson(dir: URL(fileURLWithPath: "/tmp/x"), payload: live)]
    check(matchLivePerson(["id": "p1", "displayName": "Z"], in: livePeople) != nil, "match by id")
    check(matchLivePerson(["id": "zzz", "displayName": "Z", "emails": ["JANE@acme.com"]], in: livePeople) != nil, "match by email (case-insensitive)")
    check(matchLivePerson(["id": "zzz", "displayName": "jane"], in: livePeople) != nil, "match by normalized name")
    check(matchLivePerson(["id": "zzz", "displayName": "Nobody"], in: livePeople) == nil, "no false match -> new person")

    // Hashing is stable + sensitive
    check(fnv1a(Data("hello".utf8)) == fnv1a(Data("hello".utf8)), "hash stable")
    check(fnv1a(Data("hello".utf8)) != fnv1a(Data("hellp".utf8)), "hash sensitive")

    print(failures == 0 ? "\nAll self-tests passed.\n" : "\n\(failures) self-test(s) FAILED.\n")
    return failures == 0 ? 0 : 1
}

// MARK: - Entry

let options = parseOptions()
if options.help { print(helpText); exit(0) }
if options.selfTest { exit(selfTest()) }
exit(run(options))
