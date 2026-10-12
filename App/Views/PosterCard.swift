import SwiftUI
import StreamCore

struct RemoteImage: View {
    let url: String?
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            default:
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct PosterCard: View {
    let meta: MetaItem

    private var shape: PosterShape { meta.posterShape ?? .poster }

    private var width: CGFloat {
        switch shape {
        case .poster: return 116
        case .square: return 136
        case .landscape: return 220
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: meta.poster)
                .frame(width: width, height: width / shape.aspectRatio)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(meta.name)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .leading)
            if let year = meta.releaseInfo {
                Text(year)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
