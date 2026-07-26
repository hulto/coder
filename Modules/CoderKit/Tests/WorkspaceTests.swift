import Testing
import Foundation
@testable import CoderKit

@Test func testWorkspaceDecoding() throws {
    let jsonString = """
    {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "name": "my-workspace",
        "owner_name": "alice",
        "template_name": "kubernetes",
        "status": "running",
        "created_at": "2024-01-15T10:30:45.123Z",
        "updated_at": "2024-01-15T11:45:30.456Z"
    }
    """

    let jsonData = try #require(jsonString.data(using: .utf8))
    let workspace = try JSONDecoder().decode(Workspace.self, from: jsonData)

    #expect(workspace.id == UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000"))
    #expect(workspace.name == "my-workspace")
    #expect(workspace.ownerName == "alice")
    #expect(workspace.templateName == "kubernetes")
    #expect(workspace.status == .running)

    let calendar = Calendar(identifier: .gregorian)
    var components = DateComponents()
    components.year = 2024
    components.month = 1
    components.day = 15
    components.hour = 10
    components.minute = 30
    components.second = 45
    components.nanosecond = 123_000_000
    components.timeZone = TimeZone(secondsFromGMT: 0)

    let expectedCreatedAt = try #require(calendar.date(from: components))
    #expect(abs(workspace.createdAt.timeIntervalSince1970 - expectedCreatedAt.timeIntervalSince1970) < 0.001)

    components.hour = 11
    components.minute = 45
    components.second = 30
    components.nanosecond = 456_000_000
    let expectedUpdatedAt = try #require(calendar.date(from: components))
    #expect(abs(workspace.updatedAt.timeIntervalSince1970 - expectedUpdatedAt.timeIntervalSince1970) < 0.001)
}

@Test func testWorkspaceDecodingWithNullTemplateName() throws {
    let jsonString = """
    {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "name": "my-workspace",
        "owner_name": "alice",
        "template_name": null,
        "status": "starting",
        "created_at": "2024-01-15T10:30:45.123Z",
        "updated_at": "2024-01-15T11:45:30.456Z"
    }
    """

    let jsonData = try #require(jsonString.data(using: .utf8))
    let workspace = try JSONDecoder().decode(Workspace.self, from: jsonData)

    #expect(workspace.templateName == nil)
    #expect(workspace.status == .starting)
}

@Test func testWorkspaceDecodingWithAbsentTemplateName() throws {
    let jsonString = """
    {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "name": "my-workspace",
        "owner_name": "alice",
        "status": "running",
        "created_at": "2024-01-15T10:30:45.123Z",
        "updated_at": "2024-01-15T11:45:30.456Z"
    }
    """

    let jsonData = try #require(jsonString.data(using: .utf8))
    let workspace = try JSONDecoder().decode(Workspace.self, from: jsonData)

    #expect(workspace.templateName == nil)
    #expect(workspace.status == .running)
}

@Test func testWorkspaceDecodingWithoutFractionalSeconds() throws {
    let jsonString = """
    {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "name": "my-workspace",
        "owner_name": "alice",
        "status": "running",
        "created_at": "2024-01-15T10:30:45Z",
        "updated_at": "2024-01-15T11:45:30Z"
    }
    """

    let jsonData = try #require(jsonString.data(using: .utf8))
    let workspace = try JSONDecoder().decode(Workspace.self, from: jsonData)

    #expect(workspace.name == "my-workspace")
    #expect(workspace.status == .running)

    let calendar = Calendar(identifier: .gregorian)
    var components = DateComponents()
    components.year = 2024
    components.month = 1
    components.day = 15
    components.hour = 10
    components.minute = 30
    components.second = 45
    components.timeZone = TimeZone(secondsFromGMT: 0)
    let expectedCreatedAt = try #require(calendar.date(from: components))
    #expect(abs(workspace.createdAt.timeIntervalSince1970 - expectedCreatedAt.timeIntervalSince1970) < 1.0)
}

@Test func testWorkspaceStatusEnum() {
    #expect(WorkspaceStatus.pending.rawValue == "pending")
    #expect(WorkspaceStatus.starting.rawValue == "starting")
    #expect(WorkspaceStatus.running.rawValue == "running")
    #expect(WorkspaceStatus.stopping.rawValue == "stopping")
    #expect(WorkspaceStatus.stopped.rawValue == "stopped")
    #expect(WorkspaceStatus.failed.rawValue == "failed")
    #expect(WorkspaceStatus.canceling.rawValue == "canceling")
    #expect(WorkspaceStatus.deleting.rawValue == "deleting")
    #expect(WorkspaceStatus.deleted.rawValue == "deleted")
}

@Test func testWorkspaceStatusDecoding() throws {
    let statuses = ["pending", "starting", "running", "stopping", "stopped", "failed", "canceling", "deleting", "deleted"]

    for statusString in statuses {
        let jsonString = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "name": "test",
            "owner_name": "user",
            "template_name": "template",
            "status": "\(statusString)",
            "created_at": "2024-01-15T10:30:45.123Z",
            "updated_at": "2024-01-15T11:45:30.456Z"
        }
        """

        let jsonData = try #require(jsonString.data(using: .utf8))
        let workspace = try JSONDecoder().decode(Workspace.self, from: jsonData)
        #expect(workspace.status.rawValue == statusString)
    }
}

@Test func testWorkspaceEncoding() throws {
    let workspace = Workspace(
        id: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!,
        name: "my-workspace",
        ownerName: "alice",
        templateName: "kubernetes",
        status: .running,
        createdAt: Date(timeIntervalSince1970: 1705312245),
        updatedAt: Date(timeIntervalSince1970: 1705316730)
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(workspace)
    let decoded = try JSONDecoder().decode(Workspace.self, from: data)

    #expect(decoded.id == workspace.id)
    #expect(decoded.name == workspace.name)
    #expect(decoded.ownerName == workspace.ownerName)
    #expect(decoded.templateName == workspace.templateName)
    #expect(decoded.status == workspace.status)
}
