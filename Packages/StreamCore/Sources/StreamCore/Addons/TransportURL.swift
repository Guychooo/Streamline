import Foundation

/// Normalises what a person pastes into a canonical manifest URL.
///
/// Accepts `https://host/path/manifest.json`, the same without the file
/// name, and `stremio://host/path/manifest.json` install links, which are
/// the https URL with a different scheme.
public enum TransportURL {
    public static func normalize(_ input: String) throws -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AddonError.invalidURL(input) }

        if text.lowercased().hasPrefix("stremio://") {
            text = "https://" + text.dropFirst("stremio://".count)
        } else if !text.contains("://") {
            text = "https://" + text
        }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty
        else { throw AddonError.invalidURL(input) }

        guard scheme == "https" || scheme == "http" else {
            throw AddonError.unsupportedScheme(scheme)
        }
        components.scheme = scheme

        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/manifest.json") {
            path += "/manifest.json"
        }
        components.percentEncodedPath = path
        components.fragment = nil

        guard let url = components.url else { throw AddonError.invalidURL(input) }
        return url
    }

    /// The base URL that resource paths are appended to.
    public static func baseURLString(forManifest manifestURL: String) -> String {
        var base = manifestURL
        if let queryStart = base.firstIndex(of: "?") {
            base = String(base[..<queryStart])
        }
        if base.hasSuffix("/manifest.json") {
            base.removeLast("/manifest.json".count)
        }
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }
}
