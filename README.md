# Streamline

A native iPhone video streaming app built on the open
[Stremio add-on protocol](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md).
Catalogs, metadata, streams and subtitles all come from add-ons: small HTTP
services that answer `/{resource}/{type}/{id}.json`. Any add-on that follows
the protocol works, and the app ships with one built-in add-on of openly
licensed films so it plays something on first launch.

## What it does

- **Discover** shows a row for every browsable catalog of every installed add-on,
  plus a Continue Watching row. "See All" opens a paged grid.
- **Search** queries every catalog that declares the `search` extra, in parallel.
- **Detail pages** show metadata, a season picker and an episode list. Movies
  list their streams inline. Streams are grouped by add-on, and a failing add-on
  shows its error without hiding the others.
- **Player** uses `AVPlayerViewController`, so you get the system controls,
  AirPlay, Picture in Picture, playback speed and background audio.
  - **Audio menu** lists every audio rendition inside the stream (HLS alternate
    audio or multi-track files) and switches between them.
  - **Subtitles menu** lists subtitle renditions inside the stream *and*
    subtitle files offered by add-ons. Add-on subtitles in SRT, WebVTT and
    ASS/SSA are parsed in the app and drawn over the video, with a timing
    adjustment in 0.25 s steps.
  - The app remembers your last audio and subtitle language and picks them
    again on the next video.
- **Library** keeps resume points and saved titles. Resuming reopens the exact
  stream that was playing.
- **Add-ons** installs add-ons from a manifest URL or a `stremio://` install
  link, and lets you reorder or remove them. Order decides which add-on answers
  metadata first.

### Stream types

| Stream field | On iPhone |
| --- | --- |
| `url` (http, https, HLS, MP4) | Plays in the app, with `proxyHeaders.request` sent as HTTP headers |
| `ytId` | Opens YouTube |
| `externalUrl` | Opens in the browser |
| `infoHash`, `nzbUrl`, archive sources | Listed but disabled. They need Stremio's local streaming server, which an iOS app can't run. |

### The built-in "Open Movies" add-on

- **Open Movies catalog:** Big Buck Bunny, Elephants Dream, Sintel and Tears of
  Steel. These are Blender Foundation films licensed CC BY 3.0, streamed from
  Google's public sample bucket. Big Buck Bunny also offers a demo caption track
  so you can try add-on subtitles.
- **HLS Test Streams series:** Unified Streaming's multi-language Tears of
  Steel stream and Apple's advanced HLS example. Use these to try the audio and
  subtitle menus with tracks that live inside the stream.

## Web app (no Mac needed)

`docs/` is the same app for Safari. It needs no build step, and it lives in
`docs/` because GitHub Pages can serve that folder directly. On iPhone, open it in Safari and
choose Share, then Add to Home Screen, to get a full-screen app icon.

- **Playback.** Safari plays MP4 and HLS natively, including the HLS audio and
  subtitle renditions. Other browsers load hls.js for HLS.
- **Add-on subtitles.** SRT, WebVTT and ASS files are converted to WebVTT tracks,
  so they also show in Safari's native full-screen player.
- **Saved data.** Add-ons, progress and saved titles live in the browser's local
  storage on that device.
- **Browser limits.** Add-ons and subtitle servers must allow cross-origin
  requests, which the protocol requires. Streams that need custom request
  headers can't play in a browser, and plain-http streams may be blocked on an
  https page. The app explains this next to each affected stream.

Run the web tests with Node 22 or later:

```sh
cd docs
node --test tests/core.test.mjs
```

To try it locally, serve the folder with any static server, for example
`npx serve docs`.

## Build and run

You need a Mac with Xcode 15 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
cd Streamline
xcodegen generate
open Streamline.xcodeproj
```

Then choose your team under Signing & Capabilities, change the bundle
identifier from `com.example.streamline` if needed, and run on an iPhone or
the simulator. The app targets iOS 17.

### Run the unit tests

The protocol client, subtitle parser and library store live in a Swift package
with no UIKit dependency:

```sh
cd Packages/StreamCore
swift test
```

## Project layout

```
docs/                       Web app for Safari (served by GitHub Pages)
project.yml                 XcodeGen project definition
App/                        SwiftUI app target
  Model/AppModel.swift      Installed add-ons, library, what's playing
  Views/                    Discover, Search, Detail, Library, Add-ons
  Player/                   AVPlayer wrapper, track menus, subtitle overlay
  Resources/                Asset catalog and demo captions
Packages/StreamCore/        Platform-independent core
  Models/                   Manifest, meta, stream and subtitle types
  Addons/                   Request encoding, HTTP and built-in transports, client
  Playback/                 Stream classification, SRT/WebVTT/ASS parser
  Library/                  Watch progress and saved titles
```

## How it follows the protocol

- **Requests** are `{base}/{resource}/{type}/{id}.json`, with the id encoded
  like JavaScript's `encodeURIComponent`. Extras such as `search` and `skip` go
  in an extra path segment as a query string, which is what the official SDK
  router parses.
- **Resource matching** follows the manifest rules. A resource listed as a
  bare string inherits the manifest's `types` and `idPrefixes`. One listed as an
  object uses its own, and no `idPrefixes` there means every id.
- **Videos with embedded `streams`** use those streams only, as the protocol
  requires.
- **Tolerant decoding.** Malformed items in a list are skipped instead of
  failing the whole response, because community add-ons vary.
