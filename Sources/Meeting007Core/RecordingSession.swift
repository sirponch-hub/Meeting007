import Foundation

public enum RecordingState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case stopping
    case stopped
    case failed(RecordingFailure)

    public var isRecording: Bool {
        if case .recording = self {
            return true
        }

        return false
    }
}

public struct RecordingFailure: Error, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct RecordingSession: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public let primaryLanguage: String
    public private(set) var startedAt: Date?
    public private(set) var endedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        primaryLanguage: String = "ru",
        startedAt: Date? = nil,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled meeting" : title
        self.primaryLanguage = primaryLanguage
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public mutating func markStarted(at date: Date) {
        startedAt = date
        endedAt = nil
    }

    public mutating func markEnded(at date: Date) {
        endedAt = date
    }

    public mutating func rename(to title: String) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled meeting" : title
    }
}

public protocol RecordingCaptureDriver: Sendable {
    func start(session: RecordingSession) async throws
    func stop(sessionID: UUID) async throws
}

public protocol MicrophoneCaptureDriver: Sendable {
    func start(session: RecordingSession, consumer: any AudioChunkConsumer) async throws
    func stop(sessionID: UUID) async throws
}

public struct NoopRecordingCaptureDriver: RecordingCaptureDriver {
    public init() {}

    public func start(session: RecordingSession) async throws {}

    public func stop(sessionID: UUID) async throws {}
}

public struct MicrophoneRecordingCaptureDriver: RecordingCaptureDriver {
    private let microphone: any MicrophoneCaptureDriver
    private let consumer: RuntimeOnlyAudioChunkConsumer
    private let lossResistantSession: LossResistantCaptureSession?

    public init(
        microphone: any MicrophoneCaptureDriver,
        consumer: RuntimeOnlyAudioChunkConsumer = RuntimeOnlyAudioChunkConsumer(),
        lossResistantSession: LossResistantCaptureSession? = nil
    ) {
        self.microphone = microphone
        self.consumer = consumer
        self.lossResistantSession = lossResistantSession
    }

    public func start(session: RecordingSession) async throws {
        if let lossResistantSession {
            try await lossResistantSession.begin(sessionID: session.id)
        } else {
            await consumer.begin(sessionID: session.id)
        }

        do {
            if let lossResistantSession {
                try await microphone.start(session: session, consumer: lossResistantSession)
            } else {
                try await microphone.start(session: session, consumer: consumer)
            }
        } catch {
            if let lossResistantSession {
                try? await lossResistantSession.close(sessionID: session.id)
                try? await lossResistantSession.cleanup(sessionID: session.id)
            } else {
                await consumer.end(sessionID: session.id)
            }
            throw error
        }
    }

    public func stop(sessionID: UUID) async throws {
        do {
            await lossResistantSession?.requestStop(sessionID: sessionID)
            try await microphone.stop(sessionID: sessionID)
            if let lossResistantSession {
                try await lossResistantSession.close(sessionID: sessionID)
            } else {
                await consumer.end(sessionID: sessionID)
            }
        } catch {
            if let lossResistantSession {
                try? await lossResistantSession.close(sessionID: sessionID)
            } else {
                await consumer.end(sessionID: sessionID)
            }
            throw error
        }
    }
}

public actor RecordingSessionController {
    public typealias Clock = () -> Date

    private let captureDriver: any RecordingCaptureDriver
    private let clock: Clock
    private var storage = Storage()

    public init(
        captureDriver: any RecordingCaptureDriver = NoopRecordingCaptureDriver(),
        clock: @escaping Clock = Date.init
    ) {
        self.captureDriver = captureDriver
        self.clock = clock
    }

    public func state() -> RecordingState {
        storage.state
    }

    public func currentSession() -> RecordingSession? {
        storage.session
    }

    @discardableResult
    public func startManualRecording(title: String) async -> RecordingState {
        let session: RecordingSession?
        switch storage.state {
        case .idle, .stopped, .failed:
            var newSession = RecordingSession(title: title)
            newSession.markStarted(at: clock())
            storage.session = newSession
            storage.state = .starting
            session = newSession
        case .starting, .recording, .stopping:
            session = nil
        }

        guard let session else {
            return storage.state
        }

        do {
            try await captureDriver.start(session: session)
            storage.state = .recording
            return storage.state
        } catch {
            let failure = normalize(error, fallbackCode: "recording_start_failed")
            storage.state = .failed(failure)
            return storage.state
        }
    }

    @discardableResult
    public func stopManualRecording() async -> RecordingState {
        guard let session = storage.session else {
            return storage.state
        }

        let sessionID: UUID?
        switch storage.state {
        case .recording:
            storage.state = .stopping
            sessionID = session.id
        case .idle, .starting, .stopping, .stopped, .failed:
            sessionID = nil
        }

        guard let sessionID else {
            return storage.state
        }

        do {
            try await captureDriver.stop(sessionID: sessionID)
            storage.session?.markEnded(at: clock())
            storage.state = .stopped
            return storage.state
        } catch {
            let failure = normalize(error, fallbackCode: "recording_stop_failed")
            storage.state = .failed(failure)
            return storage.state
        }
    }

    private func normalize(_ error: Error, fallbackCode: String) -> RecordingFailure {
        if let failure = error as? RecordingFailure {
            return failure
        }

        return RecordingFailure(code: fallbackCode, message: "Recording could not be completed. Please try again.")
    }

    private struct Storage {
        var state: RecordingState = .idle
        var session: RecordingSession?
    }
}
