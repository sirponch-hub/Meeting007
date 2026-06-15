import Foundation
import Meeting007Core
import WhisperKit

public struct WhisperKitRollingWindowConfiguration: Equatable, Sendable {
    public let language: String
    public let modelPolicy: WhisperModelPolicy

    public init(language: String = "ru", modelPolicy: WhisperModelPolicy = .defaultRussian) {
        self.language = language
        self.modelPolicy = modelPolicy
    }
}

public protocol WhisperKitRollingWindowEngine: Sendable {
    func prepare() async throws
    func transcribe(window: RollingAudioWindow, language: String, prompt: String) async throws -> RollingTranscriptionHypothesis
    func stop() async
}

public extension WhisperKitRollingWindowEngine {
    func prepare() async throws {}
    func stop() async {}
}

public actor WhisperKitRollingWindowTranscriber: RollingWindowTranscribing, TranscriptionFailureReporting {
    private let modelPathProvider: (any LocalSTTModelPathProviding)?
    private let configuration: WhisperKitRollingWindowConfiguration
    private let fixedEngine: (any WhisperKitRollingWindowEngine)?
    private let engineFactory: (@Sendable (URL) -> any WhisperKitRollingWindowEngine)?
    private var activeEngine: (any WhisperKitRollingWindowEngine)?
    private var runtimeFailure: TranscriptionFailure?

    public init(
        modelPathProvider: any LocalSTTModelPathProviding,
        configuration: WhisperKitRollingWindowConfiguration = WhisperKitRollingWindowConfiguration(),
        engineFactory: @escaping @Sendable (URL) -> any WhisperKitRollingWindowEngine = { modelDirectory in
            LocalWhisperKitRollingWindowEngine(modelFolder: modelDirectory.path)
        }
    ) {
        self.modelPathProvider = modelPathProvider
        self.configuration = configuration
        self.fixedEngine = nil
        self.engineFactory = engineFactory
    }

    public init(
        configuration: WhisperKitRollingWindowConfiguration = WhisperKitRollingWindowConfiguration(),
        engine: any WhisperKitRollingWindowEngine
    ) {
        self.modelPathProvider = nil
        self.configuration = configuration
        self.fixedEngine = engine
        self.engineFactory = nil
        self.activeEngine = engine
    }

    public func prepare() async -> TranscriptionStartResult {
        if let modelPathProvider {
            let directory = await modelPathProvider.verifiedModelDirectory(for: configuration.modelPolicy)
            switch directory {
            case .ready(let modelDirectory):
                guard let engineFactory else {
                    let failure = TranscriptionFailure(
                        code: "local_stt_engine_unavailable",
                        message: "Local rolling transcription could not start."
                    )
                    runtimeFailure = failure
                    return .unavailable(failure)
                }
                let engine = engineFactory(modelDirectory)
                do {
                    try await engine.prepare()
                    activeEngine = engine
                    runtimeFailure = nil
                    return .ready
                } catch {
                    let failure = TranscriptionFailure(
                        code: "local_stt_engine_unavailable",
                        message: "Local rolling transcription could not start."
                    )
                    runtimeFailure = failure
                    return .unavailable(failure)
                }
            case .unavailable(let availability):
                let failure = failure(for: availability)
                runtimeFailure = failure
                return .unavailable(failure)
            }
        }

        do {
            try await fixedEngine?.prepare()
            activeEngine = fixedEngine
            runtimeFailure = nil
            return .ready
        } catch {
            let failure = TranscriptionFailure(
                code: "local_stt_engine_unavailable",
                message: "Local rolling transcription could not start."
            )
            runtimeFailure = failure
            return .unavailable(failure)
        }
    }

    public func transcribe(window: RollingAudioWindow, prompt: String) async throws -> RollingTranscriptionHypothesis {
        guard let activeEngine else {
            let failure = TranscriptionFailure(
                code: "local_stt_engine_unavailable",
                message: "Local rolling transcription is not prepared."
            )
            runtimeFailure = failure
            throw failure
        }

        do {
            return try await activeEngine.transcribe(window: window, language: configuration.language, prompt: prompt)
        } catch {
            let failure = TranscriptionFailure(
                code: "local_stt_runtime_failed",
                message: "Local rolling transcription stopped unexpectedly."
            )
            runtimeFailure = failure
            throw failure
        }
    }

    public func stop() async {
        await activeEngine?.stop()
        activeEngine = nil
    }

    public func lastFailure() -> TranscriptionFailure? {
        runtimeFailure
    }

    private func failure(for availability: LocalSTTModelAvailability) -> TranscriptionFailure {
        switch availability {
        case .ready:
            return TranscriptionFailure(code: "local_stt_engine_unavailable", message: "Local rolling transcription could not start.")
        case .missing:
            return TranscriptionFailure(code: "local_stt_model_missing", message: "The Russian transcription model is not installed on this Mac.")
        case .invalid:
            return TranscriptionFailure(code: "local_stt_model_invalid", message: "The Russian transcription model could not be verified. Download it again.")
        case .downloading:
            return TranscriptionFailure(code: "local_stt_model_downloading", message: "The Russian transcription model is still downloading.")
        case .downloadFailed:
            return TranscriptionFailure(code: "local_stt_model_download_failed", message: "The Russian transcription model download did not finish. Try again.")
        }
    }
}

public actor LocalWhisperKitRollingWindowEngine: WhisperKitRollingWindowEngine {
    private let modelFolder: String
    private var runtime: WhisperKitRuntimeBox?

    public init(modelFolder: String) {
        self.modelFolder = modelFolder
    }

    public func prepare() async throws {
        runtime = WhisperKitRuntimeBox(whisperKit: try await makeWhisperKit())
    }

    public func transcribe(window: RollingAudioWindow, language: String, prompt: String) async throws -> RollingTranscriptionHypothesis {
        let whisperKit: WhisperKit
        if let runtime {
            whisperKit = runtime.whisperKit
        } else {
            let preparedRuntime = WhisperKitRuntimeBox(whisperKit: try await makeWhisperKit())
            runtime = preparedRuntime
            whisperKit = preparedRuntime.whisperKit
        }

        var options = DecodingOptions(language: language, wordTimestamps: true)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty, let tokenizer = whisperKit.tokenizer {
            options.promptTokens = tokenizer.encode(text: " " + trimmedPrompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.usePrefillPrompt = true
        }

        let results = await whisperKit.transcribeWithResults(
            audioArrays: [Array(window.samples)],
            decodeOptions: options
        )
        let firstResult = try results.first?.get()
        let text = firstResult?.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return RollingTranscriptionHypothesis(
            text: text,
            windowStartedAt: window.startedAt,
            windowEndedAt: window.startedAt + window.duration
        )
    }

    public func stop() async {
        runtime = nil
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
