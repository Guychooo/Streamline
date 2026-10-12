import Foundation

/// How far someone got through a video.
public struct WatchProgress: Codable, Hashable, Sendable, Identifiable {
    public var videoID: String
    public var metaID: String
    public var metaType: String
    public var title: String
    public var episodeLabel: String?
    public var poster: String?
    public var position: TimeInterval
    public var duration: TimeInterval
    public var updatedAt: Date
    /// The stream that was playing, so "continue watching" can resume it directly.
    public var stream: MediaStream?
    public var addonName: String?

    public init(
        videoID: String,
        metaID: String,
        metaType: String,
        title: String,
        episodeLabel: String? = nil,
        poster: String? = nil,
        position: TimeInterval,
        duration: TimeInterval,
        updatedAt: Date = Date(),
        stream: MediaStream? = nil,
        addonName: String? = nil
    ) {
        self.videoID = videoID
        self.metaID = metaID
        self.metaType = metaType
        self.title = title
        self.episodeLabel = episodeLabel
        self.poster = poster
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
        self.stream = stream
        self.addonName = addonName
    }

    public var id: String { videoID }

    public var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// Treated as watched at 92%, or with under two minutes left on anything
    /// longer than 20 minutes (the end credits). Short clips use the percentage only.
    public var isFinished: Bool {
        guard duration > 0 else { return false }
        return fraction >= 0.92 || (duration > 1200 && duration - position < 120)
    }

    /// Where to resume, or nil to start from the beginning.
    public var resumePosition: TimeInterval? {
        guard position >= 30, !isFinished else { return nil }
        return max(position - 5, 0)
    }
}

public struct LibrarySnapshot: Codable, Sendable, Equatable {
    public var progress: [String: WatchProgress] = [:]
    public var saved: [MetaItem] = []
    public init() {}
}

/// Persists watch progress and saved titles as a JSON file.
public actor LibraryStore {
    private let fileURL: URL
    private var snapshot: LibrarySnapshot

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(LibrarySnapshot.self, from: data) {
            snapshot = decoded
        } else {
            snapshot = LibrarySnapshot()
        }
    }

    public func current() -> LibrarySnapshot { snapshot }

    /// In-progress items, most recent first.
    public func continueWatching() -> [WatchProgress] {
        snapshot.progress.values
            .filter { !$0.isFinished && $0.position >= 30 }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func progress(for videoID: String) -> WatchProgress? {
        snapshot.progress[videoID]
    }

    public func record(_ progress: WatchProgress) {
        snapshot.progress[progress.videoID] = progress
        persist()
    }

    public func removeProgress(videoID: String) {
        snapshot.progress[videoID] = nil
        persist()
    }

    public func isSaved(_ metaID: String) -> Bool {
        snapshot.saved.contains { $0.id == metaID }
    }

    /// Adds or removes a title; returns whether it is saved afterwards.
    @discardableResult
    public func toggleSaved(_ meta: MetaItem) -> Bool {
        if let index = snapshot.saved.firstIndex(where: { $0.id == meta.id }) {
            snapshot.saved.remove(at: index)
            persist()
            return false
        }
        var compact = meta
        compact.videos = nil  // keep the file small; details are re-fetched
        snapshot.saved.insert(compact, at: 0)
        persist()
        return true
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Losing a progress update is not worth interrupting playback for.
        }
    }
}

/// Persists the installed add-on list.
public struct AddonRegistryStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> [InstalledAddon]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([InstalledAddon].self, from: data)
    }

    public func save(_ addons: [InstalledAddon]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(addons).write(to: fileURL, options: .atomic)
    }
}
