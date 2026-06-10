import SwiftUI
import Foundation

// MARK: - Controller

/// Drives the cross-device sync from Settings: reads/writes the same
/// `~/.config/meetingscribe-sync/config.env` the shell installer uses, runs a
/// manual "send" (this Mac → hub) via the installed sender script, and runs a
/// manual "ingest" (promote `_remote/<device>/` into the live vault) via the
/// bundled `MeetingScribeSync` binary. The goal is to adjust paths and trigger
/// a sync without dropping to Terminal — including fixing the storageDir vs.
/// HUB_VAULT mismatch that makes files sync but never appear.
@available(macOS 14.0, *)
@MainActor
final class CrossDeviceSyncController: ObservableObject {
    struct Config {
        var hubUser = ""
        var hubHost = ""
        var deviceName = "work-macbook"
        var hubVault = ""
        var vaultLocal = ""
    }

    @Published var config = Config()
    @Published var configExists = false
    @Published var senderInstalled = false      // ~/.local/bin/meetingscribe-sync.sh present
    @Published var ingestAvailable = false       // bundled MeetingScribeSync present
    @Published var running = false
    @Published var output = ""
    @Published var lastReceived = ""             // hub: newest _remote/<device>/.last_sync
    @Published var lastSendLog = ""              // sender: sync.log freshness

    private let fm = FileManager.default
    private var home: URL { fm.homeDirectoryForCurrentUser }

    var configURL: URL { home.appendingPathComponent(".config/meetingscribe-sync/config.env") }
    var senderScriptURL: URL { home.appendingPathComponent(".local/bin/meetingscribe-sync.sh") }
    var logURL: URL { home.appendingPathComponent("Library/Logs/MeetingScribe/sync.log") }
    var syncBinaryURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/MeetingScribeSync") }

    private var defaultSSHKey: String { home.appendingPathComponent(".ssh/meetingscribe_sync").path }
    private var defaultLogDir: String { home.appendingPathComponent("Library/Logs/MeetingScribe").path }

    // MARK: Load

    func refresh() {
        configExists = fm.fileExists(atPath: configURL.path)
        senderInstalled = fm.isExecutableFile(atPath: senderScriptURL.path)
        ingestAvailable = fm.isExecutableFile(atPath: syncBinaryURL.path)

        let raw = rawConfig()
        config = Config(
            hubUser: raw["HUB_USER"] ?? "",
            hubHost: raw["HUB_HOST"] ?? "",
            deviceName: raw["DEVICE_NAME"] ?? "work-macbook",
            hubVault: raw["HUB_VAULT"] ?? "",
            vaultLocal: raw["VAULT_LOCAL"] ?? AppSettings.shared.storageDir.path
        )
        refreshStatus()
    }

    /// Newest `.last_sync` heartbeat under this vault's `_remote/<device>/`
    /// (hub side) and the sender log's freshness (sender side).
    func refreshStatus() {
        lastReceived = ""
        let remote = AppSettings.shared.storageDir.appendingPathComponent("_remote", isDirectory: true)
        if let devices = try? fm.contentsOfDirectory(at: remote,
            includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            var best: (String, Date)?
            for dev in devices {
                let stamp = dev.appendingPathComponent(".last_sync")
                guard let s = try? String(contentsOf: stamp, encoding: .utf8) else { continue }
                let when = (try? stamp.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if best == nil || when > best!.1 {
                    best = ("\(dev.lastPathComponent): \(s.trimmingCharacters(in: .whitespacesAndNewlines))", when)
                }
            }
            if let best { lastReceived = best.0 }
        }

        lastSendLog = ""
        if let attrs = try? fm.attributesOfItem(atPath: logURL.path),
           let mod = attrs[.modificationDate] as? Date {
            lastSendLog = mod.formatted(date: .abbreviated, time: .shortened)
        }
    }

    private func rawConfig() -> [String: String] {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.hasPrefix("#"), let eq = s.firstIndex(of: "=") else { continue }
            let key = String(s[..<eq]).trimmingCharacters(in: .whitespaces)
            var val = String(s[s.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")), val.count >= 2 {
                val = String(val.dropFirst().dropLast())
            }
            out[key] = val
        }
        return out
    }

    // MARK: Save

    /// Writes config.env preserving the installer's format: HUB_VAULT is
    /// single-quoted (so a literal `$HOME` expands on the hub), the rest are
    /// double-quoted local strings. Keys we don't surface (SSH_KEY, LOG_DIR) are
    /// preserved if present, else defaulted.
    func saveConfig() {
        var raw = rawConfig()
        raw["HUB_USER"] = config.hubUser.trimmingCharacters(in: .whitespaces)
        raw["HUB_HOST"] = config.hubHost.trimmingCharacters(in: .whitespaces)
        raw["DEVICE_NAME"] = config.deviceName.trimmingCharacters(in: .whitespaces)
        raw["HUB_VAULT"] = config.hubVault.trimmingCharacters(in: .whitespaces)
        raw["VAULT_LOCAL"] = config.vaultLocal.trimmingCharacters(in: .whitespaces)
        if (raw["SSH_KEY"] ?? "").isEmpty { raw["SSH_KEY"] = defaultSSHKey }
        if (raw["LOG_DIR"] ?? "").isEmpty { raw["LOG_DIR"] = defaultLogDir }

        let singleQuoted: Set<String> = ["HUB_VAULT"]
        let order = ["HUB_USER", "HUB_HOST", "DEVICE_NAME", "HUB_VAULT", "SSH_KEY", "VAULT_LOCAL", "LOG_DIR"]
        var lines = ["# MeetingScribe sync config — edited from Settings."]
        for k in order {
            guard let v = raw[k], !v.isEmpty else { continue }
            lines.append(singleQuoted.contains(k) ? "\(k)='\(v)'" : "\(k)=\"\(v)\"")
        }
        do {
            try fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: configURL, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
            output = "Saved \(configURL.path)"
        } catch {
            output = "Couldn't save config: \(error.localizedDescription)"
        }
        refresh()
    }

    func useThisMacStorageAsLocal() {
        config.vaultLocal = AppSettings.shared.storageDir.path
    }

    // MARK: Actions

    /// Push this Mac's vault to the hub by running the installed sender script.
    func sendNow(dryRun: Bool) async {
        guard senderInstalled else { output = "Sender not installed. Run scripts/sync/install-sync.sh once on this Mac."; return }
        running = true; defer { running = false }
        output = dryRun ? "Previewing send…" : "Sending to hub…"
        let args = dryRun ? ["--dry-run"] : []
        let (code, out) = await Self.run(URL(fileURLWithPath: "/bin/bash"),
                                         args: [senderScriptURL.path] + args)
        output = (out.isEmpty ? "(no output — see sync log)" : out)
            + "\n[exit \(code)]"
        refreshStatus()
    }

    /// Query the hub over SSH for the folder its app actually reads, so the
    /// user can point HUB_VAULT at the right place without guessing.
    func detectHubVault() async {
        let user = config.hubUser.trimmingCharacters(in: .whitespaces)
        let host = config.hubHost.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty, !host.isEmpty else { output = "Set hub host and user first."; return }
        running = true; defer { running = false }
        output = "Asking the hub where its vault is…"
        let key = (rawConfig()["SSH_KEY"] ?? defaultSSHKey)
        let (code, out) = await Self.run(URL(fileURLWithPath: "/usr/bin/ssh"),
            args: ["-i", key, "-o", "BatchMode=yes", "-o", "ConnectTimeout=20",
                   "\(user)@\(host)", "defaults read com.tyleryannes.MeetingScribe storageDir"])
        let detected = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if code == 0, !detected.isEmpty, detected.hasPrefix("/") {
            config.hubVault = detected
            output = "Hub vault: \(detected)\nClick Save to apply."
        } else {
            output = "Couldn't read the hub's vault (exit \(code)). Is Tailscale up and the SSH key authorized?\n\(out)"
        }
    }

    /// Promote everything the transport delivered into `_remote/<device>/` —
    /// meetings, voice notes, people, tasks, tags — into the live vault.
    func ingestNow(apply: Bool) async {
        guard ingestAvailable else { output = "MeetingScribeSync binary not found in the app bundle."; return }
        running = true; defer { running = false }
        output = apply ? "Ingesting work-device data…" : "Previewing ingest…"
        let args = apply ? ["--apply"] : []
        let (code, out) = await Self.run(syncBinaryURL, args: args,
                                         env: ["MEETINGSCRIBE_STORAGE": AppSettings.shared.storageDir.path])
        output = out + "\n[exit \(code)]"
        if apply { NotificationCenter.default.post(name: .meetingScribeSettingsChanged, object: nil) }
        refreshStatus()
    }

    func revealConfig() {
        if fm.fileExists(atPath: configURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([configURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([configURL.deletingLastPathComponent()])
        }
    }

    func openLog() {
        if fm.fileExists(atPath: logURL.path) { NSWorkspace.shared.open(logURL) }
    }

    // MARK: Subprocess

    /// Runs an external command off the main thread and returns (exitCode,
    /// combined stdout+stderr). A single pipe for both streams avoids the
    /// dual-drain deadlock. PATH is widened so Homebrew rsync/ssh are found.
    nonisolated static func run(_ executable: URL, args: [String],
                                env extra: [String: String] = [:]) async -> (Int32, String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = executable
                proc.arguments = args
                var environment = ProcessInfo.processInfo.environment
                let path = environment["PATH"] ?? ""
                environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + path
                for (k, v) in extra { environment[k] = v }
                proc.environment = environment
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = pipe
                do {
                    try proc.run()
                } catch {
                    cont.resume(returning: (-1, "Failed to launch \(executable.lastPathComponent): \(error.localizedDescription)"))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                cont.resume(returning: (proc.terminationStatus, String(data: data, encoding: .utf8) ?? ""))
            }
        }
    }
}

// MARK: - View

/// Settings card for cross-device sync. Surfaces the config the shell installer
/// writes, plus one-click Send (this Mac → hub) and Ingest (promote work-device
/// data into the live vault) so the whole flow is adjustable without Terminal.
@available(macOS 14.0, *)
struct CrossDeviceSyncSection: View {
    @StateObject private var ctl = CrossDeviceSyncController()

    var body: some View {
        Section("Cross-device sync") {
            Text("Back up a work Mac into this second brain over Tailscale, then fold it in — meetings, voice notes, people, and tasks. Send runs on the work Mac; Ingest runs on the hub (Mac mini). Both read the storage folder set above, so they always match what the app shows.")
                .font(.caption).foregroundStyle(.secondary)

            // Status row
            HStack(spacing: 12) {
                statusChip(ctl.senderInstalled, on: "Send ready", off: "Send not set up")
                statusChip(ctl.ingestAvailable, on: "Ingest ready", off: "Ingest unavailable")
                if ctl.running { ProgressView().controlSize(.small) }
            }
            if !ctl.lastReceived.isEmpty {
                Text("Last received — \(ctl.lastReceived)").font(.caption2).foregroundStyle(.secondary)
            }
            if !ctl.lastSendLog.isEmpty {
                Text("Sync log updated \(ctl.lastSendLog)").font(.caption2).foregroundStyle(.tertiary)
            }

            // Config editor
            Group {
                HStack {
                    TextField("Hub host (Tailscale name / 100.x IP)", text: $ctl.config.hubHost)
                    TextField("Hub user", text: $ctl.config.hubUser).frame(width: 120)
                }
                TextField("This device's name (folder on the hub)", text: $ctl.config.deviceName)
                HStack {
                    TextField("Hub vault path (the folder the hub app reads)", text: $ctl.config.hubVault)
                    Button("Detect") { Task { await ctl.detectHubVault() } }
                        .disabled(ctl.running)
                }
                Text("Send delivers into <hub vault>/_remote/\(ctl.config.deviceName.isEmpty ? "<device>" : ctl.config.deviceName)/. This MUST equal the hub app's storage folder, or files sync but never appear. Use Detect to read it off the hub.")
                    .font(.caption2).foregroundStyle(.tertiary)
                HStack {
                    TextField("This Mac's vault to send (local source)", text: $ctl.config.vaultLocal)
                    Button("Use my folder") { ctl.useThisMacStorageAsLocal() }
                }
                HStack {
                    Button("Save config") { ctl.saveConfig() }
                        .buttonStyle(.borderedProminent)
                    Button("Reveal config") { ctl.revealConfig() }
                    if ctl.configExists {
                        Button("Open sync log") { ctl.openLog() }.disabled(ctl.lastSendLog.isEmpty)
                    }
                }
            }

            // Actions
            HStack {
                Button { Task { await ctl.sendNow(dryRun: false) } } label: {
                    Label("Send now", systemImage: "arrow.up.circle")
                }
                .disabled(ctl.running || !ctl.senderInstalled)
                Button { Task { await ctl.sendNow(dryRun: true) } } label: {
                    Label("Preview", systemImage: "eye")
                }
                .disabled(ctl.running || !ctl.senderInstalled)
                Spacer()
                Button { Task { await ctl.ingestNow(apply: false) } } label: {
                    Label("Preview ingest", systemImage: "eye")
                }
                .disabled(ctl.running || !ctl.ingestAvailable)
                Button { Task { await ctl.ingestNow(apply: true) } } label: {
                    Label("Ingest now", systemImage: "tray.and.arrow.down")
                }
                .disabled(ctl.running || !ctl.ingestAvailable)
            }
            if !ctl.senderInstalled {
                Text("To enable Send + scheduled backup on a work Mac, run scripts/sync/install-sync.sh there once (it sets up the SSH key). After that, everything is adjustable here.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            // Output console
            if !ctl.output.isEmpty {
                ScrollView {
                    Text(ctl.output)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 130)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .onAppear { ctl.refresh() }
    }

    @ViewBuilder
    private func statusChip(_ ok: Bool, on: String, off: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? .green : .secondary)
            Text(ok ? on : off).font(.caption)
        }
    }
}
