import Foundation

public struct InstalledAddon: Codable, Hashable, Sendable, Identifiable {
    public var transportURL: String
    public var manifest: Manifest

    public init(transportURL: String, manifest: Manifest) {
        self.transportURL = transportURL
        self.manifest = manifest
    }

    public var id: String { transportURL }
    public var isBuiltIn: Bool { transportURL.hasPrefix(BuiltInAddon.scheme) }

    public func providesResource(_ name: String) -> Bool {
        manifest.resources.contains { $0.name == name }
    }

    /// Whether this add-on should be asked for `resource` on an item of
    /// `type` with `id`, following the manifest's types and id prefixes.
    public func supports(resource: String, type: String, id: String) -> Bool {
        guard let entry = manifest.resources.first(where: { $0.name == resource }) else { return false }
        let types: [String]
        let prefixes: [String]?
        if entry.isShortForm {
            types = manifest.types
            prefixes = manifest.idPrefixes
        } else {
            types = entry.types ?? manifest.types
            prefixes = entry.idPrefixes
        }
        guard types.contains(type) else { return false }
        guard let prefixes, !prefixes.isEmpty else { return true }
        return prefixes.contains { id.hasPrefix($0) }
    }

    public var browsableCatalogs: [CatalogDescriptor] {
        manifest.catalogs.filter(\.isBrowsable)
    }

    public var searchableCatalogs: [CatalogDescriptor] {
        manifest.catalogs.filter(\.isSearchable)
    }
}
