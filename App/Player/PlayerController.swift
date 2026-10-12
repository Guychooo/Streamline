import AVFoundation
import Foundation
import Observation
import StreamCore

enum SubtitleSelection: Hashable {
    case off
    /// A legible rendition inside the stream, e.g. an HLS subtitle playlist.
    case embedded(String)
    /// A subtitle file offered by an add-on or attached to the stream.
    case external(String)
}

struct MediaOptionItem: Identifiable {
    let id: String
    let name: String
    let language: String?
    let option: AVMediaSelectionOption
}

/// Owns the AVPlayer and everything around it: track menus, add-on
/// subtitles, resume points and saving progress.
@MainActor
@Observable
final class PlayerController {
    let request: PlaybackRequest
    @ObservationIgnored let player: AVPlayer

    private(set) var audioOptions: [MediaOptionItem] = []
    private(set) var embeddedSubtitles: [MediaOptionItem] = []
    private(set) var externalSubtitles: [Subtitle] = []
    private(set) var selectedAudioID: String?
    private(set) var subtitleSelection: SubtitleSelection = .off
    private(set) var subtitleText: String?
    private(set) var subtitleDelay: TimeInterval = 0
    private(set) var notice: String?
    private(set) var failureMessage: String?

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var audibleGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var legibleGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var externalTrack: SubtitleTrack?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var lastSavedPosition: TimeInterval = -.infinity
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var hasBegunPlayback = false
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    private static let subtitleLanguageKey = "preferredSubtitleLanguage"
    private static let audioLanguageKey = "preferredAudioLanguage"

    init(request: PlaybackRequest, model: AppModel) {
        self.request = request
        self.model = model
        // Add-ons can require request headers (behaviorHints.proxyHeaders).
        let options: [String: Any]? = request.headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": request.headers]
        let asset = AVURLAsset(url: request.url, options: options)
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
    }

    // MARK: Lifecycle

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)

        observeItem()
        addTimeObserver()

        await loadMediaOptions()
        if let model {
            externalSubtitles = await model.client.subtitles(
                type: request.meta.type,
                videoID: request.videoID,
                for: request.stream
            )
        }
        applySavedPreferences()
    }

    func stop() {
        let position = player.currentTime().seconds
        if position.isFinite { saveProgress(at: position, force: true) }
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        noticeTask?.cancel()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observeItem() {
        guard let item = player.currentItem else { return }
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            Task { @MainActor in self?.handle(status: status, errorMessage: message) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didPlayToEnd() }
        }
    }

    private func handle(status: AVPlayerItem.Status, errorMessage: String?) {
        switch status {
        case .readyToPlay:
            guard !hasBegunPlayback else { return }
            hasBegunPlayback = true
            if let start = request.startAt {
                let target = CMTime(seconds: start, preferredTimescale: 600)
                player.seek(to: target, toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)) { [weak self] _ in
                    Task { @MainActor in self?.player.play() }
                }
                showNotice("Resuming from \(Self.format(start))")
            } else {
                player.play()
            }
        case .failed:
            failureMessage = errorMessage ?? "This stream couldn't be played."
        default:
            break
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(value: 1, timescale: 10)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
    }

    private func tick(_ seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        let text = externalTrack?.text(at: seconds - subtitleDelay)
        if text != subtitleText { subtitleText = text }
        if abs(seconds - lastSavedPosition) >= 10 {
            saveProgress(at: seconds)
        }
    }

    private func didPlayToEnd() {
        let duration = player.currentItem?.duration.seconds ?? 0
        if duration.isFinite { saveProgress(at: duration, force: true) }
    }

    // MARK: Progress

    private func saveProgress(at position: TimeInterval, force: Bool = false) {
        guard let model, let item = player.currentItem else { return }
        let duration = item.duration.seconds
        // Live streams have no finite duration and nothing to resume.
        guard duration.isFinite, duration > 0, position.isFinite else { return }
        guard force || hasBegunPlayback else { return }
        lastSavedPosition = position
        let progress = WatchProgress(
            videoID: request.videoID,
            metaID: request.meta.id,
            metaType: request.meta.type,
            title: request.meta.name,
            episodeLabel: request.subtitle,
            poster: request.meta.background ?? request.meta.poster ?? request.video?.thumbnail,
            position: position,
            duration: duration,
            stream: request.stream,
            addonName: request.addonName
        )
        let library = model.library
        Task { await library.record(progress) }
    }

    // MARK: Tracks inside the stream

    private func loadMediaOptions() async {
        guard let item = player.currentItem else { return }
        let asset = item.asset

        if let group = try? await asset.loadMediaSelectionGroup(for: .audible) {
            audibleGroup = group
            audioOptions = group.options.enumerated().map { index, option in
                MediaOptionItem(id: "audio-\(index)", name: Self.displayName(for: option),
                                language: Self.languageCode(of: option), option: option)
            }
            if let selected = item.currentMediaSelection.selectedMediaOption(in: group) {
                selectedAudioID = audioOptions.first { $0.option == selected }?.id
            }
        }

        if let group = try? await asset.loadMediaSelectionGroup(for: .legible) {
            legibleGroup = group
            embeddedSubtitles = group.options
                .filter { !$0.hasMediaCharacteristic(.containsOnlyForcedSubtitles) }
                .enumerated()
                .map { index, option in
                    MediaOptionItem(id: "text-\(index)", name: Self.displayName(for: option),
                                    language: Self.languageCode(of: option), option: option)
                }
            if let selected = item.currentMediaSelection.selectedMediaOption(in: group),
               let match = embeddedSubtitles.first(where: { $0.option == selected }) {
                subtitleSelection = .embedded(match.id)
            }
        }
    }

    func selectAudio(_ id: String?) {
        guard let id, let item = player.currentItem, let group = audibleGroup,
              let option = audioOptions.first(where: { $0.id == id }) else { return }
        item.select(option.option, in: group)
        selectedAudioID = id
        if let language = option.language {
            UserDefaults.standard.set(language, forKey: Self.audioLanguageKey)
        }
    }

    // MARK: Subtitles

    func selectSubtitle(_ selection: SubtitleSelection, remember: Bool = true) {
        guard let item = player.currentItem else { return }
        switch selection {
        case .off:
            clearExternal()
            if let group = legibleGroup, group.allowsEmptySelection { item.select(nil, in: group) }
            subtitleSelection = .off
            if remember { UserDefaults.standard.set("off", forKey: Self.subtitleLanguageKey) }

        case .embedded(let id):
            guard let group = legibleGroup, let option = embeddedSubtitles.first(where: { $0.id == id }) else { return }
            clearExternal()
            item.select(option.option, in: group)
            subtitleSelection = selection
            if remember, let language = option.language {
                UserDefaults.standard.set(language, forKey: Self.subtitleLanguageKey)
            }

        case .external(let id):
            guard let subtitle = externalSubtitles.first(where: { $0.id == id }) else { return }
            if let group = legibleGroup, group.allowsEmptySelection { item.select(nil, in: group) }
            subtitleSelection = selection
            if remember, let language = LanguageMatching.normalize(subtitle.lang) {
                UserDefaults.standard.set(language, forKey: Self.subtitleLanguageKey)
            }
            Task { await loadExternal(subtitle) }
        }
    }

    private func clearExternal() {
        externalTrack = nil
        subtitleText = nil
    }

    private func loadExternal(_ subtitle: Subtitle) async {
        clearExternal()
        showNotice("Loading \(subtitle.displayName) subtitles…", autoHide: false)
        do {
            guard let url = URL(string: subtitle.url) else { throw URLError(.badURL) }
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                data = try await URLSession.shared.data(from: url).0
            }
            let cues = try await Task.detached(priority: .userInitiated) {
                try SubtitleParser.parse(data: data)
            }.value
            // The person may have picked something else while this loaded.
            guard subtitleSelection == .external(subtitle.id) else { return }
            externalTrack = SubtitleTrack(cues: cues)
            showNotice("\(subtitle.displayName) subtitles on")
        } catch {
            guard subtitleSelection == .external(subtitle.id) else { return }
            subtitleSelection = .off
            showNotice("Couldn't load subtitles. \(error.localizedDescription)")
        }
    }

    func shiftSubtitles(by delta: TimeInterval) {
        subtitleDelay += delta
        let formatted = String(format: "%+.2f s", subtitleDelay)
        showNotice(subtitleDelay == 0 ? "Subtitle timing reset" : "Subtitle delay \(formatted)")
    }

    func resetSubtitleDelay() {
        subtitleDelay = 0
        showNotice("Subtitle timing reset")
    }

    /// Re-applies the languages chosen in earlier sessions.
    private func applySavedPreferences() {
        let defaults = UserDefaults.standard
        if let audio = defaults.string(forKey: Self.audioLanguageKey),
           let match = audioOptions.first(where: { LanguageMatching.normalize($0.language) == audio }),
           match.id != selectedAudioID {
            selectAudio(match.id)
        }

        guard let preferred = defaults.string(forKey: Self.subtitleLanguageKey) else { return }
        if preferred == "off" {
            selectSubtitle(.off, remember: false)
        } else if let match = embeddedSubtitles.first(where: { LanguageMatching.normalize($0.language) == preferred }) {
            selectSubtitle(.embedded(match.id), remember: false)
        } else if let match = externalSubtitles.first(where: { LanguageMatching.normalize($0.lang) == preferred }) {
            selectSubtitle(.external(match.id), remember: false)
        }
    }

    // MARK: Notices

    private func showNotice(_ text: String, autoHide: Bool = true) {
        noticeTask?.cancel()
        notice = text
        guard autoHide else { return }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    // MARK: Helpers

    private static func displayName(for option: AVMediaSelectionOption) -> String {
        var name = option.displayName
        if option.hasMediaCharacteristic(.describesMusicAndSoundForAccessibility) {
            name += " (SDH)"
        } else if option.hasMediaCharacteristic(.describesVideoForAccessibility) {
            name += " (Audio Description)"
        }
        return name
    }

    private static func languageCode(of option: AVMediaSelectionOption) -> String? {
        option.extendedLanguageTag ?? option.locale?.identifier
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

enum LanguageMatching {
    /// Reduces "en-US", "eng" and "en" to the same two-letter code where possible.
    static func normalize(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        let base = code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { String($0).lowercased() } ?? code.lowercased()
        return Locale.LanguageCode(base).identifier(.alpha2) ?? base
    }
}
