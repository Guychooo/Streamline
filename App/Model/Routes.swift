import SwiftUI
import StreamCore

struct CatalogRoute: Hashable {
    let addon: InstalledAddon
    let catalog: CatalogDescriptor
}

struct EpisodeRoute: Hashable {
    let meta: MetaItem
    let video: Video
}

enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)
}

extension View {
    /// Registers the screens every tab can push.
    func appDestinations() -> some View {
        self
            .navigationDestination(for: MetaItem.self) { DetailView(preview: $0) }
            .navigationDestination(for: CatalogRoute.self) { CatalogGridView(addon: $0.addon, catalog: $0.catalog) }
            .navigationDestination(for: EpisodeRoute.self) { EpisodeStreamsView(meta: $0.meta, video: $0.video) }
    }
}

enum ContentTypeLabel {
    static func text(for type: String) -> String {
        switch type {
        case "movie": return "Movies"
        case "series": return "Series"
        case "channel": return "Channels"
        case "tv": return "Live TV"
        default: return type.capitalized
        }
    }
}
