# Windows / Cross-Platform Research Spike

Status: **research only** — no code committed for Windows. This documents what a
Windows port of MeetingScribe would actually require so we can make an informed
build/buy/skip decision.

## TL;DR

MeetingScribe is deeply tied to macOS frameworks (AppKit, SwiftUI-for-macOS,
AVFoundation, ScreenCaptureKit, EventKit, CryptoKit/Keychain, Sparkle). A
native Swift-on-Windows port is **not** a recompile — it's a UI + platform-layer
rewrite. The recommended path is an **Electron (or Tauri) wrapper** that reuses
the already-portable engine pieces (whisper.cpp + Ollama) over a thin local
service, rather than porting the Swift app.

**Estimated effort for a real cross-platform rewrite: ~6–8 months, 1–2 engineers.**

## Current macOS-only dependencies

| Area | Framework | macOS-only? | Windows replacement |
|---|---|---|---|
| UI | SwiftUI (macOS) + AppKit (`NSWorkspace`, `NSSavePanel`, `NSPasteboard`, menu bar) | Yes | Web UI (Electron/Tauri) or WinUI 3 |
| Mic capture | AVFoundation (`AVAudioEngine`) | Yes | WASAPI / `IAudioClient`, or `cpal` (Rust) / `naudiodon` (Node) |
| System-audio capture | ScreenCaptureKit | Yes (and no direct equivalent) | WASAPI **loopback** capture — different model, must be rebuilt |
| Calendar | EventKit | Yes | Microsoft Graph / Outlook + Google Calendar APIs |
| Mic-in-use detection | CoreAudio (`kAudioDevicePropertyDeviceIsRunningSomewhere`) | Yes | WASAPI session enumeration (`IAudioSessionManager2`) |
| Secrets | Keychain (`Security`) | Yes | Windows Credential Manager (DPAPI) |
| Encryption | CryptoKit | Yes | swift-crypto (portable) / Web Crypto / `ring` |
| Updates | Sparkle | Yes | Squirrel / electron-updater / MSIX |
| Global hotkey | Carbon `RegisterEventHotKey` | Yes | `RegisterHotKey` (Win32) |
| App intents / widgets | AppIntents | Yes | n/a (Windows has no equivalent) |

## What's already portable

- **whisper.cpp** (`whisper-cli`) — runs on Windows; transcription needs no change.
- **Ollama** — ships a Windows build; the HTTP API (`/api/generate`) is identical.
- **The data model + business logic** — `Meeting`, `ActionItem`, summarization
  prompts, the export/markdown logic, and the new `SecondBrainCore` are plain
  Swift/Foundation with no UI ties. Foundation is available via swift.org's
  Windows toolchain, so this layer is the most reusable.

## Options considered

1. **Native Swift-on-Windows port.** swift.org ships a Windows toolchain, but
   there's no SwiftUI/AppKit — you'd rebuild the entire UI in WinUI/Win32 and
   reimplement every platform service above. Highest fidelity, highest cost,
   smallest ecosystem. **Not recommended.**

2. **Electron (or Tauri) wrapper around a local engine — recommended.**
   - Package `whisper.cpp` + `Ollama` as local backends.
   - A small local service (Swift-Foundation core compiled for Windows, or a
     Node/Rust shim) exposes record/transcribe/summarize over localhost.
   - The UI is a web frontend reused across macOS and Windows.
   - System-audio capture is the one genuinely hard part: WASAPI loopback
     replaces ScreenCaptureKit and must be written per-platform.
   - Tauri (Rust core + webview) is lighter than Electron if bundle size matters.

3. **Skip Windows; offer a web companion.** A read-only/notes web app backed by
   the (Phase 2) CloudKit/sync layer covers many "I'm on my work PC" cases at a
   fraction of the cost.

## Recommendation

Pursue **Option 2 (Electron/Tauri wrapper)** if Windows is a real requirement,
and front-load a **2–3 week spike on WASAPI loopback capture** — that's the
load-bearing risk. Otherwise prefer **Option 3** and invest in sync instead.

### Rough phasing (Option 2)

1. Extract the portable core (model + transcription/summary orchestration) into
   a platform-agnostic library — `SecondBrainCore` (Phase 2) is the first step.
2. Spike WASAPI loopback + mic capture on Windows (highest risk).
3. Stand up the local service + web UI; wire whisper.cpp + Ollama.
4. Calendar via Graph/Google; updates via electron-updater; secrets via DPAPI.
5. Harden, package (MSIX), and ship a beta.
