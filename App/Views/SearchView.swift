import SwiftUI
import StreamCore

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [SearchResults] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(results) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(group.catalog.displayName) · \(group.addon.manifest.name)")
                                .font(.headline)
                                .padding(.horizontal)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 12) {
                                    ForEach(Array(group.metas.enumerated()), id: \.offset) { _, meta in
                                        NavigationLink(value: meta) { PosterCard(meta: meta) }
                                            .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .overlay { overlay }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Movies, series, channels")
            .task(id: query) { await search() }
            .appDestinations()
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if isSearching && results.isEmpty {
            ProgressView()
        } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView("Search Your Add-ons", systemImage: "magnifyingglass",
                                   description: Text("Searches every installed add-on that supports search."))
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }

    @MainActor
    private func search() async {
        let text = query
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        // Debounce typing.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        let found = await model.client.search(text)
        guard !Task.isCancelled else { return }
        results = found
    }
}
