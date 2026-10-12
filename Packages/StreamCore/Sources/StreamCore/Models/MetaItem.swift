import Foundation

/// A catalog entry or full detail record. The protocol uses the same shape
/// for both; detail responses simply fill in more fields.
public struct MetaItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var type: String
    public var name: String
    public var poster: String?
    public var posterShape: PosterShape?
    public var background: String?
    public var logo: String?
    public var description: String?
    public var releaseInfo: String?
    public var imdbRating: String?
    public var runtime: String?
    public var genres: [String]?
    public var cast: [String]?
    public var director: [String]?
    public var videos: [Video]?
    public var behaviorHints: MetaBehaviorHints?

    public init(
        id: String,
        type: String,
        name: String,
        poster: String? = nil,
        posterShape: PosterShape? = nil,
        background: String? = nil,
        logo: String? = nil,
        description: String? = nil,
        releaseInfo: String? = nil,
        imdbRating: String? = nil,
        runtime: String? = nil,
        genres: [String]? = nil,
        cast: [String]? = nil,
        director: [String]? = nil,
        videos: [Video]? = nil,
        behaviorHints: MetaBehaviorHints? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.poster = poster
        self.posterShape = posterShape
        self.background = background
        self.logo = logo
        self.description = description
        self.releaseInfo = releaseInfo
        self.imdbRating = imdbRating
        self.runtime = runtime
        self.genres = genres
        self.cast = cast
        self.director = director
        self.videos = videos
        self.behaviorHints = behaviorHints
    }

    enum CodingKeys: String, CodingKey {
        case id, type, name, poster, posterShape, background, logo, description, releaseInfo
        case imdbRating, runtime, genres, cast, director, videos, behaviorHints, year
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "other"
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Untitled"
        poster = try? c.decodeIfPresent(String.self, forKey: .poster)
        posterShape = try? c.decodeIfPresent(PosterShape.self, forKey: .posterShape)
        background = try? c.decodeIfPresent(String.self, forKey: .background)
        logo = try? c.decodeIfPresent(String.self, forKey: .logo)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        releaseInfo = c.flexibleString(forKey: .releaseInfo) ?? c.flexibleString(forKey: .year)
        imdbRating = c.flexibleString(forKey: .imdbRating)
        runtime = try? c.decodeIfPresent(String.self, forKey: .runtime)
        genres = try? c.decodeIfPresent([String].self, forKey: .genres)
        cast = try? c.decodeIfPresent([String].self, forKey: .cast)
        director = try? c.decodeIfPresent([String].self, forKey: .director)
        videos = c.lossyArray(Video.self, forKey: .videos)
        behaviorHints = try? c.decodeIfPresent(MetaBehaviorHints.self, forKey: .behaviorHints)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(poster, forKey: .poster)
        try c.encodeIfPresent(posterShape, forKey: .posterShape)
        try c.encodeIfPresent(background, forKey: .background)
        try c.encodeIfPresent(logo, forKey: .logo)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(releaseInfo, forKey: .releaseInfo)
        try c.encodeIfPresent(imdbRating, forKey: .imdbRating)
        try c.encodeIfPresent(runtime, forKey: .runtime)
        try c.encodeIfPresent(genres, forKey: .genres)
        try c.encodeIfPresent(cast, forKey: .cast)
        try c.encodeIfPresent(director, forKey: .director)
        try c.encodeIfPresent(videos, forKey: .videos)
        try c.encodeIfPresent(behaviorHints, forKey: .behaviorHints)
    }

    /// Items without a `videos` list play as a single video whose id is the item id.
    public var isSingleVideo: Bool { (videos ?? []).isEmpty }

    /// Season numbers in ascending order, with specials (season 0) last.
    public var seasons: [Int] {
        let all = Set((videos ?? []).compactMap(\.season))
        return all.filter { $0 > 0 }.sorted() + (all.contains(0) ? [0] : [])
    }

    public func episodes(inSeason season: Int?) -> [Video] {
        let list = videos ?? []
        let filtered = season.map { s in list.filter { $0.season == s } } ?? list
        return filtered.sorted { ($0.episode ?? 0, $0.released ?? "") < ($1.episode ?? 0, $1.released ?? "") }
    }

    /// Returns `self` with any fields missing here filled in from `other`.
    public func merging(fallback other: MetaItem) -> MetaItem {
        var merged = self
        merged.poster = poster ?? other.poster
        merged.background = background ?? other.background
        merged.logo = logo ?? other.logo
        merged.description = description ?? other.description
        merged.releaseInfo = releaseInfo ?? other.releaseInfo
        merged.imdbRating = imdbRating ?? other.imdbRating
        merged.genres = genres ?? other.genres
        return merged
    }
}

public enum PosterShape: String, Codable, Hashable, Sendable {
    case poster, square, landscape

    /// Width divided by height.
    public var aspectRatio: Double {
        switch self {
        case .poster: return 0.675
        case .square: return 1
        case .landscape: return 1.77
        }
    }
}

public struct MetaBehaviorHints: Codable, Hashable, Sendable {
    public var defaultVideoId: String?
    public var isLive: Bool?

    public init(defaultVideoId: String? = nil, isLive: Bool? = nil) {
        self.defaultVideoId = defaultVideoId
        self.isLive = isLive
    }
}

public struct Video: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var released: String?
    public var thumbnail: String?
    public var overview: String?
    public var season: Int?
    public var episode: Int?
    public var streams: [MediaStream]?

    public init(
        id: String,
        title: String,
        released: String? = nil,
        thumbnail: String? = nil,
        overview: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        streams: [MediaStream]? = nil
    ) {
        self.id = id
        self.title = title
        self.released = released
        self.thumbnail = thumbnail
        self.overview = overview
        self.season = season
        self.episode = episode
        self.streams = streams
    }

    enum CodingKeys: String, CodingKey {
        case id, title, name, released, thumbnail, overview, description, season, episode, number, streams
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        season = c.flexibleInt(forKey: .season)
        episode = c.flexibleInt(forKey: .episode) ?? c.flexibleInt(forKey: .number)
        title = (try? c.decodeIfPresent(String.self, forKey: .title))
            ?? (try? c.decodeIfPresent(String.self, forKey: .name))
            ?? episode.map { "Episode \($0)" }
            ?? "Video"
        released = try? c.decodeIfPresent(String.self, forKey: .released)
        thumbnail = try? c.decodeIfPresent(String.self, forKey: .thumbnail)
        overview = (try? c.decodeIfPresent(String.self, forKey: .overview))
            ?? (try? c.decodeIfPresent(String.self, forKey: .description))
        streams = c.lossyArray(MediaStream.self, forKey: .streams)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(released, forKey: .released)
        try c.encodeIfPresent(thumbnail, forKey: .thumbnail)
        try c.encodeIfPresent(overview, forKey: .overview)
        try c.encodeIfPresent(season, forKey: .season)
        try c.encodeIfPresent(episode, forKey: .episode)
        try c.encodeIfPresent(streams, forKey: .streams)
    }

    /// "S1 · E4" style label, or nil for videos without numbering.
    public var episodeLabel: String? {
        switch (season, episode) {
        case let (s?, e?): return "S\(s) · E\(e)"
        case let (nil, e?): return "E\(e)"
        default: return nil
        }
    }
}
