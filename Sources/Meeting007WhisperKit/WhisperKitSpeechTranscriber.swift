import Foundation
import Meeting007Core
import WhisperKit

public struct WhisperKitAdapterConfiguration: Equatable, Sendable {
    public let modelPolicy: WhisperModelPolicy
    public let language: String
    public let allowsAutomaticModelDownload: Bool

    public init(
        modelPolicy: WhisperModelPolicy = .defaultRussian,
        language: String = "ru",
        allowsAutomaticModelDownload: Bool = false
    ) {
        self.modelPolicy = modelPolicy
        self.language = language
        self.allowsAutomaticModelDownload = allowsAutomaticModelDownload
    }
}

public enum WhisperKitDependencyProbe {
    public static func sdkTypeNames() -> [String] {
        [
            String(describing: WhisperKit.self),
            String(describing: WhisperKitConfig.self)
        ]
    }
}

public enum WhisperKitSpeechChunkValidator {
    public static func accepts(_ chunk: SpeechChunk) -> Bool {
        chunk.sampleRate == 16_000
            && !chunk.samples.isEmpty
            && chunk.duration > 0
    }
}

public protocol WhisperKitTranscriptionEngine: Sendable {
    func transcribe(_ chunk: SpeechChunk, language: String) async throws -> String
}

public struct FakeWhisperKitTranscriptionEngine: WhisperKitTranscriptionEngine {
    private let result: String

    public init(result: String) {
        self.result = result
    }

    public func transcribe(_ chunk: SpeechChunk, language: String) async throws -> String {
        result
    }
}

public struct LocalWhisperKitTranscriptionEngine: WhisperKitTranscriptionEngine {
    private let modelFolder: String

    public init(modelFolder: String) {
        self.modelFolder = modelFolder
    }

    public func transcribe(_ chunk: SpeechChunk, language: String) async throws -> String {
        let whisperKit = try await makeWhisperKit()
        let decodeOptions = DecodingOptions(language: language)
        let results = await whisperKit.transcribe(
            audioArrays: [Array(chunk.samples)],
            decodeOptions: decodeOptions
        )

        return results.first??.first?.text ?? ""
    }

    private func makeWhisperKit() async throws -> WhisperKit {
        let config = WhisperKitConfig(
            model: nil,
            modelFolder: modelFolder,
            verbose: false,
            prewarm: false,
            load: true,
            download: false
        )
        return try await WhisperKit(config)
    }
}

public actor WhisperKitSpeechTranscriber: SpeechTranscribing {
    private let modelManager: any LocalSTTModelManaging
    private let configuration: WhisperKitAdapterConfiguration
    private let engine: any WhisperKitTranscriptionEngine
    private var activeConfig: STTSessionConfig?
    private var downloadAttempts = 0

    public init(
        modelManager: any LocalSTTModelManaging,
        configuration: WhisperKitAdapterConfiguration = WhisperKitAdapterConfiguration(),
        engine: any WhisperKitTranscriptionEngine
    ) {
        self.modelManager = modelManager
        self.configuration = configuration
        self.engine = engine
    }

    public func start(config: STTSessionConfig) async -> TranscriptionStartResult {
        guard config.language == configuration.language else {
            activeConfig = nil
            return .unavailable(TranscriptionFailure(
                code: "local_stt_language_unsupported",
                message: "The local WhisperKit adapter is configured for Russian transcription."
            ))
        }

        let availability = await modelManager.availability(for: configuration.modelPolicy)
        switch availability {
        case .ready:
            activeConfig = config
            return .ready
        case .missing:
            activeConfig = nil
            return .unavailable(TranscriptionFailure(
                code: "local_stt_model_missing",
                message: "The Russian transcription model is not installed on this Mac."
            ))
        case .invalid:
            activeConfig = nil
            return .unavailable(TranscriptionFailure(
                code: "local_stt_model_invalid",
                message: "The Russian transcription model could not be verified. Download it again."
            ))
        case .downloading:
            activeConfig = nil
            return .unavailable(TranscriptionFailure(
                code: "local_stt_model_downloading",
                message: "The Russian transcription model is still downloading."
            ))
        case .downloadFailed:
            activeConfig = nil
            return .unavailable(TranscriptionFailure(
                code: "local_stt_model_download_failed",
                message: "The Russian transcription model download did not finish. Try again."
            ))
        }
    }

    public func receive(_ chunk: SpeechChunk) async -> [TranscriptSegment] {
        guard let activeConfig, activeConfig.sessionID == chunk.sessionID else {
            return []
        }

        guard WhisperKitSpeechChunkValidator.accepts(chunk) else {
            return []
        }

        do {
            let text = try await engine.transcribe(chunk, language: activeConfig.language)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return []
            }

            return [
                TranscriptSegment(
                    meetingID: chunk.sessionID,
                    lane: speakerLane(for: chunk.lane),
                    state: .final,
                    startTime: chunk.startedAt,
                    endTime: chunk.startedAt + chunk.duration,
                    text: text
                )
            ]
        } catch {
            return []
        }
    }

    public func stop(sessionID: UUID) async -> [TranscriptSegment] {
        guard activeConfig?.sessionID == sessionID else {
            return []
        }

        activeConfig = nil
        return []
    }

    public func automaticDownloadAttempts() -> Int {
        downloadAttempts
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
