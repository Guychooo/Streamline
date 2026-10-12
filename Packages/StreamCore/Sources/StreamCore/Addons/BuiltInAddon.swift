import Foundation

/// An add-on that lives inside the app and answers requests from memory.
public struct BuiltInAddon: AddonTransport {
    public static let scheme = "builtin://"

    public let transportURL: String
    public let manifest: Manifest
    private let responses: [String: Data]

    /// - Parameter responses: Encodable payloads keyed by `ResourceRequest.path`.
    public init(slug: String, manifest: Manifest, responses: [String: any Encodable]) {
        self.transportURL = Self.scheme + slug
        self.manifest = manifest
        let encoder = JSONEncoder()
        var encoded: [String: Data] = [:]
        for (path, value) in responses {
            if let data = try? encoder.encode(AnyEncodable(value)) {
                encoded[path] = data
            }
        }
        self.responses = encoded
    }

    public func fetchManifest() async throws -> Manifest { manifest }

    public func fetch(_ request: ResourceRequest) async throws -> Data {
        // Built-in catalogs are small, so paging and search extras are answered
        // from the unfiltered response, with search applied by the client.
        let unfiltered = ResourceRequest(resource: request.resource, type: request.type, id: request.id)
        if let data = responses[request.path] ?? responses[unfiltered.path] {
            if let query = request.extra.first(where: { $0.name == "search" })?.value, request.resource == "catalog" {
                return try Self.filterCatalog(data, query: query)
            }
            if request.extra.contains(where: { $0.name == "skip" && $0.value != "0" }) {
                return Data(#"{"metas":[]}"#.utf8)
            }
            return data
        }
        // An empty but well-formed answer, like a real add-on with no match.
        let key: String
        switch request.resource {
        case "catalog": key = "metas"
        case "stream": key = "streams"
        case "subtitles": key = "subtitles"
        default: throw AddonError.resourceNotFound(request.path)
        }
        return Data(#"{"\#(key)":[]}"#.utf8)
    }

    private static func filterCatalog(_ data: Data, query: String) throws -> Data {
        let catalog = try JSONDecoder().decode(CatalogResponse.self, from: data)
        let needle = query.lowercased()
        let matches = catalog.metas.filter {
            $0.name.lowercased().contains(needle) || ($0.description ?? "").lowercased().contains(needle)
        }
        return try JSONEncoder().encode(["metas": matches])
    }
}

private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
