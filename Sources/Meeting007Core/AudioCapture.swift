import Foundation

public enum CaptureLane: String, Codable, Equatable, Sendable {
    case mic
    case system
}

public enum MicrophoneCaptureStatus: Equatable, Sendable {
    case idle
    case requestingPermission
    case starting
    case listening(level: Double)
    case quiet
    case blocked
    case unavailable(String)
    case failed(String)

    public var userFacingLabel: String {
        switch self {
        case .idle:
            return "Me · Ready"
        case .requestingPermission:
            return "Me · Waiting for access"
        case .starting:
            return "Me · Starting"
        case .listening:
            return "Me · Listening"
        case .quiet:
            return "Me · Quiet"
        case .blocked:
            return "Me · Microphone blocked"
        case .unavailable:
            return "Me · Input unavailable"
        case .failed:
            return "Me · Capture stopped"
        }
    }

    public var level: Double {
        if case let .listening(level) = self {
            return min(max(level, 0), 1)
        }

        return 0
    }
}

public struct CapturedAudioChunk: Equatable, Sendable {
    public let sessionID: UUID
    public let lane: CaptureLane
    public let startedAt: TimeInterval
    public let duration: TimeInterval
    public let sampleRate: Double
    public let channelCount: Int
    public let byteCount: Int

    public init(
        sessionID: UUID,
        lane: CaptureLane,
        startedAt: TimeInterval,
        duration: TimeInterval,
        sampleRate: Double,
        channelCount: Int,
        byteCount: Int
    ) {
        self.sessionID = sessionID
        self.lane = lane
        self.startedAt = startedAt
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.byteCount = byteCount
    }
}

public protocol AudioChunkConsumer: Sendable {
    func receive(_ chunk: CapturedAudioChunk) async
}

public actor RuntimeOnlyAudioChunkConsumer: AudioChunkConsumer {
    private var activeSessionID: UUID?
    private var chunks: [CapturedAudioChunk] = []

    public init() {}

    public func begin(sessionID: UUID) {
        activeSessionID = sessionID
        chunks.removeAll()
    }

    public func end(sessionID: UUID) {
        guard activeSessionID == sessionID else {
            return
        }

        activeSessionID = nil
        chunks.removeAll()
    }

    public func receive(_ chunk: CapturedAudioChunk) async {
        guard activeSessionID == chunk.sessionID else {
            return
        }

        chunks.append(chunk)
    }

    public func capturedChunks() -> [CapturedAudioChunk] {
        chunks
    }
}
