import SwiftUI
import StreamCore

struct CatalogRow: View {
    @Environment(AppModel.self) private var model
    let addon: InstalledAddon
    let catalog: CatalogDescriptor
    @State private var state: LoadState<[MetaItem]> = .loading

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(catalog.displayName).font(.title3.bold())
                    Text("\(ContentTypeLabel.text(for: catalog.type)) · \(addon.manifest.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                NavigationLink("See All", value: CatalogRoute(addon: addon, catalog: catalog))
                    .font(.subheadline)
            }
            .padding(.horizontal)

            switch state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            case .loaded(let items) where items.isEmpty:
                Text("Nothing in this catalog right now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            case .loaded(let items):
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(items.prefix(30).enumerated()), id: \.offset) { _, meta in
                            NavigationLink(value: meta) { PosterCard(meta: meta) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .task(id: model.addonsVersion) { await load() }
    }

    @MainActor
    private func load() async {
        state = .loading
        do {
            state = .loaded(try await model.client.catalog(catalog, from: addon))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct CatalogGridView: View {
    @Environment(AppModel.self) private var model
    let addon: InstalledAddon
    let catalog: CatalogDescriptor

    @State private var items: [MetaItem] = []
    @State private var isLoading = false
    @State private var reachedEnd = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, meta in
                    NavigationLink(value: meta) { PosterCard(meta: meta) }
                        .buttonStyle(.plain)
                        .onAppear {
                            if index == items.count - 1 { Task { await loadMore() } }
                        }
                }
            }
            .padding()

            if isLoading {
                ProgressView().padding()
            } else if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.secondary).padding()
            }
        }
        .navigationTitle(catalog.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { if items.isEmpty { await loadMore() } }
    }

    @MainActor
    private func loadMore() async {
        guard !isLoading, !reachedEnd else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await model.client.catalog(catalog, from: addon, skip: items.count)
            let known = Set(items.map(\.id))
            let fresh = page.filter { !known.contains($0.id) }
            items.append(contentsOf: fresh)
            // Add-ons that ignore `skip` return the same page again.
            if fresh.isEmpty || !catalog.supportsPaging { reachedEnd = true }
        } catch {
            errorMessage = error.localizedDescription
            reachedEnd = true
        }
    }
}
