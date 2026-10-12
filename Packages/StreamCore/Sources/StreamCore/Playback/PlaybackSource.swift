import Foundation

/// What the app can do with a stream on iPhone.
public enum PlaybackSource: Hashable, Sendable {
    /// Plays in the built-in player. Headers come from `proxyHeaders.request`.
    case direct(url: URL, headers: [String: String])
    /// Opens in the YouTube app or website.
    case youtube(videoID: String, url: URL)
    /// Opens in the browser, e.g. a link to a service's own website.
    case external(URL)
    case unsupported(reason: String)

    public init(stream: MediaStream) {
        if let raw = stream.url {
            guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else {
                self = .unsupported(reason: "The stream address is malformed.")
                return
            }
            switch scheme {
            case "http", "https", "file":
                self = .direct(url: url, headers: stream.behaviorHints?.proxyHeaders?.request ?? [:])
            case "magnet":
                self = .unsupported(reason: "Torrent links aren't supported on iPhone.")
            default:
                self = .unsupported(reason: "\(scheme.uppercased()) links can't be played on iPhone.")
            }
            return
        }
        if let ytId = stream.ytId,
           let url = URL(string: "https://www.youtube.com/watch?v=\(ytId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ytId)") {
            self = .youtube(videoID: ytId, url: url)
            return
        }
        if let raw = stream.externalUrl {
            if let url = URL(string: raw), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                self = .external(url)
            } else {
                self = .unsupported(reason: "This link only works inside the Stremio app.")
            }
            return
        }
        if stream.infoHash != nil {
            self = .unsupported(reason: "Torrent streams need a local streaming server, which iPhone apps can't run.")
            return
        }
        if stream.nzbUrl != nil || stream.hasArchiveSources {
            self = .unsupported(reason: "Usenet and archive sources aren't supported on iPhone.")
            return
        }
        self = .unsupported(reason: "The stream doesn't include a playable source.")
    }

    public var isPlayableInApp: Bool {
        if case .direct = self { return true }
        return false
    }

    public var unsupportedReason: String? {
        if case .unsupported(let reason) = self { return reason }
        return nil
    }
}
