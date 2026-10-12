import Foundation

public struct SubtitleCue: Hashable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public enum SubtitleFormat: Sendable {
    case srt, webVTT, ass
}

public enum SubtitleParseError: Error, Equatable, LocalizedError {
    case unreadableEncoding
    case noCues

    public var errorDescription: String? {
        switch self {
        case .unreadableEncoding: return "The subtitle file uses a text encoding this app can't read."
        case .noCues: return "The subtitle file has no timed lines this app can read."
        }
    }
}

/// Parses SRT, WebVTT and the dialogue lines of ASS/SSA files into plain-text cues.
public enum SubtitleParser {
    public static func parse(data: Data) throws -> [SubtitleCue] {
        guard let text = decodeText(data) else { throw SubtitleParseError.unreadableEncoding }
        return try parse(text: text)
    }

    public static func parse(text raw: String) throws -> [SubtitleCue] {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        let cues: [SubtitleCue]
        switch detectFormat(text) {
        case .ass: cues = parseASS(text)
        case .srt, .webVTT: cues = parseBlocks(text)
        }
        guard !cues.isEmpty else { throw SubtitleParseError.noCues }
        return cues.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    public static func detectFormat(_ text: String) -> SubtitleFormat {
        let head = text.prefix(512).trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("WEBVTT") { return .webVTT }
        if head.hasPrefix("[Script Info]") || text.contains("\nDialogue:") { return .ass }
        return .srt
    }

    // MARK: SRT and WebVTT

    private static func parseBlocks(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = text.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timingIndex].components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTimestamp(parts[0]),
                  let endToken = parts[1].split(whereSeparator: { $0 == " " || $0 == "\t" }).first,
                  let end = parseTimestamp(String(endToken)),
                  end > start
            else { continue }
            let body = lines[(timingIndex + 1)...]
                .map(cleanMarkup)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            guard !body.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: body))
        }
        return cues
    }

    /// Parses `hh:mm:ss,mmm`, `hh:mm:ss.mmm`, `mm:ss.mmm` and ASS's `h:mm:ss.cc`.
    static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let value = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let fields = value.split(separator: ":")
        guard (2...3).contains(fields.count) else { return nil }
        var seconds: Double = 0
        for field in fields {
            guard let number = Double(field), number >= 0 else { return nil }
            seconds = seconds * 60 + number
        }
        return seconds
    }

    // MARK: ASS / SSA

    private static func parseASS(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var inEvents = false
        // Default column order from the ASS spec.
        var columns = ["Layer", "Start", "End", "Style", "Name", "MarginL", "MarginR", "MarginV", "Effect", "Text"]

        for line in text.split(separator: "\n").map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inEvents = trimmed.lowercased() == "[events]"
                continue
            }
            guard inEvents else { continue }
            if trimmed.hasPrefix("Format:") {
                columns = trimmed.dropFirst("Format:".count)
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                continue
            }
            guard trimmed.hasPrefix("Dialogue:") else { continue }
            let payload = String(trimmed.dropFirst("Dialogue:".count))
            // The text column is last and may itself contain commas.
            let fields = payload.split(separator: ",", maxSplits: columns.count - 1, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count == columns.count,
                  let startIndex = columns.firstIndex(of: "Start"),
                  let endIndex = columns.firstIndex(of: "End"),
                  let textIndex = columns.firstIndex(of: "Text"),
                  let start = parseTimestamp(fields[startIndex]),
                  let end = parseTimestamp(fields[endIndex]),
                  end > start
            else { continue }
            let body = fields[textIndex]
                .replacingOccurrences(of: "\\N", with: "\n")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\h", with: " ")
                .split(separator: "\n")
                .map { cleanMarkup(String($0)) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            guard !body.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: body))
        }
        return cues
    }

    // MARK: Text clean-up

    static func cleanMarkup(_ line: String) -> String {
        var result = ""
        var depthAngle = 0
        var depthBrace = 0
        for character in line {
            switch character {
            case "<": depthAngle += 1
            case ">" where depthAngle > 0: depthAngle -= 1
            case "{": depthBrace += 1
            case "}" where depthBrace > 0: depthBrace -= 1
            default:
                if depthAngle == 0 && depthBrace == 0 { result.append(character) }
            }
        }
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespaces)
    }

    static func decodeText(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        // Many older subtitle files are Windows-1252 rather than UTF-8.
        return String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1)
    }
}

/// Fast lookup of the cue text that should be on screen at a given time.
public struct SubtitleTrack: Sendable {
    public let cues: [SubtitleCue]
    private let longestCue: TimeInterval

    public init(cues: [SubtitleCue]) {
        self.cues = cues.sorted { $0.start < $1.start }
        self.longestCue = cues.map { $0.end - $0.start }.max() ?? 0
    }

    /// The text of all cues active at `time`, joined by new lines.
    public func text(at time: TimeInterval) -> String? {
        // Binary search for the first cue starting after `time`.
        var low = 0
        var high = cues.count
        while low < high {
            let mid = (low + high) / 2
            if cues[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        var active: [String] = []
        var index = low - 1
        while index >= 0, cues[index].start >= time - longestCue {
            let cue = cues[index]
            if cue.end > time { active.append(cue.text) }
            index -= 1
        }
        return active.isEmpty ? nil : active.reversed().joined(separator: "\n")
    }
}
