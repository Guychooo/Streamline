import SwiftUI
import StreamCore

struct DetailView: View {
    @Environment(AppModel.self) private var model
    let preview: MetaItem

    @State private var meta: MetaItem?
    @State private var isLoading = true
    @State private var season: Int?
    @State private var isSaved = false
    @State private var showFullDescription = false

    private var item: MetaItem { meta ?? preview }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if item.isSingleVideo {
                    StreamsSection(meta: item, video: nil)
                        .padding(.horizontal)
                } else {
                    episodes
                }
            }
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { isSaved = await model.toggleSaved(item) }
                } label: {
                    Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                }
            }
        }
        .task(id: preview.id) { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        let full = await model.client.meta(type: preview.type, id: preview.id)
        meta = full?.merging(fallback: preview) ?? preview
        if season == nil {
            season = item.seasons.first
        }
        isSaved = await model.library.isSaved(preview.id)
        isLoading = false
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: item.background ?? item.poster)
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .clipped()
                LinearGradient(colors: [.clear, Color(.systemBackground)], startPoint: .center, endPoint: .bottom)
                Text(item.name)
                    .font(.largeTitle.bold())
                    .padding(.horizontal)
                    .shadow(radius: 6)
            }
            .frame(height: 260)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if let year = item.releaseInfo { Text(year) }
                    if let runtime = item.runtime { Text(runtime) }
                    if let rating = item.imdbRating {
                        Label(rating, systemImage: "star.fill").labelStyle(.titleAndIcon)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let genres = item.genres, !genres.isEmpty {
                    Text(genres.joined(separator: " · "))
                        .font(.subheadline)
                }

                if let description = item.description {
                    Text(description)
                        .font(.body)
                        .lineLimit(showFullDescription ? nil : 4)
                        .onTapGesture { withAnimation { showFullDescription.toggle() } }
                }

                if let cast = item.cast, !cast.isEmpty {
                    Text("Cast: " + cast.prefix(6).joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: Episodes

    private var episodes: some View {
        VStack(alignment: .leading, spacing: 12) {
            let seasons = item.seasons
            if seasons.count > 1 {
                Picker("Season", selection: Binding(get: { season ?? seasons[0] }, set: { season = $0 })) {
                    ForEach(seasons, id: \.self) { number in
                        Text(number == 0 ? "Specials" : "Season \(number)").tag(number)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
            }

            LazyVStack(spacing: 0) {
                ForEach(item.episodes(inSeason: seasons.isEmpty ? nil : season)) { video in
                    NavigationLink(value: EpisodeRoute(meta: item, video: video)) {
                        EpisodeRow(video: video)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading)
                }
            }
        }
    }
}

struct EpisodeRow: View {
    let video: Video

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let thumbnail = video.thumbnail {
                RemoteImage(url: thumbnail)
                    .frame(width: 120, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                if let label = video.episodeLabel {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
                Text(video.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let overview = video.overview {
                    Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct EpisodeStreamsView: View {
    let meta: MetaItem
    let video: Video

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                EpisodeRow(video: video)
                StreamsSection(meta: meta, video: video)
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle(video.episodeLabel ?? video.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
