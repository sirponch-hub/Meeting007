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

public enum WhisperKitTranscriptionPipelineFactory {
    public static func makeProductionPipeline(
        modelPathProvider: any LocalSTTModelPathProviding,
        configuration: WhisperKitAdapterConfiguration = WhisperKitAdapterConfiguration()
    ) -> LocalSTTPipeline {
        LocalSTTPipeline(transcriber: makeProductionTranscriber(
            modelPathProvider: modelPathProvider,
            configuration: configuration
        ))
    }

    public static func makeProductionTranscriber(
        modelPathProvider: any LocalSTTModelPathProviding,
        configuration: WhisperKitAdapterConfiguration = WhisperKitAdapterConfiguration()
    ) -> any SpeechTranscribing {
        WhisperKitSpeechTranscriber(
            modelPathProvider: modelPathProvider,
            configuration: configuration
        )
    }

    public static func makeProductionRollingPipeline(
        modelPathProvider: any LocalSTTModelPathProviding,
        configuration: WhisperKitRollingWindowConfiguration = WhisperKitRollingWindowConfiguration()
    ) -> RollingLocalTranscriptionPipeline {
        let transcriber = WhisperKitRollingWindowTranscriber(
            modelPathProvider: modelPathProvider,
            configuration: configuration,
            keepsEngineWarmAfterStop: true
        )
        return RollingLocalTranscriptionPipeline(
            decoder: transcriber,
            lifecycle: transcriber,
            initialWindowDuration: 3,
            windowDuration: 20
        )
    }
}

public protocol WhisperKitTranscriptionEngine: Sendable {
    func prepare() async throws
    func transcribe(_ chunk: SpeechChunk, language: String) async throws -> String
    func stop() async
}

public extension WhisperKitTranscriptionEngine {
    func prepare() async throws {}
    func stop() async {}
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

final class WhisperKitRuntimeBox: @unchecked Sendable {
    let whisperKit: WhisperKit

    init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }
}

public actor LocalWhisperKitTranscriptionEngine: WhisperKitTranscriptionEngine {
    private let modelFolder: String
    private var runtime: WhisperKitRuntimeBox?

    public init(modelFolder: String) {
        self.modelFolder = modelFolder
    }

    public func prepare() async throws {
        runtime = WhisperKitRuntimeBox(whisperKit: try await makeWhisperKit())
    }

    public func transcribe(_ chunk: SpeechChunk, language: String) async throws -> String {
        let whisperKit: WhisperKit
        if let runtime {
            whisperKit = runtime.whisperKit
        } else {
            let preparedRuntime = WhisperKitRuntimeBox(whisperKit: try await makeWhisperKit())
            runtime = preparedRuntime
            whisperKit = preparedRuntime.whisperKit
        }

        let decodeOptions = DecodingOptions(language: language)
        let results = await whisperKit.transcribeWithResults(
            audioArrays: [Array(chunk.samples)],
            decodeOptions: decodeOptions
        )

        let firstResult = try results.first?.get()
        return firstResult?.first?.text ?? ""
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

    public func stop() async {
        runtime = nil
    }
}

public actor WhisperKitSpeechTranscriber: SpeechTranscribing, TranscriptionFailureReporting {
    private let modelManager: any LocalSTTModelManaging
    private let modelPathProvider: (any LocalSTTModelPathProviding)?
    private let configuration: WhisperKitAdapterConfiguration
    private let fixedEngine: (any WhisperKitTranscriptionEngine)?
    private let engineFactory: (@Sendable (URL) -> any WhisperKitTranscriptionEngine)?
    private var activeEngine: (any WhisperKitTranscriptionEngine)?
    private var activeConfig: STTSessionConfig?
    private var downloadAttempts = 0
    private var runtimeFailure: TranscriptionFailure?

    public init(
        modelManager: any LocalSTTModelManaging,
        configuration: WhisperKitAdapterConfiguration = WhisperKitAdapterConfiguration(),
        engine: any WhisperKitTranscriptionEngine
    ) {
        self.modelManager = modelManager
        self.modelPathProvider = nil
        self.configuration = configuration
        self.fixedEngine = engine
        self.engineFactory = nil
    }

    public init(
        modelPathProvider: any LocalSTTModelPathProviding,
        configuration: WhisperKitAdapterConfiguration = WhisperKitAdapterConfiguration(),
        engineFactory: @escaping @Sendable (URL) -> any WhisperKitTranscriptionEngine = { modelDirectory in
            LocalWhisperKitTranscriptionEngine(modelFolder: modelDirectory.path)
        }
    ) {
        self.modelManager = modelPathProvider
        self.modelPathProvider = modelPathProvider
        self.configuration = configuration
        self.fixedEngine = nil
        self.engineFactory = engineFactory
    }

    public func start(config: STTSessionConfig) async -> TranscriptionStartResult {
        guard config.language == configuration.language else {
            activeConfig = nil
            let failure = TranscriptionFailure(
                code: "local_stt_language_unsupported",
                message: "The local WhisperKit adapter is configured for Russian transcription."
            )
            runtimeFailure = failure
            return .unavailable(failure)
        }

        if let modelPathProvider {
            let directory = await modelPathProvider.verifiedModelDirectory(for: configuration.modelPolicy)
            switch directory {
            case .ready(let modelDirectory):
                guard let engineFactory else {
                    activeConfig = nil
                    activeEngine = nil
                    let failure = TranscriptionFailure(
                        code: "local_stt_engine_unavailable",
                        message: "Local transcription could not start."
                    )
                    runtimeFailure = failure
                    return .unavailable(failure)
                }
                let engine = engineFactory(modelDirectory)
                do {
                    try await engine.prepare()
                    activeEngine = engine
                    activeConfig = config
                    runtimeFailure = nil
                    return .ready
                } catch {
                    activeEngine = nil
                    activeConfig = nil
                    let failure = TranscriptionFailure(
                        code: "local_stt_engine_unavailable",
                        message: "Local transcription could not start."
                    )
                    runtimeFailure = failure
                    return .unavailable(failure)
                }
            case .unavailable(let availability):
                activeEngine = nil
                activeConfig = nil
                let result = unavailableResult(for: availability)
                if case let .unavailable(failure) = result {
                    runtimeFailure = failure
                }
                return result
            }
        }

        let availability = await modelManager.availability(for: configuration.modelPolicy)
        switch availability {
        case .ready:
            do {
                try await fixedEngine?.prepare()
            } catch {
                activeConfig = nil
                activeEngine = nil
                let failure = TranscriptionFailure(
                    code: "local_stt_engine_unavailable",
                    message: "Local transcription could not start."
                )
                runtimeFailure = failure
                return .unavailable(failure)
            }
            activeEngine = fixedEngine
            activeConfig = config
            runtimeFailure = nil
            return .ready
        case .missing, .invalid, .downloading, .downloadFailed:
            activeEngine = nil
            activeConfig = nil
            let result = unavailableResult(for: availability)
            if case let .unavailable(failure) = result {
                runtimeFailure = failure
            }
            return result
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
            guard let activeEngine else {
                return []
            }
            let text = try await activeEngine.transcribe(chunk, language: activeConfig.language)
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
            runtimeFailure = TranscriptionFailure(
                code: "local_stt_runtime_failed",
                message: "Local transcription stopped unexpectedly."
            )
            return []
        }
    }

    public func stop(sessionID: UUID) async -> [TranscriptSegment] {
        guard activeConfig?.sessionID == sessionID else {
            return []
        }

        await activeEngine?.stop()
        activeEngine = nil
        activeConfig = nil
        return []
    }

    public func automaticDownloadAttempts() -> Int {
        downloadAttempts
    }

    public func lastFailure() -> TranscriptionFailure? {
        runtimeFailure
    }

    private func speakerLane(for lane: CaptureLane) -> SpeakerLane {
        switch lane {
        case .mic:
            return .me
        case .system:
            return .others
        }
    }

    private func unavailableResult(for availability: LocalSTTModelAvailability) -> TranscriptionStartResult {
        switch availability {
        case .ready:
            return .ready
        case .missing:
            return .unavailable(TranscriptionFailure(
                code: "local_stt_model_missing",
                message: "The Russian transcription model is not installed on this Mac."
            ))
        case .invalid:
            return .unavailable(TranscriptionFailure(
                code: "local_stt_model_invalid",
                message: "The Russian transcription model could not be verified. Download it again."
            ))
        case .downloading:
            return .unavailable(TranscriptionFailure(
                code: "local_stt_model_downloading",
                message: "The Russian transcription model is still downloading."
            ))
        case .downloadFailed:
            return .unavailable(TranscriptionFailure(
                code: "local_stt_model_download_failed",
                message: "The Russian transcription model download did not finish. Try again."
            ))
        }
    }
}
