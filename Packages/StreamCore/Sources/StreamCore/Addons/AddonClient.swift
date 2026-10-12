import Foundation

/// Results from a single add-on, kept separate so one failing add-on
/// does not hide the others.
public struct AddonStreams: Identifiable, Sendable {
    public var addon: InstalledAddon
    public var streams: [MediaStream]
    public var errorMessage: String?
    public var id: String { addon.id }
}

public struct SearchResults: Identifiable, Sendable {
    public var addon: InstalledAddon
    public var catalog: CatalogDescriptor
    public var metas: [MetaItem]
    public var id: String { addon.id + "|" + catalog.type + "|" + catalog.id }
}

/// Talks to every installed add-on and merges their answers the way the
/// Stremio clients do: catalogs per add-on, the first meta that answers,
/// and streams and subtitles from all add-ons that claim the item.
public struct AddonClient: Sendable {
    public let addons: [InstalledAddon]
    private let transports: [String: any AddonTransport]

    public init(addons: [InstalledAddon], factory: AddonTransportFactory) {
        self.addons = addons
        var map: [String: any AddonTransport] = [:]
        for addon in addons {
            map[addon.id] = factory.transport(for: addon.transportURL)
        }
        self.transports = map
    }

    // MARK: Catalogs

    public func catalog(
        _ catalog: CatalogDescriptor,
        from addon: InstalledAddon,
        skip: Int = 0,
        extra: [ResourceRequest.Extra] = []
    ) async throws -> [MetaItem] {
        var extras = extra
        if skip > 0 { extras.append(.init("skip", String(skip))) }
        let request = ResourceRequest(resource: "catalog", type: catalog.type, id: catalog.id, extra: extras)
        return try await fetch(CatalogResponse.self, request, from: addon).metas
    }

    public func search(_ query: String) async -> [SearchResults] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let jobs = addons.flatMap { addon in addon.searchableCatalogs.map { (addon, $0) } }

        return await withTaskGroup(of: (Int, SearchResults?).self) { group in
            for (index, job) in jobs.enumerated() {
                group.addTask {
                    let metas = try? await self.catalog(job.1, from: job.0, extra: [.init("search", trimmed)])
                    guard let metas, !metas.isEmpty else { return (index, nil) }
                    return (index, SearchResults(addon: job.0, catalog: job.1, metas: metas))
                }
            }
            var collected: [(Int, SearchResults)] = []
            for await (index, result) in group {
                if let result { collected.append((index, result)) }
            }
            return collected.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    // MARK: Meta

    /// Asks meta-capable add-ons in install order and returns the first answer.
    public func meta(type: String, id: String) async -> MetaItem? {
        for addon in addons where addon.supports(resource: "meta", type: type, id: id) {
            let request = ResourceRequest(resource: "meta", type: type, id: id)
            if let meta = try? await fetch(MetaResponse.self, request, from: addon).meta {
                return meta
            }
        }
        return nil
    }

    // MARK: Streams

    public func streams(type: String, videoID: String) async -> [AddonStreams] {
        let candidates = addons.filter { $0.supports(resource: "stream", type: type, id: videoID) }
        let request = ResourceRequest(resource: "stream", type: type, id: videoID)

        return await withTaskGroup(of: (Int, AddonStreams).self) { group in
            for (index, addon) in candidates.enumerated() {
                group.addTask {
                    do {
                        let response = try await self.fetch(StreamsResponse.self, request, from: addon)
                        return (index, AddonStreams(addon: addon, streams: response.streams))
                    } catch {
                        return (index, AddonStreams(addon: addon, streams: [], errorMessage: error.localizedDescription))
                    }
                }
            }
            var collected: [(Int, AddonStreams)] = []
            for await item in group { collected.append(item) }
            return collected.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    // MARK: Subtitles

    public func subtitles(type: String, videoID: String, for stream: MediaStream?) async -> [Subtitle] {
        var extras: [ResourceRequest.Extra] = []
        if let hints = stream?.behaviorHints {
            if let hash = hints.videoHash { extras.append(.init("videoHash", hash)) }
            if let size = hints.videoSize { extras.append(.init("videoSize", String(size))) }
            if let filename = hints.filename { extras.append(.init("filename", filename)) }
        }
        let request = ResourceRequest(resource: "subtitles", type: type, id: videoID, extra: extras)
        let candidates = addons.filter { $0.supports(resource: "subtitles", type: type, id: videoID) }

        let lists = await withTaskGroup(of: (Int, [Subtitle]).self) { group in
            for (index, addon) in candidates.enumerated() {
                group.addTask {
                    let subs = (try? await self.fetch(SubtitlesResponse.self, request, from: addon).subtitles) ?? []
                    return (index, subs)
                }
            }
            var collected: [(Int, [Subtitle])] = []
            for await item in group { collected.append(item) }
            return collected.sorted { $0.0 < $1.0 }.flatMap { $0.1 }
        }

        // Subtitles attached to the stream itself come first.
        var seen = Set<String>()
        return ((stream?.subtitles ?? []) + lists).filter { seen.insert($0.url).inserted }
    }

    // MARK: Plumbing

    private func fetch<T: Decodable>(_ type: T.Type, _ request: ResourceRequest, from addon: InstalledAddon) async throws -> T {
        guard let transport = transports[addon.id] else { throw AddonError.invalidURL(addon.transportURL) }
        let data = try await transport.fetch(request)
        return try AddonDecoding.decode(type, from: data)
    }
}

/// Creates transports and installs add-ons from user input.
public struct AddonTransportFactory: Sendable {
    public let httpClient: HTTPClient
    public let builtIns: [BuiltInAddon]

    public init(httpClient: HTTPClient, builtIns: [BuiltInAddon]) {
        self.httpClient = httpClient
        self.builtIns = builtIns
    }

    public func transport(for transportURL: String) -> any AddonTransport {
        if let builtIn = builtIns.first(where: { $0.transportURL == transportURL }) {
            return builtIn
        }
        return HTTPAddonTransport(transportURL: transportURL, client: httpClient)
    }

    /// Validates the input, downloads the manifest and returns the add-on.
    public func install(from input: String) async throws -> InstalledAddon {
        let url = try TransportURL.normalize(input)
        let transport = HTTPAddonTransport(transportURL: url.absoluteString, client: httpClient)
        let manifest = try await transport.fetchManifest()
        return InstalledAddon(transportURL: url.absoluteString, manifest: manifest)
    }

    public var builtInAddons: [InstalledAddon] {
        builtIns.map { InstalledAddon(transportURL: $0.transportURL, manifest: $0.manifest) }
    }
}
