import Foundation

/// Central network-egress policy (E4-3).
///
/// MeetingScribe's marquee promise is "everything stays local." The only
/// outbound destinations are a small set of opt-in integrations plus the
/// local LLM endpoint. This type makes that promise an *enforced* invariant
/// rather than an aspiration:
///
///  - `allowedHosts` is a compile-time allowlist of every host the app is
///    permitted to reach. New egress must be added here deliberately.
///  - The Ollama endpoint is user-settable (`AppSettings.ollamaURL`) and
///    receives full transcripts/summaries. If a user (or a typo) points it at
///    a non-local host, transcripts would silently leave the device. Callers
///    POSTing meeting content must gate on `assertOllamaEgressAllowed` first;
///    a non-local endpoint is refused until the user explicitly approves it.
enum EgressPolicy {

    /// Hosts the app is allowed to reach. Local LLM hosts are handled
    /// separately by `isLocal`. Everything here is an opt-in integration or a
    /// model/update host referenced by a hardcoded HTTPS constant.
    static let allowedHosts: Set<String> = [
        // Google (OAuth, People/Contacts, Drive)
        "accounts.google.com",
        "oauth2.googleapis.com",
        "people.googleapis.com",
        "www.googleapis.com",
        // Notion
        "api.notion.com",
        // Linear
        "api.linear.app",
        // Whisper model download
        "huggingface.co",
        // Sparkle appcast / release assets
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    ]

    /// True when the URL targets the local machine (the only place a transcript
    /// is allowed to be POSTed without explicit approval).
    static func isLocal(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host == "0.0.0.0"
            || host.hasSuffix(".local")
    }

    /// True if the host is on the compile-time allowlist or is local.
    static func isAllowed(_ url: URL) -> Bool {
        if isLocal(url) { return true }
        guard let host = url.host?.lowercased() else { return false }
        return allowedHosts.contains(host)
    }

    enum EgressError: Error, LocalizedError {
        case remoteEndpointNotApproved(host: String)

        var errorDescription: String? {
            switch self {
            case .remoteEndpointNotApproved(let host):
                return "The local-LLM endpoint points at a non-local host (\(host)). "
                    + "Sending a transcript there would take it off this device. "
                    + "Approve it in Settings → You/Ollama (\"Allow a non-local Ollama endpoint\") "
                    + "or set the URL back to http://127.0.0.1:11434."
            }
        }
    }

    /// Gate for any request that carries meeting content to Ollama. Allows a
    /// local endpoint unconditionally; a non-local endpoint is refused unless
    /// the user has explicitly approved remote egress in Settings. (E4-3)
    static func assertOllamaEgressAllowed(_ url: URL) throws {
        if isLocal(url) { return }
        if AppSettings.shared.allowRemoteOllamaEndpoint { return }
        throw EgressError.remoteEndpointNotApproved(host: url.host ?? url.absoluteString)
    }

    enum BrainDumpEgressError: Error, LocalizedError {
        case webAccessDisabled
        var errorDescription: String? {
            switch self {
            case .webAccessDisabled:
                return "Brain Dump web access is off. Turn on \"Allow web access\" in Settings → Integrations → Brain Dump before fetching URLs or running web searches."
            }
        }
    }

    /// Gate for Brain Dump URL fetching and web search. Unlike the Ollama and
    /// integration paths, the destination is arbitrary, so the allowlist
    /// approach doesn't fit — instead the user opts in once
    /// (`AppSettings.allowBrainDumpWebAccess`) and that toggle gates every
    /// outbound generic-web request. HTTPS-only.
    static func assertGenericOutboundAllowed(_ url: URL) throws {
        guard AppSettings.shared.allowBrainDumpWebAccess else {
            throw BrainDumpEgressError.webAccessDisabled
        }
        // HTTP plaintext is never allowed for arbitrary hosts — only Ollama /
        // local services get the http exemption.
        if !isLocal(url), (url.scheme ?? "").lowercased() != "https" {
            throw EgressError.remoteEndpointNotApproved(host: url.host ?? url.absoluteString)
        }
    }
}
