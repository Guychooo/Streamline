import Foundation

public struct CatalogResponse: Decodable, Sendable {
    public var metas: [MetaItem]
    enum CodingKeys: String, CodingKey { case metas }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metas = c.lossyArray(MetaItem.self, forKey: .metas) ?? []
    }
}

public struct MetaResponse: Decodable, Sendable {
    public var meta: MetaItem?
    enum CodingKeys: String, CodingKey { case meta }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meta = try? c.decodeIfPresent(MetaItem.self, forKey: .meta)
    }
}

public struct StreamsResponse: Decodable, Sendable {
    public var streams: [MediaStream]
    enum CodingKeys: String, CodingKey { case streams }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streams = c.lossyArray(MediaStream.self, forKey: .streams) ?? []
    }
}

public struct SubtitlesResponse: Decodable, Sendable {
    public var subtitles: [Subtitle]
    enum CodingKeys: String, CodingKey { case subtitles }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subtitles = c.lossyArray(Subtitle.self, forKey: .subtitles) ?? []
    }
}
