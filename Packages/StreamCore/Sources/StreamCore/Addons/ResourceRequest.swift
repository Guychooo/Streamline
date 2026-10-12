import Foundation

/// A request for `/{resource}/{type}/{id}[/{extra}].json`.
public struct ResourceRequest: Hashable, Sendable {
    public struct Extra: Hashable, Sendable {
        public var name: String
        public var value: String
        public init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
    }

    public var resource: String
    public var type: String
    public var id: String
    public var extra: [Extra]

    public init(resource: String, type: String, id: String, extra: [Extra] = []) {
        self.resource = resource
        self.type = type
        self.id = id
        self.extra = extra
    }

    /// The path relative to the add-on base, without a leading slash.
    ///
    /// Path segments use JavaScript `encodeURIComponent` rules, and extras
    /// form a query-string segment, which is what the official SDK router
    /// decodes on the server side.
    public var path: String {
        var segments = [resource, type, id].map(Self.encodeComponent)
        let extras = extra.filter { !$0.value.isEmpty }
        if !extras.isEmpty {
            segments.append(extras.map { "\(Self.encodeComponent($0.name))=\(Self.encodeComponent($0.value))" }.joined(separator: "&"))
        }
        return segments.joined(separator: "/") + ".json"
    }

    private static let unreserved: CharacterSet = {
        var set = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        set.insert(charactersIn: "-_.!~*'()")
        return set
    }()

    static func encodeComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
