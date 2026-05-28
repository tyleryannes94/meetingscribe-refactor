import Foundation

/// Versioned envelope for persisted JSON files. New writes wrap the
/// payload as `{ "schemaVersion": N, "data": {...} }`. Reads accept
/// both shapes — legacy (raw payload) and versioned — so we can
/// migrate without breaking older meetings on disk.
///
/// Usage:
///     // Write
///     let env = SchemaEnvelope(version: 2, data: meeting)
///     try SharedCoders.encoder(pretty: true, sorted: true).encode(env).write(to: url)
///
///     // Read (handles both shapes)
///     let meeting: Meeting = try SchemaEnvelope.decode(Meeting.self, from: data,
///                                                     currentVersion: 2)
public struct SchemaEnvelope<Payload: Codable>: Codable {
    public let schemaVersion: Int
    public let data: Payload

    public init(version: Int, data: Payload) {
        self.schemaVersion = version
        self.data = data
    }
}

extension SchemaEnvelope {
    /// Decode either a versioned envelope or a legacy raw payload.
    /// `currentVersion` is the version the caller expects; if the file
    /// is older, the caller can run a migration before consuming the
    /// returned value. `migrate` is called with the decoded payload
    /// when `decodedVersion < currentVersion` so callers can transform.
    public static func decode(
        _ type: Payload.Type,
        from data: Data,
        currentVersion: Int,
        decoder: JSONDecoder = SharedCoders.decoder(),
        migrate: ((Payload, _ from: Int, _ to: Int) -> Payload)? = nil
    ) throws -> Payload {
        // Try versioned first.
        if let env = try? decoder.decode(SchemaEnvelope<Payload>.self, from: data) {
            if env.schemaVersion == currentVersion { return env.data }
            if let migrate { return migrate(env.data, env.schemaVersion, currentVersion) }
            return env.data
        }
        // Fall back to legacy raw payload.
        let raw = try decoder.decode(Payload.self, from: data)
        if let migrate { return migrate(raw, 0, currentVersion) }
        return raw
    }
}
