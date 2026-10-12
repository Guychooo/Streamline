import Foundation

/// A stream object. Exactly one source field is expected to be set.
public struct MediaStream: Codable, Hashable, Sendable {
    public var url: String?
    public var ytId: String?
    public var infoHash: String?
    public var fileIdx: Int?
    public var externalUrl: String?
    public var nzbUrl: String?
    /// True when the stream points at archive sources (rar, zip, 7z, tar, tgz).
    public var hasArchiveSources: Bool
    public var name: String?
    public var title: String?
    public var description: String?
    public var subtitles: [Subtitle]?
    public var behaviorHints: StreamBehaviorHints?

    public init(
        url: String? = nil,
        ytId: String? = nil,
        infoHash: String? = nil,
        fileIdx: Int? = nil,
        externalUrl: String? = nil,
        nzbUrl: String? = nil,
        hasArchiveSources: Bool = false,
        name: String? = nil,
        title: String? = nil,
        description: String? = nil,
        subtitles: [Subtitle]? = nil,
        behaviorHints: StreamBehaviorHints? = nil
    ) {
        self.url = url
        self.ytId = ytId
        self.infoHash = infoHash
        self.fileIdx = fileIdx
        self.externalUrl = externalUrl
        self.nzbUrl = nzbUrl
        self.hasArchiveSources = hasArchiveSources
        self.name = name
        self.title = title
        self.description = description
        self.subtitles = subtitles
        self.behaviorHints = behaviorHints
    }

    enum CodingKeys: String, CodingKey {
        case url, ytId, infoHash, fileIdx, externalUrl, nzbUrl, name, title, description, subtitles, behaviorHints
        case rarUrls, zipUrls, tgzUrls, tarUrls
        case sevenZipUrls = "7zipUrls"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        ytId = try? c.decodeIfPresent(String.self, forKey: .ytId)
        infoHash = try? c.decodeIfPresent(String.self, forKey: .infoHash)
        fileIdx = c.flexibleInt(forKey: .fileIdx)
        externalUrl = try? c.decodeIfPresent(String.self, forKey: .externalUrl)
        nzbUrl = try? c.decodeIfPresent(String.self, forKey: .nzbUrl)
        hasArchiveSources = [.rarUrls, .zipUrls, .sevenZipUrls, .tgzUrls, .tarUrls].contains { c.contains($0) }
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        subtitles = c.lossyArray(Subtitle.self, forKey: .subtitles)
        behaviorHints = try? c.decodeIfPresent(StreamBehaviorHints.self, forKey: .behaviorHints)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(ytId, forKey: .ytId)
        try c.encodeIfPresent(infoHash, forKey: .infoHash)
        try c.encodeIfPresent(fileIdx, forKey: .fileIdx)
        try c.encodeIfPresent(externalUrl, forKey: .externalUrl)
        try c.encodeIfPresent(nzbUrl, forKey: .nzbUrl)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(subtitles, forKey: .subtitles)
        try c.encodeIfPresent(behaviorHints, forKey: .behaviorHints)
    }

    /// The short label add-ons usually use for quality, e.g. "1080p".
    public var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Stream" : trimmed
    }

    /// The longer description; `title` is the deprecated spelling.
    public var displayDescription: String? {
        let text = description ?? title
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

public struct StreamBehaviorHints: Codable, Hashable, Sendable {
    public var notWebReady: Bool?
    public var bingeGroup: String?
    public var countryWhitelist: [String]?
    public var proxyHeaders: ProxyHeaders?
    public var filename: String?
    public var videoHash: String?
    public var videoSize: Int64?

    public init(
        notWebReady: Bool? = nil,
        bingeGroup: String? = nil,
        countryWhitelist: [String]? = nil,
        proxyHeaders: ProxyHeaders? = nil,
        filename: String? = nil,
        videoHash: String? = nil,
        videoSize: Int64? = nil
    ) {
        self.notWebReady = notWebReady
        self.bingeGroup = bingeGroup
        self.countryWhitelist = countryWhitelist
        self.proxyHeaders = proxyHeaders
        self.filename = filename
        self.videoHash = videoHash
        self.videoSize = videoSize
    }
}

public struct ProxyHeaders: Codable, Hashable, Sendable {
    public var request: [String: String]?
    public var response: [String: String]?

    public init(request: [String: String]? = nil, response: [String: String]? = nil) {
        self.request = request
        self.response = response
    }
}
