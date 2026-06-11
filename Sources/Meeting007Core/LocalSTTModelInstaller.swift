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

    public init(policy: WhisperModelPolicy, localURL: URL) {
        self.policy = policy
        self.localURL = localURL
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

        return .ready
    }

    public func modelDirectory(for policy: WhisperModelPolicy) -> URL {
        rootDirectory.appendingPathComponent(policy.modelID, isDirectory: true)
    }

    public func markInstalled(_ artifact: DownloadedModelArtifact) throws -> URL {
        let modelDirectory = modelDirectory(for: artifact.policy)
        do {
            try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            let marker = LocalSTTModelInstallMarker(
                policyID: artifact.policy.modelID,
                language: artifact.policy.language,
                expectedBytes: artifact.policy.approximateSizeInBytes,
                source: "explicit-user-consent",
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
    let source: String
    let installedAt: Date
}

private extension JSONEncoder {
    static var meeting007Encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
