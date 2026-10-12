import Foundation

public struct Subtitle: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var url: String
    public var lang: String
    public var label: String?

    public init(id: String, url: String, lang: String, label: String? = nil) {
        self.id = id
        self.url = url
        self.lang = lang
        self.label = label
    }

    enum CodingKeys: String, CodingKey { case id, url, lang, label }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        lang = (try? c.decodeIfPresent(String.self, forKey: .lang)) ?? "und"
        id = c.flexibleString(forKey: .id) ?? url
        label = try? c.decodeIfPresent(String.self, forKey: .label)
    }

    /// The label to show in a subtitle picker.
    public var displayName: String {
        if let label, !label.isEmpty { return label }
        return LanguageNames.displayName(for: lang)
    }
}
