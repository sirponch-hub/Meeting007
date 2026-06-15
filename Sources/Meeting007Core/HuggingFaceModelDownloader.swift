import CryptoKit
import Foundation

public struct HuggingFaceWhisperModelPolicy: Equatable, Sendable {
    public let repositoryID: String
    public let revision: String
    public let folderName: String
    public let requiredEntries: [String]

    public init(
        repositoryID: String,
        revision: String,
        folderName: String,
        requiredEntries: [String]
    ) {
        self.repositoryID = repositoryID
        self.revision = revision
        self.folderName = folderName
        self.requiredEntries = requiredEntries
    }

    public static let defaultRussian = HuggingFaceWhisperModelPolicy(
        repositoryID: "argmaxinc/whisperkit-coreml",
        revision: "7235bbd",
        folderName: "openai_whisper-large-v3-v20240930_626MB",
        requiredEntries: [
            "AudioEncoder.mlmodelc",
            "MelSpectrogram.mlmodelc",
            "TextDecoder.mlmodelc",
            "config.json",
            "generation_config.json"
        ]
    )
}

public struct RemoteModelFile: Equatable, Sendable {
    public let path: String
    public let size: Int64
    public let sha256: String?
    public let downloadURL: URL

    public init(path: String, size: Int64, sha256: String?, downloadURL: URL) {
        self.path = path
        self.size = size
        self.sha256 = sha256
        self.downloadURL = downloadURL
    }
}

public protocol HuggingFaceModelRepository: Sendable {
    func listFiles(for policy: HuggingFaceWhisperModelPolicy) async throws -> [RemoteModelFile]
}

public protocol ModelFileFetching: Sendable {
    func download(
        _ file: RemoteModelFile,
        to destinationURL: URL,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws
}

public struct HuggingFaceModelDownloader: ModelDownloading {
    private let modelPolicy: HuggingFaceWhisperModelPolicy
    private let repository: any HuggingFaceModelRepository
    private let fileFetcher: any ModelFileFetching

    public init(
        modelPolicy: HuggingFaceWhisperModelPolicy = .defaultRussian,
        repository: any HuggingFaceModelRepository = URLSessionHuggingFaceModelRepository(),
        fileFetcher: any ModelFileFetching = URLSessionModelFileFetcher()
    ) {
        self.modelPolicy = modelPolicy
        self.repository = repository
        self.fileFetcher = fileFetcher
    }

    public func download(
        _ request: ModelDownloadRequest,
        progress: @escaping @Sendable (ModelDownloadProgress) async -> Void
    ) async throws -> DownloadedModelArtifact {
        try Task.checkCancellation()
        await progress(ModelDownloadProgress(
            phase: .preparing,
            downloadedBytes: 0,
            expectedBytes: Int64(request.expectedBytes)
        ))

        let remoteFiles = try await repository.listFiles(for: modelPolicy)
        let selectedFiles = try validate(remoteFiles, for: modelPolicy)
        let expectedBytes = selectedFiles.reduce(Int64(0)) { $0 + $1.size }
        let stagingDirectory = stagingDirectory(for: request)
        try prepareStagingDirectory(stagingDirectory)

        do {
            let progressAccumulator = ModelDownloadProgressAccumulator()
            var manifests: [DownloadedModelFileManifest] = []

            for file in selectedFiles {
                try Task.checkCancellation()
                let relativePath = relativeModelPath(for: file.path)
                guard LocalModelPathValidator.isSafeRelativePath(relativePath) else {
                    throw ModelInstallFailure.unsupportedRepositoryLayout
                }

                let destinationURL = stagingDirectory.appendingPathComponent(relativePath, isDirectory: false)
                try FileManager.default.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let priorDownloadedBytes = await progressAccumulator.completedBytes()
                try await fileFetcher.download(file, to: destinationURL) { fileProgress in
                    await progress(ModelDownloadProgress(
                        phase: .downloading,
                        downloadedBytes: priorDownloadedBytes + fileProgress,
                        expectedBytes: expectedBytes
                    ))
                }

                let fileSize = try localFileSize(at: destinationURL)
                guard fileSize == file.size else {
                    throw ModelInstallFailure.verificationFailed
                }
                let checksum = try LocalModelChecksum.sha256Hex(for: destinationURL)
                if let expectedChecksum = file.sha256, expectedChecksum.lowercased() != checksum {
                    throw ModelInstallFailure.verificationFailed
                }
                manifests.append(DownloadedModelFileManifest(
                    path: relativePath,
                    size: fileSize,
                    sha256: checksum
                ))
                await progressAccumulator.addCompletedBytes(fileSize)
            }

            let downloadedBytes = await progressAccumulator.completedBytes()
            await progress(ModelDownloadProgress(
                phase: .verifying,
                downloadedBytes: downloadedBytes,
                expectedBytes: expectedBytes
            ))
            return DownloadedModelArtifact(
                policy: request.policy,
                localURL: stagingDirectory,
                repositoryID: modelPolicy.repositoryID,
                revision: modelPolicy.revision,
                folderName: modelPolicy.folderName,
                actualBytes: manifests.reduce(Int64(0)) { $0 + $1.size },
                files: manifests.sorted { $0.path < $1.path }
            )
        } catch {
            try? FileManager.default.removeItem(at: stagingDirectory)
            if error is CancellationError {
                throw ModelInstallFailure.cancelled
            }
            throw error
        }
    }

    public func cancel(requestID: UUID) async {}

    private func validate(
        _ files: [RemoteModelFile],
        for policy: HuggingFaceWhisperModelPolicy
    ) throws -> [RemoteModelFile] {
        let prefix = policy.folderName + "/"
        let modelFiles = files
            .filter { $0.path.hasPrefix(prefix) }
            .filter { LocalModelPathValidator.isSafeRelativePath($0.path) }
            .sorted { $0.path < $1.path }

        guard !modelFiles.isEmpty else {
            throw ModelInstallFailure.unsupportedRepositoryLayout
        }

        for requiredEntry in policy.requiredEntries {
            let requiredPath = prefix + requiredEntry
            let isPresent: Bool
            if requiredEntry.hasSuffix(".mlmodelc") {
                isPresent = modelFiles.contains { $0.path.hasPrefix(requiredPath + "/") }
            } else {
                isPresent = modelFiles.contains { $0.path == requiredPath }
            }
            guard isPresent else {
                throw ModelInstallFailure.unsupportedRepositoryLayout
            }
        }

        return modelFiles
    }

    private func stagingDirectory(for request: ModelDownloadRequest) -> URL {
        request.destinationDirectory
            .deletingLastPathComponent()
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent(request.id.uuidString, isDirectory: true)
    }

    private func prepareStagingDirectory(_ directory: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func relativeModelPath(for remotePath: String) -> String {
        String(remotePath.dropFirst(modelPolicy.folderName.count + 1))
    }

    private func localFileSize(at fileURL: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw ModelInstallFailure.verificationFailed
        }
        return size.int64Value
    }
}

private actor ModelDownloadProgressAccumulator {
    private var bytes: Int64 = 0

    func completedBytes() -> Int64 {
        bytes
    }

    func addCompletedBytes(_ completedBytes: Int64) {
        bytes += completedBytes
    }
}

public struct URLSessionHuggingFaceModelRepository: HuggingFaceModelRepository {
    private let endpoint: URL
    private let session: URLSession

    public init(
        endpoint: URL = URL(string: "https://huggingface.co")!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    public func listFiles(for policy: HuggingFaceWhisperModelPolicy) async throws -> [RemoteModelFile] {
        guard let url = URL(string: "\(endpoint.absoluteString)/api/models/\(policy.repositoryID)?revision=\(policy.revision)&blobs=true") else {
            throw ModelInstallFailure.downloadSourceUnavailable
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw ModelInstallFailure.networkUnavailable
            }
            let modelInfo = try JSONDecoder().decode(HuggingFaceModelInfoResponse.self, from: data)
            return modelInfo.siblings.compactMap { sibling in
                guard let size = sibling.lfs?.size ?? sibling.size else {
                    return nil
                }
                return RemoteModelFile(
                    path: sibling.rfilename,
                    size: size,
                    sha256: sibling.lfs?.oid,
                    downloadURL: resolveURL(
                        repositoryID: policy.repositoryID,
                        revision: policy.revision,
                        filePath: sibling.rfilename
                    )
                )
            }
        } catch let failure as ModelInstallFailure {
            throw failure
        } catch {
            throw ModelInstallFailure.networkUnavailable
        }
    }

    private func resolveURL(repositoryID: String, revision: String, filePath: String) -> URL {
        let escapedPath = filePath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return URL(string: "\(endpoint.absoluteString)/\(repositoryID)/resolve/\(revision)/\(escapedPath)")!
    }
}

public struct URLSessionModelFileFetcher: ModelFileFetching {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func download(
        _ file: RemoteModelFile,
        to destinationURL: URL,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws {
        do {
            let (bytes, response) = try await session.bytes(from: file.downloadURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw ModelInstallFailure.networkUnavailable
            }
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            fileManager.createFile(atPath: destinationURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: destinationURL)
            defer {
                try? handle.close()
            }

            var downloadedBytes: Int64 = 0
            var buffer = Data()
            buffer.reserveCapacity(1_048_576)
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 1_048_576 {
                    try handle.write(contentsOf: buffer)
                    downloadedBytes += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    await progress(downloadedBytes)
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                downloadedBytes += Int64(buffer.count)
                await progress(downloadedBytes)
            }
            if downloadedBytes == 0 {
                await progress(0)
            }
        } catch let failure as ModelInstallFailure {
            throw failure
        } catch is CancellationError {
            throw ModelInstallFailure.cancelled
        } catch {
            throw ModelInstallFailure.networkUnavailable
        }
    }
}

private struct HuggingFaceModelInfoResponse: Decodable {
    let siblings: [Sibling]

    struct Sibling: Decodable {
        let rfilename: String
        let size: Int64?
        let lfs: LFS?
    }

    struct LFS: Decodable {
        let oid: String?
        let size: Int64?
    }
}
