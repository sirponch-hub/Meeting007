import Foundation

public struct CompletedRecordingSession: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let session: RecordingSession
    public let transcript: MeetingTranscript
    public let note: String
    public let completedAt: Date
    public let isPrototypeOnly: Bool

    public init?(
        session: RecordingSession,
        transcript: MeetingTranscript,
        note: String = "",
        completedAt: Date = Date(),
        isPrototypeOnly: Bool = true
    ) {
        guard session.startedAt != nil, session.endedAt != nil, transcript.meetingID == session.id else {
            return nil
        }

        self.id = session.id
        self.session = session
        self.transcript = transcript
        self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        self.completedAt = completedAt
        self.isPrototypeOnly = isPrototypeOnly
    }

    public var title: String {
        session.title
    }

    public var primaryLanguage: String {
        session.primaryLanguage
    }

    public var startedAt: Date? {
        session.startedAt
    }

    public var endedAt: Date? {
        session.endedAt
    }

    public var duration: TimeInterval {
        guard let startedAt, let endedAt else {
            return 0
        }

        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    public var segmentCount: Int {
        transcript.segments.count
    }

    public var finalSegmentCount: Int {
        transcript.segments.filter { $0.state == .final }.count
    }

    public var partialSegmentCount: Int {
        transcript.segments.filter { $0.state == .partial }.count
    }

    public var stablePreviewText: String? {
        transcript.finalizedSegments().last?.text
    }
}

public protocol RecordingSessionStore: Sendable {
    func save(_ completedSession: CompletedRecordingSession) async
    func recentSessions(limit: Int) async -> [CompletedRecordingSession]
    func session(id: UUID) async -> CompletedRecordingSession?
}

public actor InMemoryRecordingSessionStore: RecordingSessionStore {
    private var sessionsByID: [UUID: CompletedRecordingSession] = [:]

    public init() {}

    public func save(_ completedSession: CompletedRecordingSession) async {
        sessionsByID[completedSession.id] = completedSession
    }

    public func recentSessions(limit: Int = 20) async -> [CompletedRecordingSession] {
        let sortedSessions = sessionsByID.values.sorted { first, second in
            first.sortDate > second.sortDate
        }

        guard limit >= 0 else {
            return sortedSessions
        }

        return Array(sortedSessions.prefix(limit))
    }

    public func session(id: UUID) async -> CompletedRecordingSession? {
        sessionsByID[id]
    }
}

private extension CompletedRecordingSession {
    var sortDate: Date {
        endedAt ?? completedAt
    }
}
