import Foundation

public struct LiveTranscriptPreviewStep: Equatable, Sendable {
    public let segment: TranscriptSegment

    public init(segment: TranscriptSegment) {
        self.segment = segment
    }
}

public struct FakeLiveTranscriptPreviewScript: Equatable, Sendable {
    public let steps: [LiveTranscriptPreviewStep]

    public init(steps: [LiveTranscriptPreviewStep]) {
        self.steps = steps
    }

    public static func russianMeetingPreview(meetingID: UUID) -> FakeLiveTranscriptPreviewScript {
        let introID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let decisionID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let nextStepID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let localID = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!

        return FakeLiveTranscriptPreviewScript(steps: [
            LiveTranscriptPreviewStep(segment: TranscriptSegment(
                id: introID,
                meetingID: meetingID,
                lane: .me,
                state: .partial,
                startTime: 2,
                endTime: 5,
                text: "Давайте начнем с целей..."
            )),
            LiveTranscriptPreviewStep(segment: TranscriptSegment(
                id: introID,
                meetingID: meetingID,
                lane: .me,
                state: .final,
                startTime: 2,
                endTime: 7,
                text: "Давайте начнем с целей встречи и зафиксируем решения по каждому пункту."
            )),
            LiveTranscriptPreviewStep(segment: TranscriptSegment(
                id: decisionID,
                meetingID: meetingID,
                lane: .others,
                state: .final,
                startTime: 11,
                endTime: 17,
                text: "Согласен. Важно отдельно отметить открытые вопросы и владельцев задач."
            )),
            LiveTranscriptPreviewStep(segment: TranscriptSegment(
                id: nextStepID,
                meetingID: meetingID,
                lane: .me,
                state: .final,
                startTime: 21,
                endTime: 28,
                text: "Тогда первый шаг - проверить текущий сценарий записи и экспорт в Markdown."
            )),
            LiveTranscriptPreviewStep(segment: TranscriptSegment(
                id: localID,
                meetingID: meetingID,
                lane: .others,
                state: .partial,
                startTime: 32,
                endTime: 36,
                text: "Да, и нужно убедиться..."
            )),
            LiveTranscriptPreviewStep(segment: TranscriptSegment(
                id: localID,
                meetingID: meetingID,
                lane: .others,
                state: .final,
                startTime: 32,
                endTime: 39,
                text: "Да, и нужно убедиться, что текст остается локально на устройстве."
            ))
        ])
    }
}

public actor LiveTranscriptPreviewController {
    private var transcript: MeetingTranscript?
    private var steps: [LiveTranscriptPreviewStep] = []
    private var nextStepIndex = 0
    private var activeMeetingID: UUID?

    public init() {}

    public func start(meetingID: UUID, script: FakeLiveTranscriptPreviewScript? = nil) {
        activeMeetingID = meetingID
        transcript = MeetingTranscript(meetingID: meetingID)
        steps = (script ?? .russianMeetingPreview(meetingID: meetingID)).steps
        nextStepIndex = 0
    }

    public func stop() {
        activeMeetingID = nil
    }

    @discardableResult
    public func advance() -> [TranscriptSegment] {
        guard activeMeetingID != nil, nextStepIndex < steps.count else {
            return visibleSegments()
        }

        transcript?.upsert(steps[nextStepIndex].segment)
        nextStepIndex += 1
        return visibleSegments()
    }

    public func visibleSegments() -> [TranscriptSegment] {
        transcript?.segments ?? []
    }

    public func isActive() -> Bool {
        activeMeetingID != nil
    }
}

