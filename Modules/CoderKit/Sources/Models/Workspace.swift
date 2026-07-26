import Foundation

/// Represents the status of a workspace
public enum WorkspaceStatus: String, Codable, Sendable {
    case pending
    case starting
    case running
    case stopping
    case stopped
    case failed
    case canceling
    case deleting
    case deleted
}

/// Represents a Coder workspace
public struct Workspace: Codable, Sendable {
    public let id: UUID
    public let name: String
    public let ownerName: String
    public let templateName: String?
    public let status: WorkspaceStatus
    public let createdAt: Date
    public let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerName = "owner_name"
        case templateName = "template_name"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: UUID,
        name: String,
        ownerName: String,
        templateName: String?,
        status: WorkspaceStatus,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.ownerName = ownerName
        self.templateName = templateName
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Custom Date Decoding

extension Workspace {
    /// Cached formatters for performance (avoids per-decode allocation).
    nonisolated(unsafe) private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let iso8601WithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Parses an ISO 8601 date string, handling both with and without fractional seconds.
    private static func parseDate(_ string: String) -> Date? {
        iso8601WithFractionalSeconds.date(from: string)
            ?? iso8601WithoutFractionalSeconds.date(from: string)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        ownerName = try container.decode(String.self, forKey: .ownerName)
        templateName = try container.decodeIfPresent(String.self, forKey: .templateName)
        status = try container.decode(WorkspaceStatus.self, forKey: .status)

        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        guard let createdAt = Self.parseDate(createdAtString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt,
                in: container,
                debugDescription: "Invalid date format"
            )
        }
        self.createdAt = createdAt

        let updatedAtString = try container.decode(String.self, forKey: .updatedAt)
        guard let updatedAt = Self.parseDate(updatedAtString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .updatedAt,
                in: container,
                debugDescription: "Invalid date format"
            )
        }
        self.updatedAt = updatedAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(ownerName, forKey: .ownerName)
        try container.encodeIfPresent(templateName, forKey: .templateName)
        try container.encode(status, forKey: .status)
        try container.encode(Self.iso8601WithFractionalSeconds.string(from: createdAt), forKey: .createdAt)
        try container.encode(Self.iso8601WithFractionalSeconds.string(from: updatedAt), forKey: .updatedAt)
    }
}

// MARK: - Workspace List Response

/// A paginated response containing a list of workspaces.
public struct WorkspaceList: Codable, Sendable {
    /// The total count of workspaces matching the query (before pagination).
    public let count: Int
    /// The workspaces in this page of results.
    public let workspaces: [Workspace]

    public init(count: Int, workspaces: [Workspace]) {
        self.count = count
        self.workspaces = workspaces
    }
}
