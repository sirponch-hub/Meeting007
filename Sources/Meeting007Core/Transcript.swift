import Foundation

public struct MeetingTranscript: Equatable, Sendable {
    public let meetingID: UUID
    private var segmentsByID: [UUID: TranscriptSegment]

    public init(meetingID: UUID, segments: [TranscriptSegment] = []) {
        self.meetingID = meetingID
        self.segmentsByID = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
    }

    public var segments: [TranscriptSegment] {
        segmentsByID.values.sorted {
            if $0.startTime == $1.startTime {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.startTime < $1.startTime
        }
    }

    public mutating func upsert(_ segment: TranscriptSegment) {
        precondition(segment.meetingID == meetingID, "Segment belongs to another meeting.")
        segmentsByID[segment.id] = segment
    }

    public func finalizedSegments() -> [TranscriptSegment] {
        segments.filter { $0.state == .final }
    }

    public func segments(endingAfter cutoff: TimeInterval) -> [TranscriptSegment] {
        segments.filter { $0.endTime >= cutoff }
    }

    public func plainText(includePartial: Bool = true) -> String {
        let source = includePartial ? segments : finalizedSegments()
        return source
            .map { "[\(TimestampFormatter.format($0.startTime))] \($0.speakerLabel): \($0.text)" }
            .joined(separator: "\n")
    }

    public func textForLast(seconds: TimeInterval, from currentTime: TimeInterval) -> String {
        let cutoff = max(0, currentTime - seconds)
        return segments(endingAfter: cutoff)
            .map { "[\(TimestampFormatter.format($0.startTime))] \($0.speakerLabel): \($0.text)" }
            .joined(separator: "\n")
    }
}

