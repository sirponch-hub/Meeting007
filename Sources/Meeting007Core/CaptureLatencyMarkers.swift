import Foundation

public enum CaptureLatencyEvent: String, Codable, Equatable, Sendable {
    case startRequested
    case spoolReady
    case firstAudioReceived
    case firstAudioSpooled
    case stopRequested
    case captureStopped
    case spoolClosed
    case spoolFailed
}

public struct CaptureLatencyMarker: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let event: CaptureLatencyEvent
    public let timestamp: TimeInterval

    public init(sessionID: UUID, event: CaptureLatencyEvent, timestamp: TimeInterval) {
        self.sessionID = sessionID
        self.event = event
        self.timestamp = timestamp
    }
}

public actor CaptureLatencyMarkers {
    public typealias Clock = @Sendable () -> TimeInterval

    private let clock: Clock
    private var markersBySession: [UUID: [CaptureLatencyMarker]] = [:]

    public init(clock: @escaping Clock = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
    }

    @discardableResult
    public func mark(sessionID: UUID, event: CaptureLatencyEvent) -> CaptureLatencyMarker {
        let previous = markersBySession[sessionID]?.last?.timestamp ?? 0
        let marker = CaptureLatencyMarker(
            sessionID: sessionID,
            event: event,
            timestamp: max(clock(), previous)
        )
        markersBySession[sessionID, default: []].append(marker)
        return marker
    }

    public func markers(sessionID: UUID) -> [CaptureLatencyMarker] {
        markersBySession[sessionID] ?? []
    }

    public func clear(sessionID: UUID) {
        markersBySession[sessionID] = nil
    }
}
