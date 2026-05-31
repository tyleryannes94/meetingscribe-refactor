import Foundation

final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let storageDir = "storageDir"
        static let userName = "userName"
        static let whisperBinary = "whisperBinary"
        static let whisperModel = "whisperModel"
        static let ollamaURL = "ollamaURL"
        static let ollamaModel = "ollamaModel"
        static let autoRecord = "autoRecord"
        static let captureMic = "captureMic"
        static let captureSystem = "captureSystem"
        static let filterToConferenceLinks = "filterToConferenceLinks"
        static let notifyAtMeetingStart = "notifyAtMeetingStart"
        static let detectZoomImpromptu = "detectZoomImpromptu"
        static let dictationHotkeyKeyCode = "dictationHotkeyKeyCode"
        static let dictationHotkeyModifiers = "dictationHotkeyModifiers"
        static let dictationAutoPaste = "dictationAutoPaste"
        static let dictationUsePolished = "dictationUsePolished"
        static let dictationSwapHotkeyKeyCode = "dictationSwapHotkeyKeyCode"
        static let dictationSwapHotkeyModifiers = "dictationSwapHotkeyModifiers"
        static let enabledCalendarIDs = "enabledCalendarIDs"
        /// Storage key — kept as "coworkFolders" so existing users don't
        /// lose their saved folder list. Surfaced in code as `chatFolders`.
        static let chatFolders = "coworkFolders"
        static let notionAPIKey = "notionAPIKey"
        static let notionActionItemsDatabaseID = "notionActionItemsDatabaseID"
        static let linearAPIKey = "linearAPIKey"
        static let lastTaskSync = "lastTaskSync"
        static let googleClientID = "googleClientID"
        static let googleClientSecret = "googleClientSecret"
        static let googleRefreshToken = "googleRefreshToken"
        static let googleDriveFolderName = "googleDriveFolderName"
        static let googleDriveFolderID = "googleDriveFolderID"
        /// Whether whisper-cli should use the Metal/GPU backend. Default
        /// true (faster). Disable as a fallback if the Metal stack misfires
        /// on your hardware (e.g. older Apple Silicon + new ggml).
        static let whisperUseGPU = "whisperUseGPU"
        /// Whether to pass --flash-attn to whisper-cli. Default FALSE on
        /// macOS because flash-attn produces empty output on M2/M3 with
        /// the current homebrew ggml/whisper.cpp build. Re-enable if a
        /// future whisper-cpp release fixes this.
        static let whisperFlashAttention = "whisperFlashAttention"
        static let whisperDiarizationEnabled = "whisperDiarizationEnabled"
        static let autoExtractPeople = "autoExtractPeople"
        /// One-time flag: bump anyone still on the old llama3.1:8b default
        /// to qwen2.5:7b, which actually emits proper `tool_calls` and
        /// doesn't hallucinate spurious safety refusals on benign messages.
        static let migratedToQwen2_5 = "migratedToQwen2_5"
        /// BCP-47 language code passed to whisper-cli via --language.
        /// "auto" = let whisper detect; "en", "es", "fr", etc. for forced lang.
        static let whisperLanguage = "whisperLanguage"
        /// User-editable list of additional names/nicknames that mean "me".
        static let userNameAliases = "userNameAliases"
        /// Off-by-default kill-switch for the ScribeCore daemon recording path.
        /// The daemon path does not finalize a meeting (no merge/transcribe/
        /// summary) and records into an orphan folder → silent total data loss.
        /// Gated OFF until that path is finished. See E3-1.
        static let useScribeCoreDaemon = "useScribeCoreDaemon"
    }

    /// The recommended local model. Qwen 2.5 7B is the strongest small
    /// open-weight tool-caller on Ollama — it populates `tool_calls`
    /// properly (llama3.1:8b leaks the JSON as plain content), runs fast
    /// on Apple Silicon, and is far less prone to overfiring refusals on
    /// benign summarization tasks.
    static let recommendedOllamaModel = "qwen2.5:7b"
    /// The old default. Kept here so the one-time migration knows what
    /// to upgrade from without misclassifying a user's intentional pick.
    static let legacyOllamaModelDefault = "llama3.1:8b"

    /// Default storage location when nothing valid is configured.
    /// Defaults to iCloud Drive so the vault syncs across devices.
    /// Falls back to ~/Documents/MeetingNotes if iCloud isn't available.
    static var defaultStorageURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let iCloud = home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs/MeetingScribeVault",
            isDirectory: true
        )
        return iCloud
    }

    var defaultStorageDir: URL { Self.defaultStorageURL }

    var storageDir: URL {
        get {
            if let raw = defaults.string(forKey: Keys.storageDir) {
                let expanded = (raw.trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
                    .expandingTildeInPath
                // Reject empty / whitespace / filesystem root — those resolve to
                // unwritable paths (a stale "/  " here once broke recording).
                if !expanded.isEmpty, expanded != "/" {
                    return URL(fileURLWithPath: expanded)
                }
            }
            return defaultStorageDir
        }
        set {
            let p = newValue.path.trimmingCharacters(in: .whitespacesAndNewlines)
            // Never persist an empty or root path.
            guard !p.isEmpty, p != "/" else {
                defaults.removeObject(forKey: Keys.storageDir)
                return
            }
            defaults.set(p, forKey: Keys.storageDir)
        }
    }

    /// The user's own name, used to attribute "Me" action items in AI prompts
    /// instead of a hard-coded name. Defaults to "Tyler" to preserve existing
    /// behavior; surfaced in Settings so anyone else's install reads correctly.
    var userName: String {
        get {
            let v = (defaults.string(forKey: Keys.userName) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? "Tyler" : v
        }
        set { defaults.set(newValue, forKey: Keys.userName) }
    }

    /// Additional names/nicknames that should be treated as referring to the
    /// user (e.g. "Ty", a first name, "the eng lead"). User-editable in
    /// Settings. Combined with `userName` by `myNameAliases`. (U1-2)
    var userNameAliases: [String] {
        get { defaults.stringArray(forKey: Keys.userNameAliases) ?? [] }
        set { defaults.set(newValue, forKey: Keys.userNameAliases) }
    }

    /// All lowercased tokens that mean "the user": generic first-person words,
    /// the configured `userName` (full form + first token), and any
    /// user-defined `userNameAliases`. The single source of truth for the
    /// "only my action items" ownership filter and for dropping self-references
    /// during people/attendee extraction. Replaces the hardcoded "tyler" sets
    /// that silently broke those features for anyone not named Tyler. (U1-2)
    var myNameAliases: Set<String> {
        var set: Set<String> = ["me", "i", "myself", "my"]
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !name.isEmpty {
            set.insert(name)
            if let first = name.split(separator: " ").first { set.insert(String(first)) }
        }
        for alias in userNameAliases {
            let t = alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !t.isEmpty { set.insert(t) }
        }
        return set
    }

    /// `myNameAliases` minus the generic first-person pronouns — i.e. only the
    /// tokens that look like an actual name. Used where matching "me"/"my"/"i"
    /// as a substring would be too eager (e.g. scanning free-text for the
    /// user's name). (U1-2)
    var myNameTokens: Set<String> {
        myNameAliases.subtracting(["me", "i", "myself", "my"])
    }

    var whisperBinary: String {
        get { defaults.string(forKey: Keys.whisperBinary) ?? "/opt/homebrew/bin/whisper-cli" }
        set { defaults.set(newValue, forKey: Keys.whisperBinary) }
    }

    var whisperModel: String {
        get {
            if let s = defaults.string(forKey: Keys.whisperModel) { return s }
            return storageDir.appendingPathComponent("models/ggml-base.en.bin").path
        }
        set { defaults.set(newValue, forKey: Keys.whisperModel) }
    }

    var ollamaURL: URL {
        get {
            if let s = defaults.string(forKey: Keys.ollamaURL), let u = URL(string: s) { return u }
            return URL(string: "http://127.0.0.1:11434")!
        }
        set { defaults.set(newValue.absoluteString, forKey: Keys.ollamaURL) }
    }

    var ollamaModel: String {
        get { defaults.string(forKey: Keys.ollamaModel) ?? Self.recommendedOllamaModel }
        set { defaults.set(newValue, forKey: Keys.ollamaModel) }
    }

    /// One-time migration: if the stored model is still the old default
    /// (`llama3.1:8b`, which doesn't tool-call reliably and randomly
    /// refuses benign prompts), bump it to the new recommended model.
    /// Users who *intentionally* picked a different model are untouched.
    /// Idempotent — controlled by the `migratedToQwen2_5` flag.
    func migrateOllamaModelIfNeeded() {
        guard !defaults.bool(forKey: Keys.migratedToQwen2_5) else { return }
        let current = defaults.string(forKey: Keys.ollamaModel)
        if current == nil || current == Self.legacyOllamaModelDefault {
            defaults.set(Self.recommendedOllamaModel, forKey: Keys.ollamaModel)
        }
        defaults.set(true, forKey: Keys.migratedToQwen2_5)
    }

    /// BCP-47 language hint for whisper-cli (--language flag).
    /// "auto" lets whisper detect; "en", "es", "fr", etc. force a language.
    /// Default "auto" — detection is fast and avoids broken output when the
    /// user switches languages.
    var whisperLanguage: String {
        get { defaults.string(forKey: Keys.whisperLanguage) ?? "auto" }
        set { defaults.set(newValue, forKey: Keys.whisperLanguage) }
    }

    var autoRecord: Bool {
        get { defaults.object(forKey: Keys.autoRecord) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.autoRecord) }
    }

    /// Whether to route recording through the embedded ScribeCore daemon.
    /// Default FALSE — the daemon path captures into an orphan
    /// `meetings/scribecore-<date>/` folder, never wires live transcription,
    /// and never calls `finalize()`, so a meeting recorded through it is
    /// silently and totally lost. Keep OFF until the daemon path records into
    /// the UI-chosen meeting directory and drives the same finalize entry
    /// point. See E3-1.
    var useScribeCoreDaemon: Bool {
        get { defaults.object(forKey: Keys.useScribeCoreDaemon) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.useScribeCoreDaemon) }
    }

    var captureMic: Bool {
        get { defaults.object(forKey: Keys.captureMic) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.captureMic) }
    }

    var captureSystem: Bool {
        get { defaults.object(forKey: Keys.captureSystem) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.captureSystem) }
    }

    /// Hide calendar events that don't have a Zoom/Meet/Teams URL — most of
    /// those are personal time blocks.
    var filterToConferenceLinks: Bool {
        get { defaults.object(forKey: Keys.filterToConferenceLinks) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.filterToConferenceLinks) }
    }

    var notifyAtMeetingStart: Bool {
        get { defaults.object(forKey: Keys.notifyAtMeetingStart) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.notifyAtMeetingStart) }
    }

    var detectZoomImpromptu: Bool {
        get { defaults.object(forKey: Keys.detectZoomImpromptu) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.detectZoomImpromptu) }
    }

    /// Carbon virtual keycode for the dictation hotkey. Default: F5 (96).
    var dictationHotkeyKeyCode: UInt32 {
        get {
            let v = defaults.integer(forKey: Keys.dictationHotkeyKeyCode)
            return v == 0 ? 96 : UInt32(v)
        }
        set { defaults.set(Int(newValue), forKey: Keys.dictationHotkeyKeyCode) }
    }

    /// Carbon modifier mask. 0 = no modifiers (just press F5). Use cmdKey, shiftKey, optionKey, controlKey.
    var dictationHotkeyModifiers: UInt32 {
        get {
            let v = defaults.object(forKey: Keys.dictationHotkeyModifiers) as? Int
            return UInt32(v ?? 0)
        }
        set { defaults.set(Int(newValue), forKey: Keys.dictationHotkeyModifiers) }
    }

    /// If true, after transcribing a hotkey-triggered dictation, paste the
    /// text at the cursor in the active app.
    var dictationAutoPaste: Bool {
        get { defaults.object(forKey: Keys.dictationAutoPaste) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.dictationAutoPaste) }
    }

    /// If true, dictation pastes the POLISHED (cleaned-up) transcript instead
    /// of the raw whisper output. The swap hotkey toggles whichever version is
    /// currently inserted to the other one. Default false (paste raw, which is
    /// instant — polished requires an Ollama round-trip).
    var dictationUsePolished: Bool {
        get { defaults.object(forKey: Keys.dictationUsePolished) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.dictationUsePolished) }
    }

    /// Carbon virtual keycode for the "swap dictation version" hotkey.
    /// Default: F6 (97). Replaces the last-inserted dictation with the other
    /// version (raw ↔ polished).
    var dictationSwapHotkeyKeyCode: UInt32 {
        get {
            let v = defaults.integer(forKey: Keys.dictationSwapHotkeyKeyCode)
            return v == 0 ? 97 : UInt32(v)
        }
        set { defaults.set(Int(newValue), forKey: Keys.dictationSwapHotkeyKeyCode) }
    }

    /// Carbon modifier mask for the swap hotkey. 0 = no modifiers.
    var dictationSwapHotkeyModifiers: UInt32 {
        get { UInt32(defaults.object(forKey: Keys.dictationSwapHotkeyModifiers) as? Int ?? 0) }
        set { defaults.set(Int(newValue), forKey: Keys.dictationSwapHotkeyModifiers) }
    }

    /// EventKit calendar identifiers the user has opted in to. Empty set =
    /// "all available calendars" (the default for first-run users so they
    /// see their events immediately).
    var enabledCalendarIDs: Set<String> {
        get {
            let arr = defaults.array(forKey: Keys.enabledCalendarIDs) as? [String] ?? []
            return Set(arr)
        }
        set { defaults.set(Array(newValue), forKey: Keys.enabledCalendarIDs) }
    }

    /// Folder paths the local Chat AI is allowed to read and edit. Empty
    /// by default — the user explicitly opts into each folder via the
    /// Folders sheet in the Chat sidebar. Stored as absolute paths.
    var chatFolders: [String] {
        get { defaults.stringArray(forKey: Keys.chatFolders) ?? [] }
        set { defaults.set(newValue, forKey: Keys.chatFolders) }
    }

    /// Notion Internal Integration Secret. Used both by the bundled
    /// NotionMCP server (passed through the Claude Desktop config) and
    /// by in-app features (push action items to a Notion database).
    ///
    /// Storage: macOS Keychain (`KeychainStore.Account.notionAPIKey`).
    /// First read transparently migrates any legacy UserDefaults value.
    var notionAPIKey: String? {
        get { KeychainStore.read(.notionAPIKey) }
        set { KeychainStore.write(.notionAPIKey, newValue) }
    }

    /// Default true. When false, whisper-cli is invoked with --no-gpu —
    /// useful as a fallback if the Metal backend misbehaves on your
    /// hardware (e.g. older Apple Silicon + new ggml releases).
    /// Default TRUE — Metal is faster. Even on pre-M5/A19 Apple Silicon
    /// (where Metal runs in a "tensor API disabled" compatibility mode) the
    /// GPU path produces correct output as long as we don't pass the broken
    /// `--no-context` flag. If a GPU pass ever does come back empty, the
    /// transcribers auto-retry on CPU, so correctness is guaranteed either way.
    var whisperUseGPU: Bool {
        get { defaults.object(forKey: Keys.whisperUseGPU) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.whisperUseGPU) }
    }

    /// Default FALSE. The current homebrew ggml + whisper.cpp build
    /// ships with flash-attn ENABLED by default, but flash-attn produces
    /// empty output on pre-M5 Apple Silicon (M1/M2/M3/M4). We pass
    /// --no-flash-attn unless the user explicitly opts in.
    var whisperFlashAttention: Bool {
        get { defaults.object(forKey: Keys.whisperFlashAttention) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.whisperFlashAttention) }
    }

    /// Speaker diarization. Off by default — it requires a tinydiarize-capable
    /// whisper model and the `--diarize` flag, which standard ggml models
    /// ignore. When on, WhisperRunner appends `--diarize` and the transcript
    /// gets `[SPEAKER_NN]` turn markers (see SpeakerDiarization.swift).
    var whisperDiarizationEnabled: Bool {
        get { defaults.object(forKey: Keys.whisperDiarizationEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.whisperDiarizationEnabled) }
    }

    /// Phase B — after a meeting is summarized, run a second local Ollama pass
    /// to extract the people mentioned and feed them into the People graph.
    /// Default true; entirely on-device. Disable to skip the extra LLM pass.
    var autoExtractPeople: Bool {
        get { defaults.object(forKey: Keys.autoExtractPeople) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.autoExtractPeople) }
    }

    /// Notion database ID where action items get pushed. The database
    /// must have at least the properties: Name (title), Status (status),
    /// Priority (select), Due (date), Meeting (rich_text).
    var notionActionItemsDatabaseID: String? {
        get { defaults.string(forKey: Keys.notionActionItemsDatabaseID) }
        set {
            if let v = newValue, !v.isEmpty {
                defaults.set(v, forKey: Keys.notionActionItemsDatabaseID)
            } else {
                defaults.removeObject(forKey: Keys.notionActionItemsDatabaseID)
            }
        }
    }

    /// Linear personal API key (Linear → Settings → Security & access → API →
    /// Personal API keys). Used to pull issues into the task tracker. Linear's
    /// API is free; no usage charges.
    ///
    /// Storage: macOS Keychain (`KeychainStore.Account.linearAPIKey`).
    /// First read transparently migrates any legacy UserDefaults value.
    var linearAPIKey: String? {
        get { KeychainStore.read(.linearAPIKey) }
        set { KeychainStore.write(.linearAPIKey, newValue) }
    }

    var lastTaskSync: Date? {
        get { defaults.object(forKey: Keys.lastTaskSync) as? Date }
        set {
            if let v = newValue { defaults.set(v, forKey: Keys.lastTaskSync) }
            else { defaults.removeObject(forKey: Keys.lastTaskSync) }
        }
    }

    // MARK: - Google Drive export

    private func optString(_ key: String) -> String? {
        guard let v = defaults.string(forKey: key), !v.isEmpty else { return nil }
        return v
    }
    private func setOpt(_ value: String?, _ key: String) {
        if let v = value, !v.isEmpty { defaults.set(v, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    /// OAuth "Desktop app" client ID. NOT a secret — paired with the
    /// client secret + redirect URI, the client ID is published to the
    /// user's browser during the OAuth flow. UserDefaults is fine.
    var googleClientID: String? {
        get { optString(Keys.googleClientID) }
        set { setOpt(newValue, Keys.googleClientID) }
    }
    /// OAuth "Desktop app" client SECRET — stored in Keychain.
    /// First read transparently migrates any legacy UserDefaults value.
    var googleClientSecret: String? {
        get { KeychainStore.read(.googleClientSecret) }
        set { KeychainStore.write(.googleClientSecret, newValue) }
    }
    /// Long-lived refresh token from the OAuth flow — Keychain.
    /// First read transparently migrates any legacy UserDefaults value.
    var googleRefreshToken: String? {
        get { KeychainStore.read(.googleRefreshToken) }
        set { KeychainStore.write(.googleRefreshToken, newValue) }
    }
    /// Drive folder exports land in (created on demand).
    var googleDriveFolderName: String {
        get { optString(Keys.googleDriveFolderName) ?? "MeetingScribe" }
        set { setOpt(newValue, Keys.googleDriveFolderName) }
    }
    /// Cached id of the created/located Drive folder.
    var googleDriveFolderID: String? {
        get { optString(Keys.googleDriveFolderID) }
        set { setOpt(newValue, Keys.googleDriveFolderID) }
    }
}
