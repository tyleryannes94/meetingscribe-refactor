import SwiftUI

/// A failure translated into plain language (D4-1). The app previously rendered
/// raw `whisper-cli failed (1): … Re-download it via ./scripts/setup.sh` stderr
/// straight to the transcript tab — engineer-speak (and a shell instruction) in
/// front of a therapist mid-session. `ErrorPresenter` maps raw engine output to
/// three human fields, and `MSErrorState` renders them with a one-click fix.
struct PresentedError: Equatable {
    /// What happened, in one plain sentence.
    let title: String
    /// Why — what it means for the user's recording, no jargon.
    let diagnosis: String
    /// The fix-it button label, or nil when there's nothing to click.
    let fixLabel: String?
    let kind: Kind

    enum Kind: Equatable { case model, summaryEngine, audio, generic }

    var symbol: String {
        switch kind {
        case .model:         return "waveform.badge.exclamationmark"
        case .summaryEngine: return "sparkles"
        case .audio:         return "mic.slash"
        case .generic:       return "exclamationmark.triangle"
        }
    }
}

enum ErrorPresenter {
    /// Translate a raw error string into plain language. Heuristic, substring
    /// based — the raw text stays available behind a "Details" disclosure for
    /// support, but never leads.
    static func present(_ raw: String) -> PresentedError {
        let s = raw.lowercased()

        if s.contains("whisper") || s.contains("model file is corrupted")
            || s.contains("bad magic") || s.contains("invalid model")
            || s.contains("initialize whisper context") {
            return PresentedError(
                title: "Speech-to-text needs a quick fix",
                diagnosis: "The on-device speech model is missing or damaged, so this recording couldn't be turned into text.",
                fixLabel: "Re-download the speech model",
                kind: .model)
        }

        if s.contains("ollama") || s.contains("summar") {
            return PresentedError(
                title: "The summary engine wasn't running",
                diagnosis: "Your on-device summary engine was off when this finished, so there's no summary yet. The recording and transcript are safe.",
                fixLabel: "Open Setup",
                kind: .summaryEngine)
        }

        if (s.contains("empty") || s.contains("0 bytes") || s.contains("no playable"))
            && (s.contains("audio") || s.contains("byte")) {
            return PresentedError(
                title: "No audio was captured",
                diagnosis: "This recording didn't pick up any sound — the microphone or system-audio source may not have been active.",
                fixLabel: nil,
                kind: .audio)
        }

        return PresentedError(
            title: "Something went wrong",
            diagnosis: sanitize(raw),
            fixLabel: nil,
            kind: .generic)
    }

    /// Strip shell instructions and filesystem paths out of a fallback message
    /// so a generic error never tells the user to run a script.
    private static func sanitize(_ raw: String) -> String {
        var out = raw
        // Drop "Try ./scripts/foo.sh …" / "Re-download it via ./scripts/…" tails.
        for marker in ["Re-download it via", "Try ./", "via ./scripts", "run ", "./scripts"] {
            if let r = out.range(of: marker) { out = String(out[..<r.lowerBound]) }
        }
        // Remove absolute paths.
        out = out.replacingOccurrences(of: #"/[^\s]+/[^\s]+"#, with: "", options: .regularExpression)
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? "An unexpected error occurred. You can try again." : out
    }
}

/// The designed "failed" state (D4-1): a tinted card with a plain diagnosis, an
/// optional one-click fix, and the raw text tucked behind "Details" for support.
@available(macOS 14.0, *)
struct MSErrorState: View {
    let presented: PresentedError
    /// The raw engine text, shown only under "Details".
    var raw: String? = nil
    /// Invoked when the fix-it button is tapped.
    var onFix: (() -> Void)? = nil

    @State private var showDetails = false

    private var tint: Color { presented.kind == .audio ? NDS.gold : NDS.danger }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: presented.symbol)
                .scaledFont(18)
                .foregroundStyle(tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(presented.title)
                    .scaledFont(14, weight: .semibold)
                    .foregroundStyle(NDS.textPrimary)
                Text(presented.diagnosis)
                    .scaledFont(12.5)
                    .foregroundStyle(NDS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let label = presented.fixLabel, let onFix {
                        Button(label, action: onFix)
                            .buttonStyle(MSPrimaryButtonStyle())
                            .controlSize(.small) // design-lint:allow
                            .tint(tint)
                    }
                    if let raw, !raw.isEmpty {
                        Button(showDetails ? "Hide details" : "Details") {
                            withAnimation(.easeOut(duration: 0.15)) { showDetails.toggle() }
                        }
                        .buttonStyle(.plain)
                        .scaledFont(11.5, weight: .medium)
                        .foregroundStyle(NDS.textTertiary)
                    }
                }
                if showDetails, let raw {
                    Text(raw)
                        .scaledFont(11)
                        .monospaced()
                        .foregroundStyle(NDS.textTertiary)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radiusSmall))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: NDS.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: NDS.rowRadius).strokeBorder(tint.opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(presented.title). \(presented.diagnosis)")
    }
}
