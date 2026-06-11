import Foundation

public struct WhisperModelPolicy: Equatable, Sendable {
    public let modelID: String
    public let language: String
    public let approximateSizeInBytes: Int
    public let isDebugOnly: Bool

    public init(
        modelID: String,
        language: String,
        approximateSizeInBytes: Int,
        isDebugOnly: Bool
    ) {
        self.modelID = modelID
        self.language = language
        self.approximateSizeInBytes = approximateSizeInBytes
        self.isDebugOnly = isDebugOnly
    }

    public static let defaultRussian = WhisperModelPolicy(
        modelID: "large-v3-v20240930_626MB",
        language: "ru",
        approximateSizeInBytes: 626_000_000,
        isDebugOnly: false
    )

    public static let macOSTurboCandidate = WhisperModelPolicy(
        modelID: "large-v3-v20240930_turbo",
        language: "ru",
        approximateSizeInBytes: 1_600_000_000,
        isDebugOnly: false
    )

    public static let debugTiny = WhisperModelPolicy(
        modelID: "tiny",
        language: "ru",
        approximateSizeInBytes: 75_000_000,
        isDebugOnly: true
    )
}

public enum LocalSTTModelAvailability: Equatable, Sendable {
    case ready
    case missing
    case invalid(String)
    case downloading(progress: Double?)
    case downloadFailed(String)

    public var userFacingTitle: String {
        switch self {
        case .ready:
            return "Ready for offline transcription"
        case .missing:
            return "Model required"
        case .invalid:
            return "Model verification failed"
        case .downloading:
            return "Downloading model"
        case .downloadFailed:
            return "Download couldn't finish"
        }
    }
}

public protocol LocalSTTModelManaging: Sendable {
    func availability(for policy: WhisperModelPolicy) async -> LocalSTTModelAvailability
}

public struct LocalSTTModelInstallRequest: Equatable, Sendable {
    public let policy: WhisperModelPolicy
    public let consentGranted: Bool
    public let preparedLocalArtifactURL: URL?

    public init(
        policy: WhisperModelPolicy,
        consentGranted: Bool,
        preparedLocalArtifactURL: URL?
    ) {
        self.policy = policy
        self.consentGranted = consentGranted
        self.preparedLocalArtifactURL = preparedLocalArtifactURL
    }

    public var canInstall: Bool {
        consentGranted && preparedLocalArtifactURL != nil
    }
}

public actor FakeLocalSTTModelManager: LocalSTTModelManaging {
    private let availability: LocalSTTModelAvailability
    private var policies: [WhisperModelPolicy] = []

    public init(availability: LocalSTTModelAvailability) {
        self.availability = availability
    }

    public func availability(for policy: WhisperModelPolicy) async -> LocalSTTModelAvailability {
        policies.append(policy)
        return availability
    }

    public func requestedPolicies() -> [WhisperModelPolicy] {
        policies
    }
}

public actor ModelManagedSpeechTranscriber: SpeechTranscribing {
    private let modelManager: any LocalSTTModelManaging
    private let wrapped: any SpeechTranscribing
    private let policy: WhisperModelPolicy
    private var activeSessionID: UUID?

    public init(
        modelManager: any LocalSTTModelManaging,
        wrapped: any SpeechTranscribing,
        policy: WhisperModelPolicy = .defaultRussian
    ) {
        self.modelManager = modelManager
        self.wrapped = wrapped
        self.policy = policy
    }

    public func start(config: STTSessionConfig) async -> TranscriptionStartResult {
        let availability = await modelManager.availability(for: policy)
        switch availability {
        case .ready:
            let result = await wrapped.start(config: config)
            if result == .ready {
                activeSessionID = config.sessionID
            }
            return result
        case .missing:
            activeSessionID = nil
            return .unavailable(TranscriptionFailure(
                code: "local_stt_model_missing",
                message: "The Russian transcription model is not installed on this Mac."
            ))
        case .invalid:
            activeSessionID = nil
            return .unavailable(TranscriptionFailure(
                code: "local_stt_model_invalid",
                message: "The Russian transcription model could not be verified. Download it again."
            ))
        case .downloading:
            activeSessionID = nil
            return .unavailable(TranscriptionFailure(
                code: "local_stt_model_downloading",
                message: "The Russian transcription model is still downloading."
            ))
        case .downloadFailed:
            activeSessionID = nil
            return .unavailable(TranscriptionFailure(
                code: "local_stt_model_download_failed",
                message: "The Russian transcription model download did not finish. Try again."
            ))
        }
    }

    public func receive(_ chunk: CapturedAudioChunk) async -> [TranscriptSegment] {
        guard activeSessionID == chunk.sessionID else {
            return []
        }

        return await wrapped.receive(chunk)
    }

    public func stop(sessionID: UUID) async -> [TranscriptSegment] {
        guard activeSessionID == sessionID else {
            return []
        }

        activeSessionID = nil
        return await wrapped.stop(sessionID: sessionID)
    }
}
