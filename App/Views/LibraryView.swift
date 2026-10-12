import SwiftUI
import StreamCore

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var fallback: MetaItem?

    var body: some View {
        NavigationStack {
            List {
                if !model.continueWatching.isEmpty {
                    Section("Continue Watching") {
                        ForEach(model.continueWatching) { progress in
                            Button {
                                Task {
                                    if !(await model.resume(progress)) {
                                        fallback = MetaItem(id: progress.metaID, type: progress.metaType,
                                                            name: progress.title, poster: progress.poster)
                                    }
                                }
                            } label: {
                                ProgressRow(progress: progress)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    Task { await model.removeProgress(progress) }
                                }
                            }
                        }
                    }
                }

                if !model.saved.isEmpty {
                    Section("Saved") {
                        ForEach(model.saved) { meta in
                            NavigationLink(value: meta) {
                                HStack(spacing: 12) {
                                    RemoteImage(url: meta.poster)
                                        .frame(width: 48, height: 70)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(meta.name).font(.subheadline.weight(.semibold))
                                        Text([ContentTypeLabel.text(for: meta.type), meta.releaseInfo].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if model.continueWatching.isEmpty && model.saved.isEmpty {
                    ContentUnavailableView(
                        "Your Library Is Empty",
                        systemImage: "books.vertical",
                        description: Text("Titles you save and videos you start watching show up here.")
                    )
                }
            }
            .navigationTitle("Library")
            .task { await model.refreshLibrary() }
            .refreshable { await model.refreshLibrary() }
            .navigationDestination(item: $fallback) { DetailView(preview: $0) }
            .appDestinations()
        }
    }
}

private struct ProgressRow: View {
    let progress: WatchProgress

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: progress.poster)
                .frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(progress.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let label = progress.episodeLabel {
                    Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                ProgressView(value: progress.fraction)
            }
        }
        .contentShape(Rectangle())
    }
}
