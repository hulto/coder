import Foundation

/// Represents the status of a workspace build.
public enum WorkspaceBuildStatus: String, Codable, Sendable {
    case pending
    case starting
    case running
    case stopping
    case stopped
    case failed
    case canceling
    case deleted
}

/// The transition type for a workspace build.
public enum WorkspaceTransition: String, Codable, Sendable {
    case start
    case stop
    case delete
}

/// Represents a workspace build in the Coder API.
public struct WorkspaceBuild: Codable, Sendable, Identifiable {
    public let id: UUID
    public let workspaceID: UUID
    public let transition: WorkspaceTransition
    public let status: WorkspaceBuildStatus
    public let createdAt: Date
    public let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case transition
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: UUID,
        workspaceID: UUID,
        transition: WorkspaceTransition,
        status: WorkspaceBuildStatus,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.transition = transition
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Custom Date Decoding

extension WorkspaceBuild {
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
        workspaceID = try container.decode(UUID.self, forKey: .workspaceID)
        transition = try container.decode(WorkspaceTransition.self, forKey: .transition)
        status = try container.decode(WorkspaceBuildStatus.self, forKey: .status)

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
        try container.encode(workspaceID, forKey: .workspaceID)
        try container.encode(transition, forKey: .transition)
        try container.encode(status, forKey: .status)
        try container.encode(Self.iso8601WithFractionalSeconds.string(from: createdAt), forKey: .createdAt)
        try container.encode(Self.iso8601WithFractionalSeconds.string(from: updatedAt), forKey: .updatedAt)
    }
}
