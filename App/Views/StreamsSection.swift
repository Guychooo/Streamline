import SwiftUI
import StreamCore

/// Lists streams for one video, grouped by the add-on that returned them.
struct StreamsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let meta: MetaItem
    let video: Video?

    @State private var groups: [AddonStreams] = []
    @State private var isLoading = true

    private var videoID: String { video?.id ?? meta.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Streams").font(.title3.bold())

            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if groups.allSatisfy({ $0.streams.isEmpty }) {
                ContentUnavailableView(
                    "No Streams",
                    systemImage: "play.slash",
                    description: Text(emptyMessage)
                )
            }

            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.addon.manifest.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let error = group.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(group.streams.enumerated()), id: \.offset) { _, stream in
                        StreamButton(stream: stream) { open(stream, addonName: group.addon.manifest.name) }
                    }
                }
            }
        }
        .task(id: videoID + "|\(model.addonsVersion)") { await load() }
    }

    private var emptyMessage: String {
        groups.isEmpty
            ? "None of your add-ons provide streams for this title."
            : "Your add-ons didn't return any streams for this title."
    }

    @MainActor
    private func load() async {
        isLoading = true
        // Per the protocol, streams embedded in the video are used exclusively.
        if let embedded = video?.streams, !embedded.isEmpty {
            let owner = model.addons.first { $0.supports(resource: "meta", type: meta.type, id: meta.id) }
                ?? InstalledAddon(transportURL: "embedded", manifest: Manifest(
                    id: "embedded", version: "1", name: "Included", types: [], resources: [], catalogs: []))
            groups = [AddonStreams(addon: owner, streams: embedded)]
        } else {
            groups = await model.client.streams(type: meta.type, videoID: videoID)
        }
        isLoading = false
    }

    @MainActor
    private func open(_ stream: MediaStream, addonName: String) {
        switch PlaybackSource(stream: stream) {
        case .direct:
            Task { await model.play(meta: meta, video: video, stream: stream, addonName: addonName) }
        case .youtube(_, let url), .external(let url):
            openURL(url)
        case .unsupported:
            break
        }
    }
}

private struct StreamButton: View {
    let stream: MediaStream
    let action: () -> Void

    private var source: PlaybackSource { PlaybackSource(stream: stream) }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(source.unsupportedReason == nil ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(stream.displayName)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.leading)
                    if let description = stream.displayDescription {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(4)
                    }
                    if let reason = source.unsupportedReason {
                        Text(reason).font(.caption2).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(source.unsupportedReason != nil)
        .opacity(source.unsupportedReason == nil ? 1 : 0.6)
    }

    private var icon: String {
        switch source {
        case .direct: return "play.circle.fill"
        case .youtube: return "play.rectangle"
        case .external: return "safari"
        case .unsupported: return "nosign"
        }
    }
}
