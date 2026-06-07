import Foundation

public enum SpeakerLane: String, Codable, Equatable, Sendable {
    case me
    case others
}

public enum TranscriptSegmentState: String, Codable, Equatable, Sendable {
    case partial
    case final
}

public struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let meetingID: UUID
    public let lane: SpeakerLane
    public let state: TranscriptSegmentState
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let text: String

    public init(
        id: UUID = UUID(),
        meetingID: UUID,
        lane: SpeakerLane,
        state: TranscriptSegmentState,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String
    ) {
        precondition(endTime >= startTime, "Segment endTime must be greater than or equal to startTime.")
        self.id = id
        self.meetingID = meetingID
        self.lane = lane
        self.state = state
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }

    public var speakerLabel: String {
        switch lane {
        case .me:
            return "Me"
        case .others:
            return "Others"
        }
    }
}

