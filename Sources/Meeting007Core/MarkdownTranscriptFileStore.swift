import Foundation

public protocol TranscriptFileWriting: Sendable {
    func write(_ completedSession: CompletedRecordingSession) async throws -> TranscriptFileWriteResult
}

public struct TranscriptFileWriteResult: Equatable, Sendable {
    public let meetingID: UUID
    public let fileURL: URL
    public let markdown: String

    public init(meetingID: UUID, fileURL: URL, markdown: String) {
        self.meetingID = meetingID
        self.fileURL = fileURL
        self.markdown = markdown
    }
}

public enum TranscriptFileWriteError: Error, Equatable, Sendable {
    case incompleteCompletedSession
}

public actor LocalMarkdownTranscriptFileWriter: TranscriptFileWriting {
    private let store: MarkdownTranscriptFileStore

    public init(folderURL: URL? = nil, fileManager: FileManager = .default) {
        if let folderURL {
            self.store = MarkdownTranscriptFileStore(folderURL: folderURL, fileManager: fileManager)
        } else {
            self.store = .defaultStore(fileManager: fileManager)
        }
    }

    public func write(_ completedSession: CompletedRecordingSession) async throws -> TranscriptFileWriteResult {
        guard let startedAt = completedSession.startedAt else {
            throw TranscriptFileWriteError.incompleteCompletedSession
        }

        let metadata = MeetingMetadata(
            id: completedSession.id,
            title: completedSession.title,
            startedAt: startedAt,
            endedAt: completedSession.endedAt,
            primaryLanguage: completedSession.primaryLanguage,
            transcriptSource: "local_preview"
        )

        return try store.save(metadata: metadata, transcript: completedSession.transcript)
    }
}

public struct MarkdownTranscriptFileStore {
    private let folderURL: URL
    private let fileManager: FileManager

    public init(folderURL: URL, fileManager: FileManager = .default) {
        self.folderURL = folderURL
        self.fileManager = fileManager
    }

    public static func defaultStore(fileManager: FileManager = .default) -> MarkdownTranscriptFileStore {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        return MarkdownTranscriptFileStore(
            folderURL: documentsURL
                .appendingPathComponent("Meeting007", isDirectory: true)
                .appendingPathComponent("Transcripts", isDirectory: true),
            fileManager: fileManager
        )
    }

    public func save(metadata: MeetingMetadata, transcript: MeetingTranscript) throws -> TranscriptFileWriteResult {
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let markdown = MarkdownTranscriptExporter.export(metadata: metadata, transcript: transcript)
        let fileURL = folderURL.appendingPathComponent(filename(for: metadata), isDirectory: false)
        let tempURL = folderURL.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp", isDirectory: false)

        do {
            try markdown.write(to: tempURL, atomically: false, encoding: .utf8)

            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: fileURL)
            }
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }

        return TranscriptFileWriteResult(meetingID: metadata.id, fileURL: fileURL, markdown: markdown)
    }

    public func filename(for metadata: MeetingMetadata) -> String {
        let date = Self.filenameDateFormatter().string(from: metadata.startedAt)
        let slug = Self.slug(metadata.title)
        let shortID = String(metadata.id.uuidString.prefix(8)).lowercased()
        return "\(date)_\(slug)_\(shortID).md"
    }

    public static func slug(_ title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let source = trimmedTitle.isEmpty ? "untitled meeting" : transliterateCyrillic(trimmedTitle)
        var result = ""
        var previousWasSeparator = false

        for scalar in source.unicodeScalars {
            if CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                result.append("-")
                previousWasSeparator = true
            }
        }

        let slug = result.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(60)
        return slug.isEmpty ? "untitled-meeting" : String(slug)
    }

    private static func filenameDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return formatter
    }

    private static func transliterateCyrillic(_ value: String) -> String {
        let pairs: [(String, String)] = [
            ("а", "a"), ("б", "b"), ("в", "v"), ("г", "g"), ("д", "d"), ("е", "e"), ("ё", "e"),
            ("ж", "zh"), ("з", "z"), ("и", "i"), ("й", "y"), ("к", "k"), ("л", "l"), ("м", "m"),
            ("н", "n"), ("о", "o"), ("п", "p"), ("р", "r"), ("с", "s"), ("т", "t"), ("у", "u"),
            ("ф", "f"), ("х", "h"), ("ц", "ts"), ("ч", "ch"), ("ш", "sh"), ("щ", "sch"), ("ъ", ""),
            ("ы", "y"), ("ь", ""), ("э", "e"), ("ю", "yu"), ("я", "ya")
        ]

        var result = value
        for (source, replacement) in pairs {
            result = result.replacingOccurrences(of: source, with: replacement)
        }
        return result
    }
}
