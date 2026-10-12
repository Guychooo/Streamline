import Foundation
import Observation
import StreamCore

/// Everything the player needs to start a stream.
struct PlaybackRequest: Identifiable {
    let id = UUID()
    let meta: MetaItem
    let video: Video?
    let stream: MediaStream
    let addonName: String?
    let url: URL
    let headers: [String: String]
    let startAt: TimeInterval?

    var videoID: String { video?.id ?? meta.id }

    /// "S1 · E2 · Title" for episodes, nil for movies.
    var subtitle: String? {
        guard let video else { return nil }
        let parts = [video.episodeLabel, video.title == meta.name ? nil : video.title].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

@MainActor
@Observable
final class AppModel {
    private(set) var addons: [InstalledAddon]
    private(set) var client: AddonClient
    private(set) var continueWatching: [WatchProgress] = []
    private(set) var saved: [MetaItem] = []
    /// Changes whenever the add-on list changes, so catalog rows reload.
    private(set) var addonsVersion = 0
    var nowPlaying: PlaybackRequest?

    @ObservationIgnored let library: LibraryStore
    @ObservationIgnored private let factory: AddonTransportFactory
    @ObservationIgnored private let registry: AddonRegistryStore

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Streamline", isDirectory: true)

        let demoCaptions = Bundle.main.url(forResource: "demo-captions", withExtension: "vtt")
        let builtIn = OpenMoviesAddon.make(demoSubtitleURL: demoCaptions)
        let factory = AddonTransportFactory(httpClient: URLSessionHTTPClient(), builtIns: [builtIn])
        let registry = AddonRegistryStore(fileURL: support.appendingPathComponent("addons.json"))

        // Built-in manifests ship with the app, so always use the current copy.
        let builtIns = factory.builtInAddons
        let stored = registry.load() ?? builtIns
        let current = stored.map { addon in builtIns.first { $0.id == addon.id } ?? addon }

        self.factory = factory
        self.registry = registry
        self.library = LibraryStore(fileURL: support.appendingPathComponent("library.json"))
        self.addons = current
        self.client = AddonClient(addons: current, factory: factory)
    }

    // MARK: Add-ons

    @discardableResult
    func installAddon(from input: String) async throws -> InstalledAddon {
        let addon = try await factory.install(from: input)
        if let index = addons.firstIndex(where: { $0.id == addon.id || $0.manifest.id == addon.manifest.id }) {
            addons[index] = addon
        } else {
            addons.append(addon)
        }
        addonsChanged()
        return addon
    }

    func removeAddons(at offsets: IndexSet) {
        addons.remove(atOffsets: offsets)
        addonsChanged()
    }

    func moveAddons(from source: IndexSet, to destination: Int) {
        addons.move(fromOffsets: source, toOffset: destination)
        addonsChanged()
    }

    var removedBuiltIns: [InstalledAddon] {
        factory.builtInAddons.filter { builtIn in !addons.contains { $0.id == builtIn.id } }
    }

    func restore(_ addon: InstalledAddon) {
        addons.insert(addon, at: 0)
        addonsChanged()
    }

    private func addonsChanged() {
        client = AddonClient(addons: addons, factory: factory)
        addonsVersion += 1
        try? registry.save(addons)
    }

    // MARK: Library

    func refreshLibrary() async {
        continueWatching = await library.continueWatching()
        saved = await library.current().saved
    }

    func toggleSaved(_ meta: MetaItem) async -> Bool {
        let isSaved = await library.toggleSaved(meta)
        await refreshLibrary()
        return isSaved
    }

    func removeProgress(_ progress: WatchProgress) async {
        await library.removeProgress(videoID: progress.videoID)
        await refreshLibrary()
    }

    // MARK: Playback

    func play(meta: MetaItem, video: Video?, stream: MediaStream, addonName: String?) async {
        guard case let .direct(url, headers) = PlaybackSource(stream: stream) else { return }
        let previous = await library.progress(for: video?.id ?? meta.id)
        nowPlaying = PlaybackRequest(
            meta: meta,
            video: video,
            stream: stream,
            addonName: addonName,
            url: url,
            headers: headers,
            startAt: previous?.resumePosition
        )
    }

    /// Resumes the exact stream that was playing. Returns false when the
    /// saved stream is missing, so the caller can open the detail page instead.
    func resume(_ progress: WatchProgress) async -> Bool {
        guard let stream = progress.stream, PlaybackSource(stream: stream).isPlayableInApp else { return false }
        let meta = MetaItem(id: progress.metaID, type: progress.metaType, name: progress.title, poster: progress.poster)
        let video = progress.videoID == progress.metaID
            ? nil
            : Video(id: progress.videoID, title: progress.episodeLabel ?? progress.title)
        await play(meta: meta, video: video, stream: stream, addonName: progress.addonName)
        return true
    }
}
