import Foundation
import Meeting007Core

@main
struct Meeting007CoreChecks {
    static func main() {
        checkSegmentsAreSortedByStartTime()
        checkUpsertReplacesPartialWithFinalSegment()
        checkCopyLastWindowIncludesOnlyRecentSegments()
        checkTimestampFormatterUsesMinutesAndHours()
        checkMarkdownExportIncludesOnlyFinalSegments()
        print("Meeting007CoreChecks passed")
    }

    private static func checkSegmentsAreSortedByStartTime() {
        let meetingID = UUID()
        let first = TranscriptSegment(
            meetingID: meetingID,
            lane: .me,
            state: .final,
            startTime: 0,
            endTime: 2,
            text: "First"
        )
        let second = TranscriptSegment(
            meetingID: meetingID,
            lane: .others,
            state: .final,
            startTime: 10,
            endTime: 12,
            text: "Second"
        )

        let transcript = MeetingTranscript(meetingID: meetingID, segments: [second, first])
        require(transcript.segments.map(\.text) == ["First", "Second"], "Segments must be sorted by start time.")
    }

    private static func checkUpsertReplacesPartialWithFinalSegment() {
        let meetingID = UUID()
        let segmentID = UUID()
        var transcript = MeetingTranscript(meetingID: meetingID)

        transcript.upsert(TranscriptSegment(
            id: segmentID,
            meetingID: meetingID,
            lane: .others,
            state: .partial,
            startTime: 1,
            endTime: 3,
            text: "priv"
        ))
        transcript.upsert(TranscriptSegment(
            id: segmentID,
            meetingID: meetingID,
            lane: .others,
            state: .final,
            startTime: 1,
            endTime: 3,
            text: "Привет"
        ))

        require(transcript.segments.count == 1, "Upsert must replace an existing segment.")
        require(transcript.segments.first?.state == .final, "Replacement segment must be final.")
        require(transcript.segments.first?.text == "Привет", "Replacement segment must keep final text.")
    }

    private static func checkCopyLastWindowIncludesOnlyRecentSegments() {
        let meetingID = UUID()
        let oldSegment = TranscriptSegment(
            meetingID: meetingID,
            lane: .me,
            state: .final,
            startTime: 10,
            endTime: 20,
            text: "Old context"
        )
        let recentSegment = TranscriptSegment(
            meetingID: meetingID,
            lane: .others,
            state: .final,
            startTime: 295,
            endTime: 300,
            text: "Recent context"
        )
        let transcript = MeetingTranscript(meetingID: meetingID, segments: [oldSegment, recentSegment])
        let copiedText = transcript.textForLast(seconds: 300, from: 600)

        require(!copiedText.contains("Old context"), "Old segment must be outside the copy window.")
        require(copiedText.contains("Recent context"), "Recent segment must be included in the copy window.")
        require(copiedText.contains("Others"), "Copy text must include speaker labels.")
    }

    private static func checkTimestampFormatterUsesMinutesAndHours() {
        require(TimestampFormatter.format(65) == "01:05", "Minute timestamp formatting failed.")
        require(TimestampFormatter.format(3661) == "01:01:01", "Hour timestamp formatting failed.")
    }

    private static func checkMarkdownExportIncludesOnlyFinalSegments() {
        let meetingID = UUID()
        let metadata = MeetingMetadata(
            id: meetingID,
            title: "Русская встреча",
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 60)
        )
        let transcript = MeetingTranscript(meetingID: meetingID, segments: [
            TranscriptSegment(
                meetingID: meetingID,
                lane: .me,
                state: .final,
                startTime: 0,
                endTime: 3,
                text: "Готово"
            ),
            TranscriptSegment(
                meetingID: meetingID,
                lane: .others,
                state: .partial,
                startTime: 4,
                endTime: 5,
                text: "partial"
            )
        ])

        let markdown = MarkdownTranscriptExporter.export(metadata: metadata, transcript: transcript)

        require(markdown.contains("# Русская встреча"), "Markdown must include the meeting title.")
        require(markdown.contains("primary_language: ru"), "Markdown must include the Russian default language.")
        require(markdown.contains("Me: Готово"), "Markdown must include final transcript text.")
        require(!markdown.contains("partial"), "Markdown export must exclude partial segments.")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("Check failed: \(message)\n", stderr)
            exit(1)
        }
    }
}

