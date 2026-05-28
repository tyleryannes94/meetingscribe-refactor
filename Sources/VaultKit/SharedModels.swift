import Foundation

/// Decode-only mirrors of the app's persisted types, shared with the MCP
/// servers so they don't carry their own (drift-prone) reimplementations.
///
/// The main `MeetingScribe` target has richer types (with computed
/// properties, equatable conformances, UI helpers) — those wrap or
/// encode/decode through these DTOs. The MCP servers and any other
/// out-of-process readers consume the DTOs directly.

public struct MeetingDTO: Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let attendees: [String]
    public let notes: String?
    public let location: String?
    public let conferenceURL: String?
    public let calendarName: String?
    public let seriesID: String?
    public let userDescription: String?
    public let userTitle: String?
    public let isImpromptu: Bool?
    public let isImported: Bool?
    public let segmentCount: Int?
    /// Persisted relative path within the storage root. Lets us resolve
    /// the meeting's directory in O(1) without walking the filesystem.
    /// Optional for backward compatibility with meetings written before
    /// this field existed (those fall back to a one-time directory walk).
    public let relativeFolderPath: String?
    /// Recorded health status — populated by the audio pipeline at the
    /// end of a recording so the UI can render "no transcript" / "fallback
    /// succeeded" / etc. badges. Optional for older meetings.
    public let health: MeetingHealthDTO?

    public init(id: String, title: String, startDate: Date, endDate: Date,
                attendees: [String], notes: String?, location: String?,
                conferenceURL: String?, calendarName: String?, seriesID: String?,
                userDescription: String?, userTitle: String?, isImpromptu: Bool?,
                isImported: Bool? = nil, segmentCount: Int? = nil,
                relativeFolderPath: String? = nil, health: MeetingHealthDTO? = nil) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.attendees = attendees
        self.notes = notes
        self.location = location
        self.conferenceURL = conferenceURL
        self.calendarName = calendarName
        self.seriesID = seriesID
        self.userDescription = userDescription
        self.userTitle = userTitle
        self.isImpromptu = isImpromptu
        self.isImported = isImported
        self.segmentCount = segmentCount
        self.relativeFolderPath = relativeFolderPath
        self.health = health
    }
}

/// End-of-pipeline summary of how the recording went. Drives UI badges.
public struct MeetingHealthDTO: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case ok                  // both sources captured, transcript non-empty
        case partial             // one source missing or very short
        case noTranscript        // pipeline finished but transcript is empty
        case fallbackUsed        // GPU pass produced empty, CPU retry succeeded
    }
    public let status: Status
    public let warnings: [String]
    public let recordedSeconds: Double
    public let micBytes: Int64
    public let systemBytes: Int64

    public init(status: Status, warnings: [String], recordedSeconds: Double,
                micBytes: Int64, systemBytes: Int64) {
        self.status = status
        self.warnings = warnings
        self.recordedSeconds = recordedSeconds
        self.micBytes = micBytes
        self.systemBytes = systemBytes
    }
}

public struct QuickNoteDTO: Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let createdAt: Date
    public let durationSeconds: Double
    public let snippet: String
    public let wasDictation: Bool

    public init(id: String, title: String, createdAt: Date,
                durationSeconds: Double, snippet: String, wasDictation: Bool) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.snippet = snippet
        self.wasDictation = wasDictation
    }
}

public struct TagFileDTO: Codable, Sendable {
    public struct Tag: Codable, Sendable {
        public let id: String
        public let name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }
    public let tags: [Tag]
    public let meetingTags: [String: [String]]
    public let seriesTags: [String: [String]]

    public init(tags: [Tag], meetingTags: [String: [String]], seriesTags: [String: [String]]) {
        self.tags = tags
        self.meetingTags = meetingTags
        self.seriesTags = seriesTags
    }
}

public struct ActionItemDTO: Codable, Sendable {
    public let id: String
    public let meetingID: String
    public let meetingTitle: String
    public let meetingDate: Date
    public let title: String
    public let owner: String?
    public let notes: String?
    public let status: String
    public let priority: String
    public let dueDate: Date?
    public let notionPageID: String?
    public let notionURL: String?

    public init(id: String, meetingID: String, meetingTitle: String,
                meetingDate: Date, title: String, owner: String?,
                notes: String?, status: String, priority: String,
                dueDate: Date?, notionPageID: String?, notionURL: String?) {
        self.id = id
        self.meetingID = meetingID
        self.meetingTitle = meetingTitle
        self.meetingDate = meetingDate
        self.title = title
        self.owner = owner
        self.notes = notes
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.notionPageID = notionPageID
        self.notionURL = notionURL
    }
}

// MARK: - People / Second-Brain DTOs
//
// Decode-only mirror of the app's `Person` (and its sub-types). The MCP
// server uses these to expose people-graph + iMessage tools without having
// to import the AppKit-aware `Person` from the main app target. Field set
// is intentionally a strict subset of the on-disk schema — the in-app
// Person can grow new optional fields without breaking decode here.

public struct PersonMemoryDTO: Codable, Sendable {
    public let id: String
    public let text: String
    public let occurredOn: Date?
    public let createdAt: Date
    public init(id: String, text: String, occurredOn: Date?, createdAt: Date) {
        self.id = id; self.text = text
        self.occurredOn = occurredOn; self.createdAt = createdAt
    }
}

public struct PersonRelationshipDTO: Codable, Sendable {
    public let id: String
    public let toPersonID: String
    public let label: String
    public let createdAt: Date
    public init(id: String, toPersonID: String, label: String, createdAt: Date) {
        self.id = id; self.toPersonID = toPersonID
        self.label = label; self.createdAt = createdAt
    }
}

public struct PersonDTO: Codable, Sendable {
    public let id: String
    public let displayName: String
    public let company: String
    public let role: String
    public let emails: [String]
    public let phones: [String]
    public let addresses: [String]
    public let bio: String
    public let favorites: [String]
    public let memories: [PersonMemoryDTO]
    public let relationships: [PersonRelationshipDTO]
    public let tagIDs: [String]
    public let createdAt: Date
    public let updatedAt: Date
    public let lastInteractionAt: Date?
    public let birthday: Date?
    public let meetingMentions: [String]
    public let importSources: [String]

    private enum CodingKeys: String, CodingKey {
        case id, displayName, company, role, emails, phones, addresses,
             bio, favorites, memories, relationships, tagIDs,
             createdAt, updatedAt, lastInteractionAt, birthday,
             meetingMentions, importSources
    }

    /// Tolerant decode: every field past `id` and `displayName` has a
    /// sensible default so a person.json written by an older or newer
    /// build still loads. Matches the in-app `Person.init(from:)` style.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        company = (try? c.decode(String.self, forKey: .company)) ?? ""
        role = (try? c.decode(String.self, forKey: .role)) ?? ""
        emails = (try? c.decode([String].self, forKey: .emails)) ?? []
        phones = (try? c.decode([String].self, forKey: .phones)) ?? []
        addresses = (try? c.decode([String].self, forKey: .addresses)) ?? []
        bio = (try? c.decode(String.self, forKey: .bio)) ?? ""
        favorites = (try? c.decode([String].self, forKey: .favorites)) ?? []
        memories = (try? c.decode([PersonMemoryDTO].self, forKey: .memories)) ?? []
        relationships = (try? c.decode([PersonRelationshipDTO].self, forKey: .relationships)) ?? []
        // tagIDs is a Set<String> on disk but an array is wire-compatible
        // and easier for the MCP server's JSON output.
        if let arr = try? c.decode([String].self, forKey: .tagIDs) {
            tagIDs = arr
        } else if let set = try? c.decode(Set<String>.self, forKey: .tagIDs) {
            tagIDs = Array(set)
        } else {
            tagIDs = []
        }
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date(timeIntervalSince1970: 0)
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date(timeIntervalSince1970: 0)
        lastInteractionAt = (try? c.decodeIfPresent(Date.self, forKey: .lastInteractionAt)) ?? nil
        birthday = (try? c.decodeIfPresent(Date.self, forKey: .birthday)) ?? nil
        if let arr = try? c.decode([String].self, forKey: .meetingMentions) {
            meetingMentions = arr
        } else if let set = try? c.decode(Set<String>.self, forKey: .meetingMentions) {
            meetingMentions = Array(set)
        } else {
            meetingMentions = []
        }
        if let arr = try? c.decode([String].self, forKey: .importSources) {
            importSources = arr
        } else if let set = try? c.decode(Set<String>.self, forKey: .importSources) {
            importSources = Array(set)
        } else {
            importSources = []
        }
    }

    public init(id: String, displayName: String, company: String = "",
                role: String = "", emails: [String] = [], phones: [String] = [],
                addresses: [String] = [], bio: String = "", favorites: [String] = [],
                memories: [PersonMemoryDTO] = [],
                relationships: [PersonRelationshipDTO] = [],
                tagIDs: [String] = [], createdAt: Date = Date(),
                updatedAt: Date = Date(), lastInteractionAt: Date? = nil,
                birthday: Date? = nil, meetingMentions: [String] = [],
                importSources: [String] = []) {
        self.id = id; self.displayName = displayName
        self.company = company; self.role = role
        self.emails = emails; self.phones = phones
        self.addresses = addresses; self.bio = bio
        self.favorites = favorites; self.memories = memories
        self.relationships = relationships; self.tagIDs = tagIDs
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.lastInteractionAt = lastInteractionAt; self.birthday = birthday
        self.meetingMentions = meetingMentions; self.importSources = importSources
    }
}

// MARK: - Audio segment manifest (new in this refactor; replaces Meeting.segmentCount as source of truth)

/// Persisted per-meeting at `<dir>/audio/manifest.json`. Lets the audio
/// recorder own its own bookkeeping instead of mutating `Meeting.segmentCount`
/// from three different code paths.
public struct AudioManifestDTO: Codable, Sendable {
    public struct Segment: Codable, Sendable {
        public let index: Int               // 1-indexed
        public let micFile: String?         // filename relative to audio/
        public let systemFile: String?      // filename relative to audio/
        public let startedAt: Date
        public let endedAt: Date?
        public init(index: Int, micFile: String?, systemFile: String?,
                    startedAt: Date, endedAt: Date?) {
            self.index = index
            self.micFile = micFile
            self.systemFile = systemFile
            self.startedAt = startedAt
            self.endedAt = endedAt
        }
    }
    public var schemaVersion: Int
    public var segments: [Segment]

    public init(schemaVersion: Int = 1, segments: [Segment] = []) {
        self.schemaVersion = schemaVersion
        self.segments = segments
    }
}

// MARK: - Coder factories

/// Single source of truth for the JSON coders used everywhere we
/// touch disk. ISO-8601 dates, no key sorting on encode (callers
/// override when they want deterministic on-disk output).
public enum SharedCoders {
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
    public static func encoder(pretty: Bool = false, sorted: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        var fmt: JSONEncoder.OutputFormatting = []
        if pretty { fmt.insert(.prettyPrinted) }
        if sorted { fmt.insert(.sortedKeys) }
        e.outputFormatting = fmt
        return e
    }
}
