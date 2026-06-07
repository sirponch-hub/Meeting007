import Foundation

public struct MeetingMetadata: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let startedAt: Date
    public let endedAt: Date?
    public let primaryLanguage: String

    public init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date,
        endedAt: Date? = nil,
        primaryLanguage: String = "ru"
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.primaryLanguage = primaryLanguage
    }
}

public enum MarkdownTranscriptExporter {
    public static func export(metadata: MeetingMetadata, transcript: MeetingTranscript) -> String {
        var lines: [String] = [
            "---",
            "id: \(metadata.id.uuidString)",
            "title: \(yamlEscape(metadata.title))",
            "started_at: \(metadata.startedAt.ISO8601Format())",
            "primary_language: \(metadata.primaryLanguage)"
        ]

        if let endedAt = metadata.endedAt {
            lines.append("ended_at: \(endedAt.ISO8601Format())")
        }

        lines.append(contentsOf: [
            "---",
            "",
            "# \(metadata.title)",
            "",
            "## Transcript",
            ""
        ])

        lines.append(transcript.plainText(includePartial: false))
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func yamlEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

