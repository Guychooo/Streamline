import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "play.square.stack") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            AddonsView()
                .tabItem { Label("Add-ons", systemImage: "puzzlepiece.extension") }
        }
        .fullScreenCover(item: $model.nowPlaying, onDismiss: {
            Task { await model.refreshLibrary() }
        }) { request in
            PlayerScreen(request: request, model: model)
        }
        .task { await model.refreshLibrary() }
    }
}
