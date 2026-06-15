import CryptoKit
import Foundation

public struct ModelDownloadProgress: Equatable, Sendable {
    public enum Phase: String, Equatable, Sendable {
        case preparing
        case downloading
        case verifying
        case installing
    }

    public let phase: Phase
    public let downloadedBytes: Int64
    public let expectedBytes: Int64?

    public init(phase: Phase, downloadedBytes: Int64 = 0, expectedBytes: Int64? = nil) {
        self.phase = phase
        self.downloadedBytes = downloadedBytes
        self.expectedBytes = expectedBytes
    }

    public var fractionCompleted: Double? {
        guard let expectedBytes, expectedBytes > 0 else {
            return nil
        }

        return min(max(Double(downloadedBytes) / Double(expectedBytes), 0), 1)
    }
}

public enum ModelInstallFailure: Error, Equatable, Sendable {
    case downloadSourceUnavailable
    case networkUnavailable
    case cancelled
    case insufficientDiskSpace
    case verificationFailed
    case unsupportedRepositoryLayout
    case fileSystemPermissionDenied
    case unknown

    public var userFacingMessage: String {
        switch self {
        case .downloadSourceUnavailable:
            return "The model download source is not configured yet."
        case .networkUnavailable:
            return "The network connection was interrupted."
        case .cancelled:
            return "Installation was cancelled."
        case .insufficientDiskSpace:
            return "There is not enough free disk space to install the model."
        case .verificationFailed:
            return "The downloaded model could not be verified."
        case .unsupportedRepositoryLayout:
            return "The model source is not in a supported format."
        case .fileSystemPermissionDenied:
            return "Meeting007 could not write to local model storage."
        case .unknown:
            return "The model could not be installed. Try again."
        }
    }
}

public enum LocalSTTModelInstallState: Equatable, Sendable {
    case notInstalled
    case awaitingConsent(WhisperModelPolicy)
    case downloading(ModelDownloadProgress)
    case verifying
    case ready(URL)
    case failed(ModelInstallFailure)
}

public struct ModelDownloadRequest: Equatable, Sendable {
    public let id: UUID
    public let policy: WhisperModelPolicy
    public let destinationDirectory: URL
    public let expectedBytes: Int

    public init(
        id: UUID = UUID(),
        policy: WhisperModelPolicy,
        destinationDirectory: URL,
        expectedBytes: Int
    ) {
        self.id = id
        self.policy = policy
        self.destinationDirectory = destinationDirectory
        self.expectedBytes = expectedBytes
    }
}

public struct DownloadedModelArtifact: Equatable, Sendable {
    public let policy: WhisperModelPolicy
    public let localURL: URL
    public let repositoryID: String?
    public let revision: String?
    public let folderName: String?
    public let actualBytes: Int64
    public let files: [DownloadedModelFileManifest]

    public init(
        policy: WhisperModelPolicy,
        localURL: URL,
        repositoryID: String? = nil,
        revision: String? = nil,
        folderName: String? = nil,
        actualBytes: Int64 = 0,
        files: [DownloadedModelFileManifest] = []
    ) {
        self.policy = policy
        self.localURL = localURL
        self.repositoryID = repositoryID
        self.revision = revision
        self.folderName = folderName
        self.actualBytes = actualBytes
        self.files = files
    }
}

public struct DownloadedModelFileManifest: Codable, Equatable, Sendable {
    public let path: String
    public let size: Int64
    public let sha256: String

    public init(path: String, size: Int64, sha256: String) {
        self.path = path
        self.size = size
        self.sha256 = sha256
    }
}

public protocol ModelDownloading: Sendable {
    func download(
        _ request: ModelDownloadRequest,
        progress: @escaping @Sendable (ModelDownloadProgress) async -> Void
    ) async throws -> DownloadedModelArtifact

    func cancel(requestID: UUID) async
}

public struct UnconfiguredModelDownloader: ModelDownloading {
    public init() {}

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
        throw ModelInstallFailure.downloadSourceUnavailable
    }

    public func cancel(requestID: UUID) async {}
}

public actor FakeModelDownloader: ModelDownloading {
    private let result: Result<DownloadedModelArtifact, ModelInstallFailure>
    private let progressUpdates: [ModelDownloadProgress]
    private var requests: [ModelDownloadRequest] = []
    private var cancelledRequestIDs: [UUID] = []

    public init(
        result: Result<DownloadedModelArtifact, ModelInstallFailure>,
        progressUpdates: [ModelDownloadProgress] = []
    ) {
        self.result = result
        self.progressUpdates = progressUpdates
    }

    public func download(
        _ request: ModelDownloadRequest,
        progress: @escaping @Sendable (ModelDownloadProgress) async -> Void
    ) async throws -> DownloadedModelArtifact {
        requests.append(request)
        for update in progressUpdates {
            await progress(update)
        }
        return try result.get()
    }

    public func cancel(requestID: UUID) async {
        cancelledRequestIDs.append(requestID)
    }

    public func downloadRequests() -> [ModelDownloadRequest] {
        requests
    }

    public func cancelledRequests() -> [UUID] {
        cancelledRequestIDs
    }
}

public actor LocalSTTModelStore: LocalSTTModelManaging {
    private let rootDirectory: URL
    private let fileManager: FileManager

    public init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory ?? Self.defaultRootDirectory(fileManager: fileManager)
        self.fileManager = fileManager
    }

    public static func defaultRootDirectory(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("Meeting007", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("whisper", isDirectory: true)
    }

    public func availability(for policy: WhisperModelPolicy) async -> LocalSTTModelAvailability {
        let markerURL = installMarkerURL(for: policy)
        guard fileManager.fileExists(atPath: markerURL.path) else {
            return .missing
        }

        do {
            let data = try Data(contentsOf: markerURL)
            let marker = try JSONDecoder.meeting007Decoder.decode(LocalSTTModelInstallMarker.self, from: data)
            guard marker.matches(policy) else {
                return .invalid("Installed model marker does not match the requested Russian model policy.")
            }
            guard marker.hasVerifiedManifest else {
                return .invalid("Installed model marker does not include a verified local manifest.")
            }
            guard verifyInstalledFiles(marker.files, for: policy) else {
                return .invalid("Installed model files could not be verified.")
            }
            return .ready
        } catch {
            return .invalid("Installed model marker could not be verified.")
        }
    }

    public func modelDirectory(for policy: WhisperModelPolicy) -> URL {
        rootDirectory.appendingPathComponent(policy.modelID, isDirectory: true)
    }

    public func markInstalled(_ artifact: DownloadedModelArtifact) throws -> URL {
        let modelDirectory = modelDirectory(for: artifact.policy)
        do {
            try fileManager.createDirectory(
                at: modelDirectory.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if artifact.localURL.standardizedFileURL != modelDirectory.standardizedFileURL {
                if fileManager.fileExists(atPath: modelDirectory.path) {
                    try fileManager.removeItem(at: modelDirectory)
                }
                if fileManager.fileExists(atPath: artifact.localURL.path) {
                    try fileManager.moveItem(at: artifact.localURL, to: modelDirectory)
                } else {
                    try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
                }
            } else {
                try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            }
            let marker = LocalSTTModelInstallMarker(
                policyID: artifact.policy.modelID,
                language: artifact.policy.language,
                expectedBytes: artifact.policy.approximateSizeInBytes,
                actualBytes: artifact.actualBytes,
                repositoryID: artifact.repositoryID,
                revision: artifact.revision,
                folderName: artifact.folderName,
                fileCount: artifact.files.count,
                files: artifact.files,
                source: "explicit-user-consent",
                status: "installed",
                installedAt: Date()
            )
            let data = try JSONEncoder.meeting007Encoder.encode(marker)
            try data.write(to: installMarkerURL(for: artifact.policy), options: .atomic)
            return modelDirectory
        } catch {
            throw ModelInstallFailure.fileSystemPermissionDenied
        }
    }

    private func installMarkerURL(for policy: WhisperModelPolicy) -> URL {
        modelDirectory(for: policy).appendingPathComponent("install.json", isDirectory: false)
    }

    private func verifyInstalledFiles(_ files: [DownloadedModelFileManifest], for policy: WhisperModelPolicy) -> Bool {
        let modelDirectory = modelDirectory(for: policy)
        for file in files {
            guard LocalModelPathValidator.isSafeRelativePath(file.path) else {
                return false
            }
            let fileURL = modelDirectory.appendingPathComponent(file.path, isDirectory: false)
            guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let size = attributes[.size] as? NSNumber,
                  size.int64Value == file.size else {
                return false
            }
            guard (try? LocalModelChecksum.sha256Hex(for: fileURL)) == file.sha256 else {
                return false
            }
        }
        return true
    }
}

public actor LocalSTTModelInstaller {
    private let downloader: any ModelDownloading
    private let store: LocalSTTModelStore
    private var installState: LocalSTTModelInstallState = .notInstalled
    private var activeRequestID: UUID?

    public init(downloader: any ModelDownloading, store: LocalSTTModelStore) {
        self.downloader = downloader
        self.store = store
    }

    public func state() -> LocalSTTModelInstallState {
        installState
    }

    public func prepareInstall(policy: WhisperModelPolicy) {
        installState = .awaitingConsent(policy)
    }

    public func cancelConsent() {
        if case .awaitingConsent = installState {
            installState = .notInstalled
        }
    }

    public func confirmInstall(policy: WhisperModelPolicy) async {
        let currentAvailability = await store.availability(for: policy)
        if currentAvailability == .ready {
            let modelDirectory = await store.modelDirectory(for: policy)
            activeRequestID = nil
            installState = .ready(modelDirectory)
            return
        }

        let destination = await store.modelDirectory(for: policy)
        let request = ModelDownloadRequest(
            policy: policy,
            destinationDirectory: destination,
            expectedBytes: policy.approximateSizeInBytes
        )
        activeRequestID = request.id
        installState = .downloading(ModelDownloadProgress(
            phase: .preparing,
            downloadedBytes: 0,
            expectedBytes: Int64(policy.approximateSizeInBytes)
        ))

        do {
            let artifact = try await downloader.download(request) { [weak self] progress in
                await self?.updateProgress(progress)
            }
            installState = .verifying
            let modelDirectory = try await store.markInstalled(artifact)
            activeRequestID = nil
            installState = .ready(modelDirectory)
        } catch let failure as ModelInstallFailure {
            activeRequestID = nil
            installState = failure == .cancelled ? .notInstalled : .failed(failure)
        } catch is CancellationError {
            activeRequestID = nil
            installState = .notInstalled
        } catch {
            activeRequestID = nil
            installState = .failed(.unknown)
        }
    }

    public func cancelInstall() async {
        guard let activeRequestID else {
            cancelConsent()
            return
        }

        await downloader.cancel(requestID: activeRequestID)
        self.activeRequestID = nil
        installState = .notInstalled
    }

    private func updateProgress(_ progress: ModelDownloadProgress) {
        installState = .downloading(progress)
    }
}

private struct LocalSTTModelInstallMarker: Codable {
    let policyID: String
    let language: String
    let expectedBytes: Int
    let actualBytes: Int64
    let repositoryID: String?
    let revision: String?
    let folderName: String?
    let fileCount: Int
    let files: [DownloadedModelFileManifest]
    let source: String
    let status: String
    let installedAt: Date

    var hasVerifiedManifest: Bool {
        fileCount == files.count && !files.isEmpty
    }

    func matches(_ policy: WhisperModelPolicy) -> Bool {
        policyID == policy.modelID
            && language == policy.language
            && expectedBytes == policy.approximateSizeInBytes
            && source == "explicit-user-consent"
            && status == "installed"
    }
}

enum LocalModelPathValidator {
    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else {
            return false
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }
}

enum LocalModelChecksum {
    static func sha256Hex(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1_048_576)
            guard !data.isEmpty else {
                return false
            }
            hasher.update(data: data)
            return true
        }) {}

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private extension JSONEncoder {
    static var meeting007Encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var meeting007Decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
