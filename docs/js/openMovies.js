// A built-in add-on with openly licensed films and public HLS test streams,
// so the app has something legitimate to play on first launch.
import { BUILTIN_SCHEME, normalizeManifest, resourcePath } from './protocol.js';

const SAMPLES = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/';
const CREDIT = '© Blender Foundation · CC BY 3.0 · blender.org';

const FILMS = [
  {
    id: 'om:big-buck-bunny', name: 'Big Buck Bunny', file: 'BigBuckBunny', year: '2008', runtime: '10m',
    genres: ['Animation', 'Comedy'],
    blurb: 'A good-natured giant rabbit finally loses patience with three woodland bullies in this dialogue-free animated short.',
  },
  {
    id: 'om:elephants-dream', name: 'Elephants Dream', file: 'ElephantsDream', year: '2006', runtime: '11m',
    genres: ['Animation', 'Science Fiction'],
    blurb: 'Two men explore a vast, surreal machine that one of them believes he understands. The first Blender open movie.',
  },
  {
    id: 'om:sintel', name: 'Sintel', file: 'Sintel', year: '2010', runtime: '15m',
    genres: ['Animation', 'Fantasy'],
    blurb: 'A young woman travels across a harsh world searching for the baby dragon she once rescued.',
  },
  {
    id: 'om:tears-of-steel', name: 'Tears of Steel', file: 'TearsOfSteel', year: '2012', runtime: '12m',
    genres: ['Science Fiction', 'Action'],
    blurb: 'A group of scientists in Amsterdam try to rewrite a painful moment from the past to stop a robot uprising.',
  },
];

const HLS_SERIES = {
  id: 'om:hls-test-streams',
  type: 'series',
  name: 'HLS Test Streams',
  posterShape: 'landscape',
  description:
    'Public HLS streams made for testing video players. Use them to try the audio and subtitle menus: the tracks come from inside each stream.',
  releaseInfo: '2024-',
  genres: ['Test'],
  videos: [
    {
      id: 'om:hls-test-streams:1:1',
      title: 'Tears of Steel (multi-language HLS)',
      overview: `Adaptive stream with several audio and subtitle languages. ${CREDIT}`,
      season: 1,
      episode: 1,
      streams: [{
        url: 'https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8',
        name: 'HLS',
        description: 'Unified Streaming public demo',
      }],
    },
    {
      id: 'om:hls-test-streams:1:2',
      title: 'Apple advanced HLS example',
      overview: 'Apple’s fMP4 example stream with subtitles and multiple variants.',
      season: 1,
      episode: 2,
      streams: [{
        url: 'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8',
        name: 'HLS',
        description: 'Apple developer example',
      }],
    },
  ],
};

export function makeOpenMovies({ demoSubtitleUrl } = {}) {
  const responses = new Map();
  const put = (request, body) => responses.set(resourcePath(request), body);

  const metas = FILMS.map((f) => ({
    id: f.id,
    type: 'movie',
    name: f.name,
    poster: `${SAMPLES}images/${f.file}.jpg`,
    posterShape: 'landscape',
    background: `${SAMPLES}images/${f.file}.jpg`,
    description: `${f.blurb}\n\n${CREDIT}`,
    releaseInfo: f.year,
    runtime: f.runtime,
    genres: f.genres,
  }));
  for (const [i, meta] of metas.entries()) {
    put({ resource: 'meta', type: 'movie', id: meta.id }, { meta });
    put({ resource: 'stream', type: 'movie', id: meta.id }, {
      streams: [{
        url: `${SAMPLES}${FILMS[i].file}.mp4`,
        name: 'MP4',
        description: `Direct file · ${meta.name}`,
        behaviorHints: { filename: `${FILMS[i].file}.mp4` },
      }],
    });
  }
  put({ resource: 'meta', type: 'series', id: HLS_SERIES.id }, { meta: HLS_SERIES });
  for (const video of HLS_SERIES.videos) {
    put({ resource: 'stream', type: 'series', id: video.id }, { streams: video.streams });
  }
  if (demoSubtitleUrl) {
    put({ resource: 'subtitles', type: 'movie', id: 'om:big-buck-bunny' }, {
      subtitles: [{ id: 'om-demo-en', url: demoSubtitleUrl, lang: 'eng', label: 'English (demo captions)' }],
    });
  }
  const { videos, ...seriesPreview } = HLS_SERIES;
  put({ resource: 'catalog', type: 'movie', id: 'open-movies' }, { metas });
  put({ resource: 'catalog', type: 'series', id: 'hls-tests' }, { metas: [seriesPreview] });

  const manifest = normalizeManifest({
    id: 'app.streamline.open-movies',
    version: '1.0.0',
    name: 'Open Movies',
    description: 'Creative Commons films from the Blender Foundation and public HLS test streams.',
    types: ['movie', 'series'],
    idPrefixes: ['om:'],
    resources: ['catalog', 'meta', 'stream', 'subtitles'],
    catalogs: [
      { type: 'movie', id: 'open-movies', name: 'Open Movies', extra: [{ name: 'search' }, { name: 'skip' }] },
      { type: 'series', id: 'hls-tests', name: 'HLS Test Streams', extra: [{ name: 'search' }] },
    ],
  });

  return {
    transportUrl: BUILTIN_SCHEME + 'open-movies',
    manifest,
    /** Answers like a real add-on: search filters the catalog, later pages are empty. */
    async answer(request) {
      const extra = new Map(request.extra ?? []);
      const unfiltered = responses.get(resourcePath({ ...request, extra: [] }));
      if (unfiltered) {
        if (request.resource === 'catalog' && extra.has('search')) {
          const needle = String(extra.get('search')).toLowerCase();
          return {
            metas: unfiltered.metas.filter(
              (m) => m.name.toLowerCase().includes(needle) || (m.description ?? '').toLowerCase().includes(needle)
            ),
          };
        }
        if (extra.has('skip') && extra.get('skip') !== '0') return { metas: [] };
        return structuredClone(unfiltered);
      }
      const empty = { catalog: 'metas', stream: 'streams', subtitles: 'subtitles' }[request.resource];
      if (empty) return { [empty]: [] };
      throw new Error('Not found');
    },
  };
}
