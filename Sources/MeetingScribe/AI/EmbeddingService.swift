import Foundation
import OSLog

/// On-device text embeddings for semantic recall (C2-1b / C5-10).
///
/// Calls the local Ollama embeddings endpoint with a small model
/// (`nomic-embed-text` by default, ~274 MB). Everything stays on the device —
/// the same egress allowlist that guards summaries (E4-3) guards this too, so a
/// non-local `ollamaURL` can't ship vault text off-machine. Degrades gracefully
/// (returns nil) when Ollama or the model isn't available, so search simply
/// falls back to lexical FTS.
struct EmbeddingService {
    private static let log = Logger(subsystem: "com.tyleryannes.MeetingScribe", category: "Embeddings")

    private struct Request: Encodable { let model: String; let prompt: String }
    private struct Response: Decodable { let embedding: [Double] }

    /// Embed a single text. Returns nil on any failure (Ollama down, model not
    /// pulled, empty input) — callers treat nil as "no semantic signal".
    static func embed(_ text: String) async -> [Float]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let settings = AppSettings.shared
        let url = settings.ollamaURL.appendingPathComponent("api/embeddings")
        // Same local-only invariant as transcript summarization.
        do { try EgressPolicy.assertOllamaEgressAllowed(url) }
        catch { log.error("Embedding egress blocked: \(error.localizedDescription, privacy: .public)"); return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        // Cap the payload — embedding models truncate anyway, and a whole
        // transcript is wasteful. Title + summary is plenty of signal.
        let capped = String(trimmed.prefix(8000))
        req.httpBody = try? JSONEncoder().encode(Request(model: settings.ollamaEmbeddingModel, prompt: capped))

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard !decoded.embedding.isEmpty else { return nil }
            return decoded.embedding.map { Float($0) }
        } catch {
            log.error("Embedding request failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Cosine similarity of two equal-length vectors (1 = identical direction).
    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }
}
