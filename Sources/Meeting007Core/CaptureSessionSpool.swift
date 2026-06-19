import Foundation

public enum CaptureSessionSpoolState: String, Codable, Equatable, Sendable {
    case active
    case closed
}

public struct CaptureSpoolChunk: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let lane: CaptureLane
    public let sequence: Int
    public let sampleStart: Int
    public let sampleEnd: Int
    public let sampleRate: Double
    public let channelCount: Int
    public let byteCount: Int
    public let startedAt: TimeInterval
    public let duration: TimeInterval
    let byteStart: Int
    let byteEnd: Int
}

public struct CaptureSpoolSnapshot: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let state: CaptureSessionSpoolState
    public let chunks: [CaptureSpoolChunk]
}

public enum CaptureSessionSpoolError: Error, Equatable, Sendable {
    case sessionAlreadyActive
    case noActiveSession
    case wrongSession
    case sessionClosed
    case invalidAudio
    case backlogOverflow
    case storageFailure
    case corruptMetadata
}

public protocol CaptureSessionSpooling: Sendable {
    func begin(sessionID: UUID) async throws
    func append(_ chunk: CapturedAudioChunk) async throws -> CaptureSpoolChunk
    func close(sessionID: UUID) async throws
    func readSession(_ sessionID: UUID) async throws -> CaptureSpoolSnapshot
    func readSamples(for chunk: CaptureSpoolChunk) async throws -> RuntimeAudioSamples
    func cleanup(sessionID: UUID) async throws
}

public actor LocalCaptureSessionSpool: CaptureSessionSpooling {
    private struct SessionRecord: Codable {
        let sessionID: UUID
        var state: CaptureSessionSpoolState
    }

    private let rootURL: URL
    private let fileManager: FileManager
    private var activeSessionID: UUID?
    private var nextSequence = 0
    private var laneSampleOffsets: [CaptureLane: Int] = [:]

    public init(rootURL: URL = LocalCaptureSessionSpool.defaultRootURL(), fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    public static func defaultRootURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Meeting007", isDirectory: true)
            .appendingPathComponent("CaptureSpool", isDirectory: true)
    }

    public func begin(sessionID: UUID) throws {
        guard activeSessionID == nil else {
            throw CaptureSessionSpoolError.sessionAlreadyActive
        }

        do {
            try createPrivateDirectory(rootURL)
            let sessionURL = sessionURL(for: sessionID)
            guard !fileManager.fileExists(atPath: sessionURL.path) else {
                throw CaptureSessionSpoolError.sessionAlreadyActive
            }
            try createPrivateDirectory(sessionURL)
            try writeRecord(SessionRecord(sessionID: sessionID, state: .active), sessionID: sessionID)
            try createPrivateFile(laneURL(for: .mic, sessionID: sessionID))
            try createPrivateFile(laneURL(for: .system, sessionID: sessionID))
            try createPrivateFile(journalURL(for: sessionID))
            activeSessionID = sessionID
            nextSequence = 0
            laneSampleOffsets = [:]
        } catch let error as CaptureSessionSpoolError {
            throw error
        } catch {
            throw CaptureSessionSpoolError.storageFailure
        }
    }

    public func append(_ chunk: CapturedAudioChunk) throws -> CaptureSpoolChunk {
        guard let activeSessionID else {
            throw CaptureSessionSpoolError.noActiveSession
        }
        guard chunk.sessionID == activeSessionID else {
            throw CaptureSessionSpoolError.wrongSession
        }
        guard chunk.samples.sampleRate == chunk.sampleRate,
              chunk.samples.channelCount == chunk.channelCount,
              chunk.samples.frameCount > 0,
              chunk.samples.byteCount == chunk.byteCount else {
            throw CaptureSessionSpoolError.invalidAudio
        }

        let sampleStart = laneSampleOffsets[chunk.lane, default: 0]
        let sampleEnd = sampleStart + chunk.samples.frameCount
        let laneURL = laneURL(for: chunk.lane, sessionID: activeSessionID)

        do {
            let handle = try FileHandle(forWritingTo: laneURL)
            defer { try? handle.close() }
            let byteStart = Int(try handle.seekToEnd())
            let audioData = chunk.samples.samples.withUnsafeBufferPointer { Data(buffer: $0) }
            try handle.write(contentsOf: audioData)
            let byteEnd = byteStart + audioData.count
            let metadata = CaptureSpoolChunk(
                sessionID: activeSessionID,
                lane: chunk.lane,
                sequence: nextSequence,
                sampleStart: sampleStart,
                sampleEnd: sampleEnd,
                sampleRate: chunk.sampleRate,
                channelCount: chunk.channelCount,
                byteCount: chunk.byteCount,
                startedAt: chunk.startedAt,
                duration: chunk.duration,
                byteStart: byteStart,
                byteEnd: byteEnd
            )
            try appendJournal(metadata, sessionID: activeSessionID)
            nextSequence += 1
            laneSampleOffsets[chunk.lane] = sampleEnd
            return metadata
        } catch {
            throw CaptureSessionSpoolError.storageFailure
        }
    }

    public func close(sessionID: UUID) throws {
        guard let activeSessionID else {
            let snapshot = try readSession(sessionID)
            guard snapshot.state == .closed else {
                throw CaptureSessionSpoolError.noActiveSession
            }
            return
        }
        guard activeSessionID == sessionID else {
            throw CaptureSessionSpoolError.wrongSession
        }

        do {
            try writeRecord(SessionRecord(sessionID: sessionID, state: .closed), sessionID: sessionID)
            self.activeSessionID = nil
        } catch {
            throw CaptureSessionSpoolError.storageFailure
        }
    }

    public func readSession(_ sessionID: UUID) throws -> CaptureSpoolSnapshot {
        do {
            let recordData = try Data(contentsOf: recordURL(for: sessionID))
            let record = try JSONDecoder().decode(SessionRecord.self, from: recordData)
            guard record.sessionID == sessionID else {
                throw CaptureSessionSpoolError.corruptMetadata
            }
            let journalData = try Data(contentsOf: journalURL(for: sessionID))
            var committedLines = journalData.split(separator: 0x0A)
            if journalData.last != 0x0A, !committedLines.isEmpty {
                committedLines.removeLast()
            }
            let chunks = try committedLines.map {
                try JSONDecoder().decode(CaptureSpoolChunk.self, from: Data($0))
            }
            guard chunks.enumerated().allSatisfy({ $0.offset == $0.element.sequence && $0.element.sessionID == sessionID }) else {
                throw CaptureSessionSpoolError.corruptMetadata
            }
            return CaptureSpoolSnapshot(sessionID: sessionID, state: record.state, chunks: chunks)
        } catch let error as CaptureSessionSpoolError {
            throw error
        } catch {
            throw CaptureSessionSpoolError.corruptMetadata
        }
    }

    public func readSamples(for chunk: CaptureSpoolChunk) throws -> RuntimeAudioSamples {
        do {
            let handle = try FileHandle(forReadingFrom: laneURL(for: chunk.lane, sessionID: chunk.sessionID))
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(chunk.byteStart))
            guard let data = try handle.read(upToCount: chunk.byteEnd - chunk.byteStart),
                  data.count == chunk.byteCount,
                  data.count.isMultiple(of: MemoryLayout<Float>.size) else {
                throw CaptureSessionSpoolError.corruptMetadata
            }
            let samples = data.withUnsafeBytes { rawBuffer in
                Array(rawBuffer.bindMemory(to: Float.self))
            }
            return RuntimeAudioSamples(
                sampleRate: chunk.sampleRate,
                channelCount: chunk.channelCount,
                samples: samples
            )
        } catch let error as CaptureSessionSpoolError {
            throw error
        } catch {
            throw CaptureSessionSpoolError.storageFailure
        }
    }

    public func cleanup(sessionID: UUID) throws {
        guard activeSessionID != sessionID else {
            throw CaptureSessionSpoolError.sessionAlreadyActive
        }
        do {
            try fileManager.removeItem(at: sessionURL(for: sessionID))
        } catch {
            throw CaptureSessionSpoolError.storageFailure
        }
    }

    private func appendJournal(_ metadata: CaptureSpoolChunk, sessionID: UUID) throws {
        let handle = try FileHandle(forWritingTo: journalURL(for: sessionID))
        defer { try? handle.close() }
        try handle.seekToEnd()
        var data = try JSONEncoder().encode(metadata)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private func writeRecord(_ record: SessionRecord, sessionID: UUID) throws {
        let url = recordURL(for: sessionID)
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func createPrivateDirectory(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private func createPrivateFile(_ url: URL) throws {
        guard fileManager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CaptureSessionSpoolError.storageFailure
        }
    }

    private func sessionURL(for sessionID: UUID) -> URL {
        rootURL.appendingPathComponent(sessionID.uuidString.lowercased(), isDirectory: true)
    }

    private func recordURL(for sessionID: UUID) -> URL {
        sessionURL(for: sessionID).appendingPathComponent("session.json")
    }

    private func journalURL(for sessionID: UUID) -> URL {
        sessionURL(for: sessionID).appendingPathComponent("chunks.jsonl")
    }

    private func laneURL(for lane: CaptureLane, sessionID: UUID) -> URL {
        sessionURL(for: sessionID).appendingPathComponent("\(lane.rawValue).f32le")
    }
}
