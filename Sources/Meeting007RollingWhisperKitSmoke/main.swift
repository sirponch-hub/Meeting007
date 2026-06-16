import Foundation
import Meeting007Core
import Meeting007WhisperKit
import WhisperKit

@main
struct Meeting007RollingWhisperKitSmoke {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let audioPath = arguments.first(where: { !$0.hasPrefix("--") }) else {
            print("Usage: swift run Meeting007RollingWhisperKitSmoke /path/to/russian-audio.wav [--model-folder /path/to/model] [--expected-text '...'] [--expected-text-file /path/to/text.txt]")
            print("The command prints a local-only rolling-vs-batch comparison and does not save audio or transcript files.")
            return
        }

        let modelFolder = try await resolveModelFolder(from: arguments)
        let expectedText = try expectedText(from: arguments)
        let audioBuffer = try AudioProcessor.loadAudio(fromPath: audioPath)
        let samples = AudioProcessor.convertBufferToArray(buffer: audioBuffer)
        guard !samples.isEmpty else {
            print("Audio file has no decodable samples.")
            return
        }

        print("Meeting007 rolling WhisperKit smoke")
        print("Audio: \(audioPath)")
        print("Model: \(modelFolder.path)")
        print("Samples: \(samples.count)")
        print("")

        let rollingText = try await runRolling(samples: samples, modelFolder: modelFolder)
        print("")
        let batchText = try await runBatch(samples: samples, modelFolder: modelFolder)

        if let expectedText {
            print("")
            printQualityEvaluation(label: "Rolling", expected: expectedText, recognized: rollingText)
            printQualityEvaluation(label: "Batch", expected: expectedText, recognized: batchText)
        }
    }

    private static func resolveModelFolder(from arguments: [String]) async throws -> URL {
        if let index = arguments.firstIndex(of: "--model-folder"), arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }

        let store = LocalSTTModelStore()
        switch await store.verifiedModelDirectory(for: .defaultRussian) {
        case .ready(let url):
            return url
        case .unavailable(let availability):
            throw SmokeError("Verified Russian model is not ready: \(availability.userFacingTitle)")
        }
    }

    private static func expectedText(from arguments: [String]) throws -> String? {
        if let index = arguments.firstIndex(of: "--expected-text-file"), arguments.indices.contains(index + 1) {
            return try String(
                contentsOf: URL(fileURLWithPath: arguments[index + 1]),
                encoding: .utf8
            )
        }

        if let index = arguments.firstIndex(of: "--expected-text"), arguments.indices.contains(index + 1) {
            return arguments[index + 1]
        }

        return nil
    }

    private static func runRolling(samples: [Float], modelFolder: URL) async throws -> String {
        let rollingEngine = LocalWhisperKitRollingWindowEngine(modelFolder: modelFolder.path)
        let rollingDecoder = WhisperKitRollingWindowTranscriber(engine: rollingEngine)
        let start = await rollingDecoder.prepare()
        guard start == .ready else {
            throw SmokeError("Rolling decoder could not start: \(start)")
        }

        let sessionID = UUID()
        let session = RollingStreamingTranscriptionSession(
            sessionID: sessionID,
            bufferDuration: 30,
            windowDuration: 20,
            decoder: rollingDecoder
        )

        print("== Rolling window every 1s ==")
        let sampleRate = RuntimeAudioFrameNormalizer.defaultTargetSampleRate
        let stepSampleCount = Int(sampleRate)
        var offset = 0
        var lastPrintedUpdate = StreamingTranscriptUpdate(committedText: "", partialText: "")
        var tickIndex = 0

        while offset < samples.count {
            let end = min(offset + stepSampleCount, samples.count)
            let chunkSamples = Array(samples[offset..<end])
            let startedAt = Double(offset) / sampleRate
            let duration = Double(end - offset) / sampleRate
            await session.receive(CapturedAudioChunk(
                sessionID: sessionID,
                lane: .mic,
                startedAt: startedAt,
                duration: duration,
                sampleRate: sampleRate,
                channelCount: 1,
                byteCount: chunkSamples.count * MemoryLayout<Float>.size,
                samples: RuntimeAudioSamples(sampleRate: sampleRate, channelCount: 1, samples: chunkSamples)
            ))

            let update = try await session.tick()
            if update != lastPrintedUpdate {
                print(String(format: "[rolling %05.1fs] committed: %@", startedAt + duration, update.committedText))
                if !update.partialText.isEmpty {
                    print(String(format: "[rolling %05.1fs] partial: %@", startedAt + duration, update.partialText))
                }
                lastPrintedUpdate = update
            }

            tickIndex += 1
            offset = end
        }

        let finalUpdate = await session.finalizeBestEffortDraft()
        print("[rolling final] committed: \(finalUpdate.committedText)")
        if !finalUpdate.partialText.isEmpty {
            print("[rolling final] partial: \(finalUpdate.partialText)")
        }
        await rollingDecoder.stop()
        await session.stop()
        _ = tickIndex
        return finalUpdate.visibleText
    }

    private static func runBatch(samples: [Float], modelFolder: URL) async throws -> String {
        let batchEngine = LocalWhisperKitTranscriptionEngine(modelFolder: modelFolder.path)
        try await batchEngine.prepare()

        print("== Batch 5s chunks ==")
        let sampleRate = RuntimeAudioFrameNormalizer.defaultTargetSampleRate
        let chunkSampleCount = Int(sampleRate * 5)
        let sessionID = UUID()
        var offset = 0
        var transcript: [String] = []

        while offset < samples.count {
            let end = min(offset + chunkSampleCount, samples.count)
            let startedAt = Double(offset) / sampleRate
            let duration = Double(end - offset) / sampleRate
            let speechChunk = SpeechChunk(
                sessionID: sessionID,
                lane: .mic,
                startedAt: startedAt,
                duration: duration,
                sampleRate: sampleRate,
                samples: ContiguousArray(samples[offset..<end])
            )
            let text = try await batchEngine.transcribe(speechChunk, language: "ru")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            print(String(format: "[batch %05.1f-%05.1fs] %@", startedAt, startedAt + duration, text))
            if !text.isEmpty {
                transcript.append(text)
            }
            offset = end
        }

        await batchEngine.stop()
        return transcript.joined(separator: " ")
    }

    private static func printQualityEvaluation(label: String, expected: String, recognized: String) {
        let evaluation = TranscriptQualityEvaluation.evaluate(expected: expected, recognized: recognized)
        let passesRecommendedSmoke = evaluation.wordErrorRate <= 0.30 && evaluation.characterErrorRate <= 0.15
        print("== \(label) quality vs expected text ==")
        print("Recommended threshold: \(passesRecommendedSmoke ? "PASS" : "REVIEW")")
        print(String(format: "WER: %.3f", evaluation.wordErrorRate))
        print(String(format: "CER: %.3f", evaluation.characterErrorRate))
        print(String(format: "Recall: %.3f", evaluation.recall))
        print(String(format: "Precision: %.3f", evaluation.precision))
        print("Matched expected words: \(evaluation.matchedExpectedWordCount)/\(evaluation.expectedWordCount)")
        print("Recognized words: \(evaluation.recognizedWordCount)")
        if evaluation.missingExpectedWords.isEmpty {
            print("Missing expected words sample: none")
        } else {
            print("Missing expected words sample: \(evaluation.missingExpectedWords.joined(separator: ", "))")
        }
        print("Privacy: expected text and audio are external inputs and were not written by this command.")
    }
}

private struct SmokeError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
