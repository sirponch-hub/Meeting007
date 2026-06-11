import Foundation

public struct STTSessionConfig: Equatable, Sendable {
    public let sessionID: UUID
    public let language: String
    public let lane: CaptureLane

    public init(sessionID: UUID, language: String = "ru", lane: CaptureLane = .mic) {
        self.sessionID = sessionID
        self.language = language
        self.lane = lane
    }
}

public struct TranscriptionFailure: Error, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public enum TranscriptionStartResult: Equatable, Sendable {
    case ready
    case unavailable(TranscriptionFailure)
}

public enum LocalSTTModelState: Equatable, Sendable {
    case ready
    case missing
    case invalid
}

public protocol SpeechTranscribing: Sendable {
    func start(config: STTSessionConfig) async -> TranscriptionStartResult
    func receive(_ chunk: SpeechChunk) async -> [TranscriptSegment]
    func stop(sessionID: UUID) async -> [TranscriptSegment]
}

public actor LocalSTTPipeline: SpeechChunkConsumer {
    private let transcriber: any SpeechTranscribing
    private var activeSessionID: UUID?
    private var transcript: MeetingTranscript?

    public init(transcriber: any SpeechTranscribing) {
        self.transcriber = transcriber
    }

    @discardableResult
    public func start(_ config: STTSessionConfig) async -> TranscriptionStartResult {
        let result = await transcriber.start(config: config)
        guard result == .ready else {
            activeSessionID = nil
            transcript = nil
            return result
        }

        activeSessionID = config.sessionID
        transcript = MeetingTranscript(meetingID: config.sessionID)
        return result
    }

    @discardableResult
    public func receive(_ chunk: SpeechChunk) async -> [TranscriptSegment] {
        guard activeSessionID == chunk.sessionID else {
            return []
        }

        let updates = await transcriber.receive(chunk)
        for update in updates where update.meetingID == chunk.sessionID {
            transcript?.upsert(update)
        }

        return visibleSegments()
    }

    @discardableResult
    public func stop(sessionID: UUID) async -> [TranscriptSegment] {
        guard activeSessionID == sessionID else {
            return visibleSegments()
        }

        let finalUpdates = await transcriber.stop(sessionID: sessionID)
        for update in finalUpdates where update.meetingID == sessionID {
            transcript?.upsert(update)
        }

        activeSessionID = nil
        return visibleSegments()
    }

    public func visibleSegments() -> [TranscriptSegment] {
        transcript?.segments ?? []
    }
}

public actor FakeRussianSpeechTranscriber: SpeechTranscribing {
    private let modelState: LocalSTTModelState
    private var activeConfig: STTSessionConfig?
    private var updateCount = 0
    private var segmentID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!

    public init(modelState: LocalSTTModelState = .ready) {
        self.modelState = modelState
    }

    public func start(config: STTSessionConfig) async -> TranscriptionStartResult {
        guard modelState == .ready else {
            return .unavailable(TranscriptionFailure(
                code: "local_stt_model_missing",
                message: "The Russian speech model is not installed on this Mac."
            ))
        }

        activeConfig = config
        updateCount = 0
        segmentID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        return .ready
    }

    public func receive(_ chunk: SpeechChunk) async -> [TranscriptSegment] {
        guard let activeConfig, activeConfig.sessionID == chunk.sessionID else {
            return []
        }

        updateCount += 1
        let state: TranscriptSegmentState = updateCount == 1 ? .partial : .final
        let text = updateCount == 1
            ? "Это локальная русская транскрибация..."
            : "Это локальная русская транскрибация."

        return [
            TranscriptSegment(
                id: segmentID,
                meetingID: chunk.sessionID,
                lane: speakerLane(for: chunk.lane),
                state: state,
                startTime: 0,
                endTime: chunk.startedAt + chunk.duration,
                text: text
            )
        ]
    }

    public func stop(sessionID: UUID) async -> [TranscriptSegment] {
        guard activeConfig?.sessionID == sessionID else {
            return []
        }

        activeConfig = nil
        return []
    }

    private func speakerLane(for lane: CaptureLane) -> SpeakerLane {
        switch lane {
        case .mic:
            return .me
        case .system:
            return .others
        }
    }
}
