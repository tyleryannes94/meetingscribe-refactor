# Agent 2 — In-app HTTP Push Sync (work MacBook → personal Mac mini hub)

**Approach:** A native Swift sync engine built *into* MeetingScribe. The hub
(Mac mini) already runs an embedded, token-gated HTTP server for phone access
(`Sources/MeetingScribe/Web/`, port 8765, LAN + Tailscale, QR pairing). We extend
that same server with a `/sync/*` ingest API, and add a "push client" mode to the
app running on the work MacBook that periodically packages new/changed vault files
and POSTs them to the hub over the tailnet. Incoming data lands in a quarantined
`_remote/<deviceID>/` namespace so the hub's primary vault is never clobbered.

Everything stays inside one app binary. No extra installs, no cloud, $0.

---

## 1. Overview & architecture

Both machines run the **same** `MeetingScribe.app`. A single new setting,
`syncRole`, decides behavior:

- **Hub** (`.hub`) — Mac mini. Already runs the web server; we just add the
  `/sync/*` routes to the existing `WebAPI`. It accepts pushes and writes them
  into `<vault>/_remote/<deviceID>/…`. It never reaches out to anyone.
- **Push** (`.push`) — work MacBook. Runs a new `VaultPushSyncService` that walks
  its local vault, diffs against the last acknowledged state, and uploads only the
  changed files to the hub. It never serves; it only sends.
- **Off** (`.off`) — default. Neither (a fresh install / phone-only user).

```
            WORK MacBook (.push)                       PERSONAL Mac mini (.hub)
   ┌─────────────────────────────────┐        ┌──────────────────────────────────┐
   │  MeetingScribe.app               │        │  MeetingScribe.app                │
   │                                  │        │                                   │
   │  Local vault (plain files)       │        │  HTTPServer (NWListener :8765)    │
   │   <tag>/<slug>/meeting.json …    │        │     │                             │
   │   people/<slug>/ …               │        │     ▼                             │
   │                                  │        │  WebAPI.handle(request)           │
   │  VaultPushSyncService            │        │   ├─ /api/*   (phone, existing)   │
   │   1. build manifest (sha256)     │        │   └─ /sync/*  (NEW)               │
   │   2. GET /sync/state  ───────────┼──tailnet─►   POST /sync/manifest          │
   │   3. diff → changed paths        │  100.x  │      POST /sync/upload           │
   │   4. POST /sync/manifest ────────┼────────►│      POST /sync/commit           │
   │   5. POST /sync/upload (chunked)─┼────────►│      GET  /sync/state            │
   │   6. POST /sync/commit  ─────────┼────────►│        │                         │
   │   7. persist cursor              │        │        ▼                         │
   │                                  │ Bearer  │  SyncIngest → atomic write into  │
   │  Timer: every 1–3h + on launch   │  token  │  <vault>/_remote/<deviceID>/…    │
   │  + "Sync now" button             │        │  (quarantine; never merged)       │
   └─────────────────────────────────┘        └──────────────────────────────────┘
```

Data flow is strictly one-way: bytes only ever travel work → hub. The hub writes
them into an isolated subtree. The hub's own meetings live outside `_remote/` and
are physically untouched by ingest.

---

## 2. Why this approach

**Pros**

- **Self-contained.** Reuses the existing `HTTPServer`, the `ms_token` auth, the
  Tailscale IP discovery (`NetworkInfo.tailscaleIP()`), and the QR pairing UI.
  No new daemon, no Syncthing/rsync/restic to install, no SSH keys to manage.
- **$0.** Tailscale free tier + the app you already run. No cloud bucket.
- **Content-addressed & idempotent.** We diff by sha256, so a re-push of an
  unchanged file is a no-op. Interrupted runs resume cleanly.
- **App-native UX.** One Settings toggle, the same QR/token pairing the user
  already understands. Sync status surfaces in the app.
- **Schema-aware.** We ship the file's `SchemaEnvelope` bytes verbatim, so the
  hub can later "adopt" remote items through the normal decoders/migrations.

**Cons (vs file-level rsync / Syncthing)**

- We re-implement change detection (manifest + sha256) that rsync gives free.
  Mitigated: the vault is small (JSON + markdown + a few m4a), and we only hash
  files whose size or mtime changed since the last run.
- "App must be open on both ends" — rsync-over-cron has the same constraint
  unless you add a launchd unit; see §5, where we add one anyway.
- No conflict resolution / two-way merge. That's intentional: the requirement is
  strictly one-way backup, and one-way removes the hardest part of sync.

vs. file-level rsync: rsync would be fewer lines but means a second tool, a
launchd plist hand-edited per machine, SSH/Tailscale-SSH auth, and it would write
straight into the live tree (clobber risk) unless pointed at a staging dir anyway.
The in-app path keeps auth, addressing, and quarantine in code we control.

---

## 3. Hub-side ingest API

**File to modify:** `Sources/MeetingScribe/Web/WebAPI.swift` (add a `/sync`
branch in `handle(_:)`), plus a new `Sources/MeetingScribe/Sync/SyncIngest.swift`
for the disk logic. Auth reuses the existing `isAuthorized(_:)` (Bearer token).

### Routing hook

In `WebAPI.handle(_:)`, before the `guard comps.first == "api"`:

```swift
if comps.first == "sync" {
    guard AppSettings.shared.syncRole == .hub else {
        return .error(403, "This Mac is not configured as a sync hub.")
    }
    guard isAuthorized(request) else {
        return .error(401, "Unauthorized — pair with the hub's access token.")
    }
    return await sync.handle(request, rest: Array(comps.dropFirst()))
}
```

`sync` is a lazily-created `SyncIngest` held by `WebAPI` (same `@MainActor`).
Reuse the *existing* `webServerToken` — pairing the work Mac is identical to
pairing a phone (scan the QR / paste the `?t=` token), so there's nothing new for
the user to set up.

### Routes

All requests carry `Authorization: Bearer <token>` and an
`X-MS-Device: <deviceID>` header (a stable UUID generated once on the work Mac).

#### `GET /sync/state`
Returns the hub's current knowledge of this device's tree, so the client can diff
locally and skip already-present files. Response:

```json
{
  "deviceID": "B6F3…",
  "schemaVersion": 1,
  "files": {
    "Work/acme-standup-2026-05-30/meeting.json": {
      "sha256": "9f2c…", "size": 814, "mtime": 1717001234.0
    },
    "Work/acme-standup-2026-05-30/audio/rec.m4a": {
      "sha256": "0aa1…", "size": 5120344, "mtime": 1717001240.0
    }
  },
  "lastCommit": "2026-06-02T09:15:00Z"
}
```

The hub builds this from a per-device **ingest ledger**
(`_remote/<deviceID>/.sync-ledger.json`) it maintains on every commit — cheap to
read, avoids re-hashing the whole remote tree on each poll.

#### `POST /sync/manifest`
The client declares the full set of files it intends this run to contain, with
hashes. The hub replies with exactly which `path`s it still needs (i.e. ones whose
sha256 differs from the ledger). This is the dedup gate.

Request:
```json
{
  "deviceID": "B6F3…",
  "sessionID": "2026-06-02T09:20:01Z-7a1c",
  "files": [
    {"path": "Work/acme-standup-2026-05-30/meeting.json",
     "sha256": "9f2c…", "size": 814, "mtime": 1717001234.0},
    {"path": "Work/acme-standup-2026-05-30/audio/rec.m4a",
     "sha256": "0aa1…", "size": 5120344, "mtime": 1717001240.0}
  ]
}
```
Response:
```json
{ "sessionID": "2026-06-02T09:20:01Z-7a1c",
  "need": ["Work/acme-standup-2026-05-30/audio/rec.m4a"],
  "chunkSize": 4194304 }
```
The hub persists the declared manifest to `_remote/<deviceID>/.sessions/<sessionID>.json`
so it can validate uploads and commit atomically.

#### `POST /sync/upload`
Streams one file (or one chunk of a large file) into a staging area. Metadata
travels in **headers**, not JSON, so the body is raw bytes (no base64 bloat):

```
POST /sync/upload
Authorization: Bearer <token>
X-MS-Device: B6F3…
X-MS-Session: 2026-06-02T09:20:01Z-7a1c
X-MS-Path: Work/acme-standup-2026-05-30/audio/rec.m4a   (percent-encoded)
X-MS-Sha256: 0aa1…            (sha256 of the WHOLE file)
X-MS-Chunk-Index: 0
X-MS-Chunk-Count: 2
X-MS-Chunk-Sha256: 4d5e…      (sha256 of THIS chunk, for integrity)
Content-Type: application/octet-stream
Content-Length: 4194304
<raw bytes>
```

The hub appends the chunk to
`_remote/<deviceID>/.staging/<sessionID>/<sanitized-path>.part`. When the last
chunk (`index == count-1`) arrives it verifies the assembled file's sha256 equals
`X-MS-Sha256`; on mismatch it returns `422` and the client re-uploads. On success
the staged file is left in `.staging/` for the commit step. Response:
`{"ok": true, "received": 1, "of": 2}` or `{"ok": true, "complete": true}`.

> **`maxRequestBytes` note:** `HTTPConnection` caps a single request at 16 MB
> (`HTTPServer.swift:165`). Chunked upload at 4 MB/chunk stays well under it, so no
> server change is needed. Files ≤ chunkSize go in one request.

#### `POST /sync/commit`
Finalizes a session: the hub validates that every `need` from the manifest is now
present and hash-correct in staging, then **atomically** moves each staged file
into `_remote/<deviceID>/<path>` and updates the ledger. Response includes the
new ledger digest so the client can advance its cursor.

```json
{ "deviceID": "B6F3…", "sessionID": "2026-06-02T09:20:01Z-7a1c" }
→ { "ok": true, "committed": 2, "ledger": "sha256:c41e…",
    "committedAt": "2026-06-02T09:20:09Z" }
```

### On-disk layout (hub)

```
<vault>/_remote/
  <deviceID>/                       e.g. "worklaptop-B6F3…"
    Work/acme-standup-2026-05-30/meeting.json
    Work/acme-standup-2026-05-30/transcript.md
    Work/acme-standup-2026-05-30/audio/rec.m4a
    people/jane-doe/person.json
    .sync-ledger.json               authoritative {path → {sha256,size,mtime}}
    .sessions/<sessionID>.json      declared manifests (pruned after commit)
    .staging/<sessionID>/…          partials (pruned after commit/expiry)
```

The `deviceID` directory name is `sanitize(deviceLabel) + "-" + deviceID.prefix`,
so two work machines never collide and the folder is human-readable in Finder.

### Atomicity & idempotency

- **Atomic file writes:** stage to `.staging/…`, then
  `FileManager.replaceItemAt(dest, withItemAt: staged)` (atomic rename within the
  same volume), mirroring the existing `data.write(to:options:.atomic)` pattern in
  `MeetingStore.swift:188`.
- **Idempotency key** = `sha256`. `/sync/manifest` only asks for files whose hash
  differs from the ledger, and `/sync/upload` is keyed by `(sessionID, path,
  chunkIndex)` so a re-sent chunk just overwrites the same `.part` slice. A whole
  re-pushed run with no changes yields `need: []` and an immediate no-op commit.
- **Path safety:** `SyncIngest` rejects any path containing `..`, a leading `/`,
  or a `:` after percent-decoding, and refuses to write outside the device's
  `_remote/<deviceID>/` root. (Hardening — a compromised/buggy client must not be
  able to escape quarantine and clobber the hub's real vault.)
- **Deletes are NOT propagated.** A file removed on the work Mac stays in the hub
  backup. This is a backup/second-brain, so retention beats mirroring; it also
  removes any way for the client to cause hub data loss.

---

## 4. The work-client sync engine

**New file:** `Sources/MeetingScribe/Sync/VaultPushSyncService.swift`.

`@MainActor` for state/UI publishing; all disk hashing and `URLSession` work is on
`Task.detached(priority: .utility)`. The vault walk + sha256 of (potentially) a few
hundred MB of audio must never touch the main thread.

```swift
import Foundation
import CryptoKit
import OSLog

/// Pushes new/changed local vault files to a remote MeetingScribe hub over the
/// tailnet. One-way (work → hub). @MainActor for published status; the heavy
/// lifting (hash + upload) runs detached.
@MainActor
final class VaultPushSyncService: ObservableObject {
    static let shared = VaultPushSyncService()

    enum Phase: Equatable { case idle, scanning, uploading(Int, Int), committing, done, failed(String) }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastError: String?

    private let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "VaultPush")
    private var timer: Timer?
    private var inFlight = false

    // MARK: Manifest model
    struct FileEntry: Codable, Hashable {
        let path: String      // vault-relative, forward-slashed
        let sha256: String
        let size: Int
        let mtime: Double
    }

    // MARK: Scheduling entry points (see §5)
    func start() {
        guard AppSettings.shared.syncRole == .push else { return }
        scheduleTimer()
        Task { await self.syncNow(trigger: "launch") }   // run-on-launch
    }
    func stop() { timer?.invalidate(); timer = nil }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(AppSettings.shared.syncIntervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.syncNow(trigger: "timer") }
        }
    }

    // MARK: One sync pass
    func syncNow(trigger: String) async {
        guard AppSettings.shared.syncRole == .push, !inFlight else { return }
        guard let base = AppSettings.shared.syncHubBaseURL else {
            phase = .failed("No hub address configured"); return
        }
        let token = AppSettings.shared.syncHubToken
        let deviceID = AppSettings.shared.syncDeviceID
        let vault = AppSettings.shared.storageDir
        inFlight = true; phase = .scanning; lastError = nil
        defer { inFlight = false }

        do {
            // 1. Build local manifest off the main actor.
            let local = try await Task.detached(priority: .utility) {
                try Self.buildManifest(vaultRoot: vault)
            }.value

            // 2. Ask the hub what it already has, diff locally.
            let client = SyncHTTPClient(baseURL: base, token: token, deviceID: deviceID)
            let state = try await client.getState()                  // GET /sync/state
            let changed = local.filter { entry in
                state.files[entry.path]?.sha256 != entry.sha256      // new or modified
            }
            if changed.isEmpty { phase = .done; lastSync = .now; persistCursor(local); return }

            // 3. Declare manifest; hub returns exactly what it still needs.
            let session = ISO8601DateFormatter().string(from: .now) + "-" + String(UUID().uuidString.prefix(4))
            let need = try await client.postManifest(sessionID: session, files: changed)  // POST /sync/manifest
            let toSend = changed.filter { need.contains($0.path) }

            // 4. Upload each needed file (chunked for big audio).
            for (i, entry) in toSend.enumerated() {
                phase = .uploading(i + 1, toSend.count)
                let fileURL = vault.appendingPathComponent(entry.path)
                try await client.uploadFile(fileURL, entry: entry, sessionID: session)   // POST /sync/upload (chunked)
            }

            // 5. Commit.
            phase = .committing
            try await client.commit(sessionID: session)              // POST /sync/commit

            persistCursor(local)
            phase = .done; lastSync = .now
            AppSettings.shared.syncLastSuccess = lastSync
            log.info("Sync ok (\(trigger, privacy: .public)): \(toSend.count) files")
        } catch {
            phase = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            log.error("Sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Manifest builder (detached — disk + CryptoKit hashing)
    nonisolated static func buildManifest(vaultRoot: URL) throws -> [FileEntry] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: vaultRoot,
                  includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]) else { return [] }
        var out: [FileEntry] = []
        for case let url as URL in walker {
            let rel = url.path.replacingOccurrences(of: vaultRoot.path + "/", with: "")
            if Self.isExcluded(rel) { if url.hasDirectoryPath { walker.skipDescendants() }; continue }
            let v = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard v.isRegularFile == true else { continue }
            let mtime = v.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = v.fileSize ?? 0
            out.append(FileEntry(path: rel, sha256: try sha256OfFile(url),
                                 size: size, mtime: mtime))
        }
        return out
    }

    /// Streamed sha256 so a 500 MB m4a never loads fully into RAM.
    nonisolated static func sha256OfFile(_ url: URL) throws -> String {
        let h = FileHandle(forReadingFrom: url); defer { try? h.close() }
        var hasher = SHA256()
        while case let chunk = try h.read(upToCount: 1 << 20) ?? Data(), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Never ship derived/local-only or already-remote artifacts.
    nonisolated static func isExcluded(_ rel: String) -> Bool {
        let firstComp = rel.split(separator: "/").first.map(String.init) ?? rel
        // _remote → don't echo a hub's quarantine back; _inbox/processed → transient;
        // .meeting-index.json / _people-cache.json → derived caches the hub rebuilds.
        return ["_remote", "_inbox", "logs", "diagnostics", "models"].contains(firstComp)
            || rel.hasSuffix(".meeting-index.json")
            || rel.hasSuffix("_people-cache.json")
            || rel.contains("/.")            // dotfiles inside the tree
    }

    // MARK: Cursor — last successfully-synced manifest (skip re-hash next run)
    private var cursorURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingScribe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync-cursor.json")
    }
    private func persistCursor(_ files: [FileEntry]) {
        if let data = try? JSONEncoder().encode(files) { try? data.write(to: cursorURL, options: .atomic) }
    }
}
```

### Networking + retry/backoff

**New file:** `Sources/MeetingScribe/Sync/SyncHTTPClient.swift` (a `Sendable`
actor, runs off the main actor):

```swift
actor SyncHTTPClient {
    let baseURL: URL; let token: String; let deviceID: String
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 3600          // big audio over cellular-grade links
        c.waitsForConnectivity = true                // ride out a tailnet hiccup
        return URLSession(configuration: c)
    }()

    func getState() async throws -> SyncState {
        try await getJSON("/sync/state", as: SyncState.self)
    }
    func postManifest(sessionID: String, files: [VaultPushSyncService.FileEntry]) async throws -> Set<String> {
        let body = ["deviceID": deviceID, "sessionID": sessionID, "files": files] as [String: Any]
        let resp: ManifestResponse = try await postJSON("/sync/manifest", body: body)
        return Set(resp.need)
    }

    /// Chunked, integrity-checked upload with bounded retry/backoff.
    func uploadFile(_ url: URL, entry: VaultPushSyncService.FileEntry, sessionID: String) async throws {
        let chunkSize = 4 * 1024 * 1024
        let count = max(1, Int((Double(entry.size) / Double(chunkSize)).rounded(.up)))
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }
        for idx in 0..<count {
            let data = try h.read(upToCount: chunkSize) ?? Data()
            var req = makeRequest("/sync/upload", method: "POST", contentType: "application/octet-stream")
            req.setValue(entry.path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? entry.path, forHTTPHeaderField: "X-MS-Path")
            req.setValue(entry.sha256, forHTTPHeaderField: "X-MS-Sha256")
            req.setValue(sessionID, forHTTPHeaderField: "X-MS-Session")
            req.setValue(String(idx), forHTTPHeaderField: "X-MS-Chunk-Index")
            req.setValue(String(count), forHTTPHeaderField: "X-MS-Chunk-Count")
            req.setValue(sha256Hex(data), forHTTPHeaderField: "X-MS-Chunk-Sha256")
            try await sendWithRetry(req, body: data)
        }
    }
    func commit(sessionID: String) async throws {
        _ = try await postJSON("/sync/commit",
            body: ["deviceID": deviceID, "sessionID": sessionID]) as CommitResponse
    }

    private func sendWithRetry(_ req: URLRequest, body: Data, attempts: Int = 4) async throws {
        var delay: UInt64 = 500_000_000   // 0.5s
        for attempt in 1...attempts {
            do {
                let (_, resp) = try await session.upload(for: req, from: body)
                guard let http = resp as? HTTPURLResponse else { throw SyncError.badResponse }
                if (200..<300).contains(http.statusCode) { return }
                if http.statusCode == 401 { throw SyncError.unauthorized }   // token rotated → don't retry
                if attempt == attempts { throw SyncError.status(http.statusCode) }
            } catch {
                if attempt == attempts { throw error }
            }
            try await Task.sleep(nanoseconds: delay); delay *= 2             // exp backoff
        }
    }
    // makeRequest / getJSON / postJSON set Authorization + X-MS-Device headers.
}
```

**Actor boundaries:** `VaultPushSyncService` is `@MainActor` only for `@Published`
status. `buildManifest`/`sha256OfFile` are `nonisolated static` and called via
`Task.detached`. `SyncHTTPClient` is its own `actor`, so all socket I/O is off the
main actor. The only main-actor work per pass is reading a handful of
`AppSettings` values and updating `phase`.

---

## 5. Scheduling

Three triggers, all in `VaultPushSyncService`:

1. **On launch** — `start()` fires one `syncNow(trigger:"launch")` (after stores
   are ready), wired in `MeetingScribeApp.swift` right after the existing
   `WebServerController.shared.startIfEnabled()` (~line 180).
2. **Repeating timer** — `Timer.scheduledTimer` every `syncIntervalMinutes`
   (default 120; user picks 60 / 120 / 180 / 360). Re-armed when the interval
   setting changes.
3. **Manual "Sync now"** — a Settings button calls `syncNow(trigger:"manual")`.

### The "app must be open" limitation

The timer only ticks while MeetingScribe runs. MeetingScribe is a menu-bar app
that normally stays running on the work Mac, so daily/hourly coverage is usually
fine. But if the user quits it, sync stops.

**Recommended fix: a launchd login-item that relaunches the app.** The repo
already has precedent — `MeetingScribeApp.swift:164` calls
`registerScribeCoreLoginItem()`. We add an analogous **`KeepAlive`** LaunchAgent
on the work Mac only (when `syncRole == .push`):

`~/Library/LaunchAgents/com.tyleryannes.MeetingScribe.keepalive.plist`
```xml
<plist version="1.0"><dict>
  <key>Label</key><string>com.tyleryannes.MeetingScribe.keepalive</string>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/open</string><string>-g</string>
         <string>-a</string><string>MeetingScribe</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>3600</integer>   <!-- relaunch hourly if quit -->
</dict></plist>
```

`open -g` launches it in the background (no window steal); if it's already
running, `open` is a no-op. This is strictly simpler and more robust than trying
to run the whole sync engine as a standalone `launchd`-managed CLI, and it reuses
the app's existing auth/config. Register it from a new
`registerPushKeepAliveLoginItem()` called when the user switches to Push mode;
unregister when they leave Push mode. (A pure-CLI headless sync agent is the
alternative — more work, duplicates manifest/upload logic, and loses the in-app
status UI; not recommended.)

> macOS App Nap / timer coalescing can delay a 2-hour timer when the app is
> backgrounded; that's acceptable for a backup. The launchd `StartInterval` is the
> belt-and-suspenders that guarantees the app is at least *alive* hourly so the
> next timer tick (and the run-on-launch) happen.

---

## 6. Settings UI

**File to modify:** `Sources/MeetingScribe/UI/SettingsView.swift` — add a new
`SyncSection` `View` (mirror `PhoneAccessSection`, §1014) and reference it from the
form, e.g. right after `PhoneAccessSection()` at line 104.

New `AppSettings` keys (added to `Sources/MeetingScribe/Models/Settings.swift`,
following the existing `webServer*` pattern):

| Key | Type | Default | Purpose |
|---|---|---|---|
| `syncRole` | `String` (`off`/`hub`/`push`) | `off` | This Mac's mode |
| `syncHubBaseURL` | `String?` (`http://100.x.y.z:8765`) | nil | Hub address (push mode) |
| `syncHubToken` | `String` (Keychain) | "" | Hub's access token (push mode) |
| `syncDeviceID` | `String` | generated UUID | Stable per-device id |
| `syncDeviceLabel` | `String` | host name | Human label for the `_remote/` folder |
| `syncIntervalMinutes` | `Int` | 120 | Push cadence |
| `syncLastSuccess` | `Date?` | nil | Status display |

Store `syncHubToken` in the **Keychain** (`KeychainStore`, like `notionAPIKey`),
not UserDefaults — it's another device's secret.

UI sketch:

```swift
struct SyncSection: View {
    @ObservedObject private var sync = VaultPushSyncService.shared
    @State private var role = AppSettings.shared.syncRole       // .off/.hub/.push
    @State private var hubURL = AppSettings.shared.syncHubBaseURL?.absoluteString ?? ""
    @State private var token = AppSettings.shared.syncHubToken
    @State private var interval = AppSettings.shared.syncIntervalMinutes

    var body: some View {
        Section("Backup sync (second brain)") {
            Picker("This Mac is", selection: $role) {
                Text("Not syncing").tag(SyncRole.off)
                Text("The Hub (receive backups)").tag(SyncRole.hub)
                Text("Pushing to a Hub").tag(SyncRole.push)
            }
            .onChange(of: role) { _, r in AppSettings.shared.syncRole = r; applyRole(r) }

            if role == .hub {
                Text("This Mac accepts pushes from your other Macs and stores them under _remote/. Turn on Phone access above so the server is running, then share its QR/token with the work Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                // reuses WebServerController.shared.endpoints() + qrImage() — same QR as phone pairing
            }

            if role == .push {
                TextField("Hub address (e.g. http://100.x.y.z:8765)", text: $hubURL)
                SecureField("Hub access token", text: $token)
                Button("Paste from pairing link…") { parsePairingLink() }  // accepts the http://…/?t=… link
                Picker("Sync every", selection: $interval) {
                    Text("1 hour").tag(60); Text("2 hours").tag(120)
                    Text("3 hours").tag(180); Text("6 hours").tag(360)
                }.onChange(of: interval) { _, v in AppSettings.shared.syncIntervalMinutes = v; sync.start() }

                Button("Sync now") { Task { await sync.syncNow(trigger: "manual") } }
                statusLabel(sync.phase)
                if let last = sync.lastSync { Text("Last sync: \(last.formatted())").font(.caption2) }
            }
        }.onAppear { role = AppSettings.shared.syncRole }
    }
}
```

**Pairing reuse:** the "Paste from pairing link" button accepts the exact
`http://100.x.y.z:8765/?t=<token>` string the hub already produces in
`WebServerController.endpoints()`; we split it into `syncHubBaseURL` (scheme+host+
port) and `syncHubToken` (the `t` query param). So pairing the work Mac is the
same scan/paste flow as pairing a phone — zero new concepts for the user.

---

## 7. One-way + non-clobber guarantees

1. **Direction is enforced on both ends.** The push client only ever issues
   `POST`/`GET` to the hub; it never opens a listener. The hub's `/sync/*` is the
   only ingest path and it only *writes* into `_remote/`. There is no code path by
   which hub data leaves the hub or by which the hub overwrites its own primary
   tree from a push.
2. **Quarantine namespace.** Everything lands under `_remote/<deviceID>/`. The
   hub's real meetings live under `<tag>/<slug>/` and `people/` *outside* that
   subtree. `MeetingStore.listPastMeetings` and friends already ignore unknown
   top-level dirs; `_remote` is also added to the client's `isExcluded` set and to
   the hub's reserved-folder list so it's never treated as a meeting grouping nor
   echoed back out.
3. **No deletes propagated** (§3) — the backup only grows; a client can't trigger
   hub data loss.
4. **Path-escape guard** in `SyncIngest` (rejects `..`, absolute, volume escapes).
5. **Optional explicit "Adopt into second brain".** A later, *manual* hub-side
   action can promote a `_remote/<deviceID>/<tag>/<slug>/` meeting into the primary
   tree by decoding its `SchemaEnvelope` through the normal `MeetingStore`
   importer (dedup by meeting `id`, conflict → keep-both). This is deliberately
   user-initiated and out of the automatic path, so automatic sync can *never*
   mutate the curated vault. (Scope this as a v2 follow-up; v1 ships
   backup-into-quarantine only, which already satisfies the requirement.)

---

## 8. Step-by-step build instructions for Claude Code

Ordered; each step compiles independently where possible.

1. **Add settings keys.** Edit `Sources/MeetingScribe/Models/Settings.swift`:
   - Add a top-level `enum SyncRole: String { case off, hub, push }`.
   - Add `Keys` entries + computed vars: `syncRole`, `syncHubBaseURL` (stored as
     String, exposed as `URL?`), `syncHubToken` (via `KeychainStore` — add a
     `KeychainStore.Account.syncHubToken` case), `syncDeviceID` (generate+persist a
     UUID on first read), `syncDeviceLabel` (default `NetworkInfo.localHostName`),
     `syncIntervalMinutes` (default 120), `syncLastSuccess` (`Date?`).

2. **Create `Sources/MeetingScribe/Sync/SyncIngest.swift`** (`@MainActor` final
   class). Implement `handle(_ request: HTTPRequest, rest: [String]) async ->
   HTTPResponse` dispatching `state` / `manifest` / `upload` / `commit`. Implement
   the per-device ledger (`.sync-ledger.json`), session manifests, chunk staging,
   whole-file sha256 verification, atomic `replaceItemAt` commit, and the
   path-escape guard. Writes go under
   `AppSettings.shared.storageDir/_remote/<sanitizedDeviceDir>/`.

3. **Wire the route.** Edit `Sources/MeetingScribe/Web/WebAPI.swift`:
   - Add `private lazy var sync = SyncIngest(meetingStore: meetingStore)` (or pass
     `manager`).
   - In `handle(_:)`, add the `if comps.first == "sync" { … }` branch shown in §3
     (role-gated to `.hub`, auth via existing `isAuthorized`).

4. **Create `Sources/MeetingScribe/Sync/SyncHTTPClient.swift`** (the `actor` from
   §4): `getState`, `postManifest`, `uploadFile` (chunked), `commit`, plus
   `sendWithRetry` and the `SyncState`/`ManifestResponse`/`CommitResponse`
   `Codable` types and a `SyncError` enum.

5. **Create `Sources/MeetingScribe/Sync/VaultPushSyncService.swift`** (§4):
   manifest builder (detached, streamed sha256), `syncNow`, the cursor file, the
   `Timer`, and `start()/stop()`.

6. **Wire launch + login item.** Edit `Sources/MeetingScribe/MeetingScribeApp.swift`
   after line 180:
   ```swift
   switch AppSettings.shared.syncRole {
   case .push: VaultPushSyncService.shared.start()
   case .hub, .off: break   // hub ingest rides on the existing web server
   }
   ```
   Add `registerPushKeepAliveLoginItem()` (model it on
   `registerScribeCoreLoginItem`) that writes/loads the LaunchAgent plist from §5
   when role is `.push`, and unloads it otherwise.

7. **Settings UI.** Edit `Sources/MeetingScribe/UI/SettingsView.swift`: add
   `struct SyncSection: View` (§6) and reference `SyncSection()` in the form after
   `PhoneAccessSection()` (line 104).

8. **Build.** `swift build -c release` (then `make app` for a bundle). Warnings
   ok; errors block per CLAUDE.md. Note: `CryptoKit` is part of the SDK — no
   `Package.swift` change needed.

9. **Verify with curl over the tailnet** (hub running, `syncRole=.hub`, token `T`):
   ```bash
   HUB=http://100.x.y.z:8765 ; TOK=<token>
   # state (empty device → empty files map)
   curl -s -H "Authorization: Bearer $TOK" -H "X-MS-Device: testdev" "$HUB/sync/state" | jq .
   # declare a one-file manifest
   curl -s -H "Authorization: Bearer $TOK" -H "X-MS-Device: testdev" \
        -d '{"deviceID":"testdev","sessionID":"s1","files":[{"path":"Work/x/meeting.json","sha256":"<sha>","size":3,"mtime":0}]}' \
        "$HUB/sync/manifest" | jq .            # → {"need":["Work/x/meeting.json"],...}
   # upload the bytes
   printf '{}\n' > /tmp/m.json
   curl -s -X POST -H "Authorization: Bearer $TOK" -H "X-MS-Device: testdev" \
        -H "X-MS-Session: s1" -H "X-MS-Path: Work%2Fx%2Fmeeting.json" \
        -H "X-MS-Sha256: <sha>" -H "X-MS-Chunk-Index: 0" -H "X-MS-Chunk-Count: 1" \
        --data-binary @/tmp/m.json "$HUB/sync/upload" | jq .
   # commit, then confirm quarantine on the hub
   curl -s -H "Authorization: Bearer $TOK" -H "X-MS-Device: testdev" \
        -d '{"deviceID":"testdev","sessionID":"s1"}' "$HUB/sync/commit" | jq .
   ls "$HOME/Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault/_remote/"
   ```
   A second identical run should return `need: []` (idempotency proven).

---

## 9. Testing / verification, failure modes, security

### Tests
- **Unit:** `buildManifest` excludes `_remote`/`_inbox`/derived caches; streamed
  `sha256OfFile` matches `shasum -a 256`; `SyncIngest` path-escape guard rejects
  `../`, absolute, and `:`-bearing paths; `commit` rejects a session whose staged
  file hash ≠ declared hash.
- **Integration (loopback):** point a push client at `http://127.0.0.1:8765` with
  the same binary in hub mode; assert files appear under `_remote/<dev>/` with
  matching hashes and that the hub's primary tree is byte-identical before/after.
- **Idempotency:** two consecutive `syncNow` runs → second produces `need:[]`,
  zero uploads.
- **Resume:** kill the client mid-upload of a large m4a; next run re-declares,
  re-uploads only the missing file, commits.

### Failure modes & handling
- **Hub offline / tailnet down:** `URLSession` with `waitsForConnectivity` +
  bounded retry; on final failure `phase = .failed`, surfaced in Settings; next
  timer tick retries. No partial commit (commit is all-or-nothing).
- **Chunk corruption:** per-chunk `X-MS-Chunk-Sha256` + whole-file `X-MS-Sha256`
  verified at commit → `422`, client re-uploads that file.
- **Disk full on hub:** atomic `replaceItemAt` fails → commit returns `507`/`500`,
  staging left intact for retry; primary tree untouched.
- **Clock skew:** `mtime` is only a *hint* to decide whether to re-hash; the
  sha256 is authoritative, so skew can't cause a false "unchanged".
- **Large vault first run:** initial full hash of all audio is the expensive case
  — runs detached at `.utility`; subsequent runs use the cursor + size/mtime
  prefilter to avoid re-hashing unchanged files.

### Security
- **Auth:** reuses the existing constant-time `webServerToken` Bearer check
  (`WebAPI.constantTimeEqual`). No new auth surface.
- **Token rotation:** hub's "Regenerate access token"
  (`WebServerController.regenerateToken`) already invalidates the old token; the
  push client then gets `401` and stops (no retry on 401), prompting the user to
  re-pair. Document this in the Settings caption.
- **TLS vs plain HTTP over tailnet:** Tailscale already provides WireGuard
  end-to-end encryption between the two devices, so plain HTTP over `100.x` is
  acceptable for a personal setup — and it keeps the existing server unchanged
  (no cert provisioning). The token still must not travel over a *non*-tailnet
  hop, so: (a) keep the server bound as-is (LAN + tailnet), and (b) optionally
  add a hub-side guard that `/sync/*` is only honored when the request arrives on
  a `100.64/10` (Tailscale) source address — refuse sync over plain LAN to
  prevent token capture on an untrusted office network. (LAN phone access can stay
  permissive; sync carries the whole vault, so it deserves the stricter check.)
- **Replay protection:** the token is a long-lived bearer secret, so a captured
  request *could* be replayed — but every `/sync/*` write is content-addressed and
  idempotent (re-POSTing the same bytes changes nothing), and only writes into
  quarantine, so replay has no harmful effect. If stronger guarantees are wanted
  later, add an `X-MS-Timestamp` + HMAC-over-body header with a ±5-min window and
  a small seen-nonce cache on the hub.
- **Quarantine + no-delete** (§7) mean the worst a fully-compromised client can do
  is fill `_remote/` with junk — never corrupt or delete the curated second brain.

---

## Files touched (summary)

**Modify**
- `Sources/MeetingScribe/Models/Settings.swift` — new sync keys + `SyncRole`.
- `Sources/MeetingScribe/Web/WebAPI.swift` — `/sync` route dispatch.
- `Sources/MeetingScribe/MeetingScribeApp.swift` — launch wiring + keep-alive login item.
- `Sources/MeetingScribe/UI/SettingsView.swift` — `SyncSection`.
- `Sources/MeetingScribe/KeychainStore.swift` — add `syncHubToken` account case.

**Create**
- `Sources/MeetingScribe/Sync/SyncIngest.swift` — hub-side ingest (ledger, staging, atomic commit, path guard).
- `Sources/MeetingScribe/Sync/SyncHTTPClient.swift` — client networking actor (chunked upload, retry/backoff).
- `Sources/MeetingScribe/Sync/VaultPushSyncService.swift` — manifest/diff/schedule/cursor.

**Unchanged but relied on:** `Web/HTTPServer.swift` (16 MB cap accommodates 4 MB
chunks), `Web/NetworkInfo.swift` (`tailscaleIP()`), `Web/WebServerController.swift`
(token + QR + endpoints reused for pairing), `VaultKit/SchemaEnvelope.swift` (bytes
shipped verbatim; decoded only on optional adopt).
