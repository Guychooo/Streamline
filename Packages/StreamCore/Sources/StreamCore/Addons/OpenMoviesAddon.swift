import Foundation

/// A built-in add-on serving openly licensed films and public HLS test
/// streams, so the app has something legitimate to play out of the box.
///
/// The Blender Foundation films are released under Creative Commons
/// Attribution 3.0. The HLS streams are public test streams published for
/// player developers.
public enum OpenMoviesAddon {
    public static let slug = "open-movies"

    private static let googleSamples = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/"
    private static let blenderCredit = "© Blender Foundation · CC BY 3.0 · blender.org"

    /// - Parameter demoSubtitleURL: A bundled WebVTT file offered as an
    ///   add-on subtitle for Big Buck Bunny, to exercise external subtitles.
    public static func make(demoSubtitleURL: URL? = nil) -> BuiltInAddon {
        let films: [(id: String, name: String, file: String, image: String, year: String, runtime: String, genres: [String], blurb: String)] = [
            ("om:big-buck-bunny", "Big Buck Bunny", "BigBuckBunny.mp4", "BigBuckBunny.jpg", "2008", "10m",
             ["Animation", "Comedy"],
             "A good-natured giant rabbit finally loses patience with three woodland bullies in this dialogue-free animated short."),
            ("om:elephants-dream", "Elephants Dream", "ElephantsDream.mp4", "ElephantsDream.jpg", "2006", "11m",
             ["Animation", "Science Fiction"],
             "Two men explore a vast, surreal machine that one of them believes he understands. The first Blender open movie."),
            ("om:sintel", "Sintel", "Sintel.mp4", "Sintel.jpg", "2010", "15m",
             ["Animation", "Fantasy"],
             "A young woman travels across a harsh world searching for the baby dragon she once rescued."),
            ("om:tears-of-steel", "Tears of Steel", "TearsOfSteel.mp4", "TearsOfSteel.jpg", "2012", "12m",
             ["Science Fiction", "Action"],
             "A group of scientists in Amsterdam try to rewrite a painful moment from the past to stop a robot uprising.")
        ]

        var responses: [String: any Encodable] = [:]
        var metas: [MetaItem] = []

        for film in films {
            let meta = MetaItem(
                id: film.id,
                type: "movie",
                name: film.name,
                poster: googleSamples + "images/" + film.image,
                posterShape: .landscape,
                background: googleSamples + "images/" + film.image,
                description: film.blurb + "\n\n" + blenderCredit,
                releaseInfo: film.year,
                runtime: film.runtime,
                genres: film.genres
            )
            metas.append(meta)
            responses[ResourceRequest(resource: "meta", type: "movie", id: film.id).path] = ["meta": meta]

            let stream = MediaStream(
                url: googleSamples + film.file,
                name: "MP4",
                description: "Direct file · \(film.name)",
                behaviorHints: StreamBehaviorHints(filename: film.file)
            )
            responses[ResourceRequest(resource: "stream", type: "movie", id: film.id).path] = ["streams": [stream]]
        }

        // A "series" whose episodes are public HLS test streams that carry
        // alternate audio and subtitle renditions inside the playlist.
        let testChannel = MetaItem(
            id: "om:hls-test-streams",
            type: "series",
            name: "HLS Test Streams",
            posterShape: .landscape,
            description: "Public HLS streams made for testing video players. Use them to try the audio and subtitle menus: the tracks come from inside each stream.",
            releaseInfo: "2024-",
            genres: ["Test"],
            videos: [
                Video(
                    id: "om:hls-test-streams:1:1",
                    title: "Tears of Steel (multi-language HLS)",
                    overview: "Adaptive stream with several audio and subtitle languages. \(blenderCredit)",
                    season: 1,
                    episode: 1,
                    streams: [MediaStream(
                        url: "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8",
                        name: "HLS",
                        description: "Unified Streaming public demo"
                    )]
                ),
                Video(
                    id: "om:hls-test-streams:1:2",
                    title: "Apple advanced HLS example",
                    overview: "Apple's fMP4 example stream with subtitles and multiple variants.",
                    season: 1,
                    episode: 2,
                    streams: [MediaStream(
                        url: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8",
                        name: "HLS",
                        description: "Apple developer example"
                    )]
                )
            ]
        )
        responses[ResourceRequest(resource: "meta", type: "series", id: testChannel.id).path] = ["meta": testChannel]
        for video in testChannel.videos ?? [] {
            responses[ResourceRequest(resource: "stream", type: "series", id: video.id).path] = ["streams": video.streams ?? []]
        }

        if let demoSubtitleURL {
            let subtitle = Subtitle(id: "om-demo-en", url: demoSubtitleURL.absoluteString, lang: "eng", label: "English (demo captions)")
            responses[ResourceRequest(resource: "subtitles", type: "movie", id: "om:big-buck-bunny").path] = ["subtitles": [subtitle]]
        }

        var catalogPreview = testChannel
        catalogPreview.videos = nil
        responses[ResourceRequest(resource: "catalog", type: "movie", id: "open-movies").path] = ["metas": metas]
        responses[ResourceRequest(resource: "catalog", type: "series", id: "hls-tests").path] = ["metas": [catalogPreview]]

        let manifest = Manifest(
            id: "app.streamline.open-movies",
            version: "1.0.0",
            name: "Open Movies",
            description: "Creative Commons films from the Blender Foundation and public HLS test streams.",
            types: ["movie", "series"],
            idPrefixes: ["om:"],
            resources: [.short("catalog"), .short("meta"), .short("stream"), .short("subtitles")],
            catalogs: [
                CatalogDescriptor(type: "movie", id: "open-movies", name: "Open Movies",
                                  extra: [ExtraProperty(name: "search"), ExtraProperty(name: "skip")]),
                CatalogDescriptor(type: "series", id: "hls-tests", name: "HLS Test Streams",
                                  extra: [ExtraProperty(name: "search")])
            ]
        )
        return BuiltInAddon(slug: slug, manifest: manifest, responses: responses)
    }
}
