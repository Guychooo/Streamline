import SwiftUI
import StreamCore

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var fallback: MetaItem?

    private var rows: [CatalogRoute] {
        model.addons.flatMap { addon in addon.browsableCatalogs.map { CatalogRoute(addon: addon, catalog: $0) } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    if !model.continueWatching.isEmpty {
                        ContinueWatchingRow(items: model.continueWatching) { fallback = $0 }
                    }
                    ForEach(rows, id: \.self) { row in
                        CatalogRow(addon: row.addon, catalog: row.catalog)
                    }
                }
                .padding(.vertical)
            }
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView(
                        "No Catalogs",
                        systemImage: "puzzlepiece.extension",
                        description: Text("Install an add-on with a catalog from the Add-ons tab.")
                    )
                }
            }
            .navigationTitle("Discover")
            .refreshable { await model.refreshLibrary() }
            .navigationDestination(item: $fallback) { DetailView(preview: $0) }
            .appDestinations()
        }
    }
}

struct ContinueWatchingRow: View {
    @Environment(AppModel.self) private var model
    let items: [WatchProgress]
    /// Called when the saved stream can't be resumed, to open the title instead.
    let openTitle: (MetaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Continue Watching")
                .font(.title3.bold())
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { progress in
                        Button {
                            Task {
                                if !(await model.resume(progress)) {
                                    openTitle(MetaItem(id: progress.metaID, type: progress.metaType, name: progress.title, poster: progress.poster))
                                }
                            }
                        } label: {
                            ProgressCard(progress: progress)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove", systemImage: "xmark.circle", role: .destructive) {
                                Task { await model.removeProgress(progress) }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct ProgressCard: View {
    let progress: WatchProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                RemoteImage(url: progress.poster)
                    .frame(width: 200, height: 112)
                    .clipped()
                ProgressView(value: progress.fraction)
                    .tint(.accentColor)
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(progress.title).font(.footnote.weight(.medium)).lineLimit(1)
            Text(progress.episodeLabel ?? remaining)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 200, alignment: .leading)
    }

    private var remaining: String {
        let minutes = Int((progress.duration - progress.position) / 60)
        return "\(max(minutes, 1)) min left"
    }
}
