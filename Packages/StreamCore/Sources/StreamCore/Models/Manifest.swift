import Foundation

/// An add-on manifest, as served at `<base>/manifest.json`.
public struct Manifest: Codable, Hashable, Sendable {
    public var id: String
    public var version: String
    public var name: String
    public var description: String?
    public var logo: String?
    public var background: String?
    public var types: [String]
    public var idPrefixes: [String]?
    public var resources: [ManifestResource]
    public var catalogs: [CatalogDescriptor]
    public var behaviorHints: ManifestBehaviorHints?

    public init(
        id: String,
        version: String,
        name: String,
        description: String? = nil,
        logo: String? = nil,
        background: String? = nil,
        types: [String],
        idPrefixes: [String]? = nil,
        resources: [ManifestResource],
        catalogs: [CatalogDescriptor],
        behaviorHints: ManifestBehaviorHints? = nil
    ) {
        self.id = id
        self.version = version
        self.name = name
        self.description = description
        self.logo = logo
        self.background = background
        self.types = types
        self.idPrefixes = idPrefixes
        self.resources = resources
        self.catalogs = catalogs
        self.behaviorHints = behaviorHints
    }

    enum CodingKeys: String, CodingKey {
        case id, version, name, description, logo, background, types, idPrefixes, resources, catalogs, behaviorHints
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        version = c.flexibleString(forKey: .version) ?? "0.0.0"
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        logo = try? c.decodeIfPresent(String.self, forKey: .logo)
        background = try? c.decodeIfPresent(String.self, forKey: .background)
        types = (try? c.decodeIfPresent([String].self, forKey: .types)) ?? []
        idPrefixes = try? c.decodeIfPresent([String].self, forKey: .idPrefixes)
        resources = c.lossyArray(ManifestResource.self, forKey: .resources) ?? []
        catalogs = c.lossyArray(CatalogDescriptor.self, forKey: .catalogs) ?? []
        behaviorHints = try? c.decodeIfPresent(ManifestBehaviorHints.self, forKey: .behaviorHints)
    }

    /// True when the add-on needs to be configured on its own website before use.
    public var requiresConfiguration: Bool {
        behaviorHints?.configurationRequired == true
    }
}

public struct ManifestBehaviorHints: Codable, Hashable, Sendable {
    public var adult: Bool?
    public var p2p: Bool?
    public var configurable: Bool?
    public var configurationRequired: Bool?

    public init(adult: Bool? = nil, p2p: Bool? = nil, configurable: Bool? = nil, configurationRequired: Bool? = nil) {
        self.adult = adult
        self.p2p = p2p
        self.configurable = configurable
        self.configurationRequired = configurationRequired
    }
}

/// A resource entry. Manifests may list a resource either as a bare string,
/// which inherits the manifest's `types` and `idPrefixes`, or as an object
/// that carries its own.
public struct ManifestResource: Codable, Hashable, Sendable {
    public var name: String
    public var types: [String]?
    public var idPrefixes: [String]?
    /// True when the manifest used the bare-string form.
    public var isShortForm: Bool

    public static func short(_ name: String) -> ManifestResource {
        ManifestResource(name: name, types: nil, idPrefixes: nil, isShortForm: true)
    }

    public static func full(_ name: String, types: [String], idPrefixes: [String]? = nil) -> ManifestResource {
        ManifestResource(name: name, types: types, idPrefixes: idPrefixes, isShortForm: false)
    }

    public init(name: String, types: [String]?, idPrefixes: [String]?, isShortForm: Bool) {
        self.name = name
        self.types = types
        self.idPrefixes = idPrefixes
        self.isShortForm = isShortForm
    }

    enum CodingKeys: String, CodingKey { case name, types, idPrefixes }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let name = try? single.decode(String.self) {
            self = .short(name)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        types = try? c.decodeIfPresent([String].self, forKey: .types)
        idPrefixes = try? c.decodeIfPresent([String].self, forKey: .idPrefixes)
        isShortForm = false
    }

    public func encode(to encoder: Encoder) throws {
        if isShortForm {
            var single = encoder.singleValueContainer()
            try single.encode(name)
        } else {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encodeIfPresent(types, forKey: .types)
            try c.encodeIfPresent(idPrefixes, forKey: .idPrefixes)
        }
    }
}

public struct CatalogDescriptor: Codable, Hashable, Sendable {
    public var type: String
    public var id: String
    public var name: String?
    public var extra: [ExtraProperty]

    public init(type: String, id: String, name: String?, extra: [ExtraProperty] = []) {
        self.type = type
        self.id = id
        self.name = name
        self.extra = extra
    }

    enum CodingKeys: String, CodingKey { case type, id, name, extra, extraSupported, extraRequired }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        id = try c.decode(String.self, forKey: .id)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        if let modern = c.lossyArray(ExtraProperty.self, forKey: .extra) {
            extra = modern
        } else {
            // Older manifests describe extras with two string arrays.
            let supported = (try? c.decodeIfPresent([String].self, forKey: .extraSupported)) ?? []
            let required = Set((try? c.decodeIfPresent([String].self, forKey: .extraRequired)) ?? [])
            extra = supported.map { ExtraProperty(name: $0, isRequired: required.contains($0)) }
            for name in required where !supported.contains(name) {
                extra.append(ExtraProperty(name: name, isRequired: true))
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(extra, forKey: .extra)
    }

    public var supportsSearch: Bool { extra.contains { $0.name == "search" } }

    /// Catalogs that can be listed without any extra arguments, for browsing.
    public var isBrowsable: Bool { !extra.contains { $0.isRequired } }

    /// Catalogs whose only required argument, if any, is the search query.
    public var isSearchable: Bool {
        supportsSearch && extra.allSatisfy { !$0.isRequired || $0.name == "search" }
    }

    public var supportsPaging: Bool { extra.contains { $0.name == "skip" } }

    public var displayName: String { name ?? id.capitalized }
}

public struct ExtraProperty: Codable, Hashable, Sendable {
    public var name: String
    public var isRequired: Bool
    public var options: [String]?
    public var optionsLimit: Int?

    public init(name: String, isRequired: Bool = false, options: [String]? = nil, optionsLimit: Int? = nil) {
        self.name = name
        self.isRequired = isRequired
        self.options = options
        self.optionsLimit = optionsLimit
    }

    enum CodingKeys: String, CodingKey { case name, isRequired, options, optionsLimit }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        isRequired = (try? c.decodeIfPresent(Bool.self, forKey: .isRequired)) ?? false
        options = try? c.decodeIfPresent([String].self, forKey: .options)
        optionsLimit = c.flexibleInt(forKey: .optionsLimit)
    }
}
