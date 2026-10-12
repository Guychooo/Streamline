import test from 'node:test';
import assert from 'node:assert/strict';
import {
  baseUrl, classifyStream, episodesOf, isBrowsable, isSearchable, languageName, normalizeLanguage,
  normalizeManifest, normalizeMeta, normalizeStream, normalizeTransportUrl, qualityTags, resourcePath,
  seasonsOf, supports,
} from '../js/protocol.js';
import { decodeSubtitleBytes, parseSubtitles, toWebVTT } from '../js/subtitles.js';
import { AddonClient, installAddon } from '../js/client.js';
import { makeOpenMovies } from '../js/openMovies.js';

test('manifest resource forms and matching', () => {
  const manifest = normalizeManifest({
    id: 'org.example', version: '1.2.0', name: 'Example', types: ['movie', 'series'], idPrefixes: ['tt'],
    resources: ['catalog', { name: 'stream', types: ['movie'], idPrefixes: ['tt', 'kitsu:'] }, 'meta', 42],
    catalogs: [
      { type: 'movie', id: 'top', name: 'Top', extra: [{ name: 'search' }, { name: 'skip' }] },
      { type: 'movie', id: 'find', extra: [{ name: 'search', isRequired: true }] },
      { type: 'series', id: 'genre', extra: [{ name: 'genre', isRequired: true, options: ['Drama'] }] },
      { id: 'broken' },
    ],
  });
  const addon = { transportUrl: 'https://a.example/manifest.json', manifest };
  assert.deepEqual(manifest.resources.map((r) => r.name), ['catalog', 'stream', 'meta']);
  assert.equal(supports(addon, 'stream', 'movie', 'kitsu:1'), true);
  assert.equal(supports(addon, 'stream', 'series', 'tt1'), false, 'object form overrides types');
  assert.equal(supports(addon, 'meta', 'series', 'tt1'), true);
  assert.equal(supports(addon, 'meta', 'series', 'kitsu:1'), false, 'short form inherits idPrefixes');
  assert.equal(supports(addon, 'subtitles', 'movie', 'tt1'), false);
  assert.deepEqual(manifest.catalogs.filter(isBrowsable).map((c) => c.id), ['top']);
  assert.deepEqual(manifest.catalogs.filter(isSearchable).map((c) => c.id), ['top', 'find']);
});

test('legacy extra fields', () => {
  const m = normalizeManifest({ id: 'x', name: 'X', catalogs: [{ type: 'movie', id: 'c', extraSupported: ['search', 'genre'], extraRequired: ['search'] }] });
  assert.equal(isBrowsable(m.catalogs[0]), false);
  assert.equal(isSearchable(m.catalogs[0]), true);
});

test('lenient meta and episode ordering', () => {
  const meta = normalizeMeta({
    id: 'tt9', type: 'series', name: 'Show', releaseInfo: 2014,
    videos: [
      { id: 'tt9:2:1', title: 'B1', season: 2, episode: 1 },
      { id: 'tt9:0:1', name: 'Special', season: 0, episode: 1 },
      { id: 'tt9:1:2', title: 'A2', season: '1', episode: '2' },
      { id: 'tt9:1:1', title: 'A1', season: 1, number: 1 },
      { title: 'no id' },
    ],
  });
  assert.equal(meta.releaseInfo, '2014');
  assert.deepEqual(seasonsOf(meta), [1, 2, 0]);
  assert.deepEqual(episodesOf(meta, 1).map((v) => v.title), ['A1', 'A2']);
  assert.equal(meta.videos.find((v) => v.season === 0).title, 'Special');
});

test('request paths and transport URLs', () => {
  assert.equal(resourcePath({ resource: 'stream', type: 'series', id: 'tt0944947:1:2' }), 'stream/series/tt0944947%3A1%3A2.json');
  assert.equal(
    resourcePath({ resource: 'catalog', type: 'movie', id: 'top', extra: [['search', 'the matrix & co'], ['skip', '100']] }),
    'catalog/movie/top/search=the%20matrix%20%26%20co&skip=100.json'
  );
  assert.equal(resourcePath({ resource: 'catalog', type: 'movie', id: 'top', extra: [['genre', '']] }), 'catalog/movie/top.json');
  assert.equal(normalizeTransportUrl(' stremio://addon.example.com/abc/manifest.json '), 'https://addon.example.com/abc/manifest.json');
  assert.equal(normalizeTransportUrl('https://addon.example.com/abc/'), 'https://addon.example.com/abc/manifest.json');
  assert.equal(normalizeTransportUrl('addon.example.com'), 'https://addon.example.com/manifest.json');
  assert.throws(() => normalizeTransportUrl('ipfs://abc/manifest.json'));
  assert.throws(() => normalizeTransportUrl('  '));
  assert.equal(baseUrl('https://a.example/x/manifest.json'), 'https://a.example/x');
});

test('extras round-trip through the SDK router parsing rules', async () => {
  // The SDK router takes the id from the decoded path param and parses extras
  // from the raw last segment with a query-string parser.
  const qs = await import('node:querystring');
  const path = resourcePath({ resource: 'catalog', type: 'movie', id: 'tt1:2', extra: [['search', 'a&b c=d'], ['skip', '20']] });
  const [resource, type, rawId, rawExtra] = path.split('/');
  assert.equal(resource, 'catalog');
  assert.equal(decodeURIComponent(rawId), 'tt1:2');
  assert.deepEqual({ ...qs.parse(rawExtra.slice(0, -5)) }, { search: 'a&b c=d', skip: '20' });
  assert.equal(type, 'movie');
});

test('stream classification for a browser', () => {
  const s = (raw) => normalizeStream(raw);
  assert.equal(classifyStream(s({ url: 'https://cdn/x.m3u8' })).kind, 'direct');
  assert.match(classifyStream(s({ url: 'http://cdn/x.mp4' })).warning, /Insecure/);
  assert.equal(classifyStream(s({ url: 'https://cdn/x.mp4', behaviorHints: { notWebReady: true, proxyHeaders: { request: { 'User-Agent': 'X' } } } })).kind, 'unsupported');
  assert.equal(classifyStream(s({ ytId: 'abc' })).url, 'https://www.youtube.com/watch?v=abc');
  assert.equal(classifyStream(s({ externalUrl: 'https://service.example/t/1' })).kind, 'external');
  assert.equal(classifyStream(s({ externalUrl: 'stremio:///detail/movie/tt1' })).kind, 'unsupported');
  assert.equal(classifyStream(s({ infoHash: 'abcdef' })).kind, 'unsupported');
  assert.equal(classifyStream(s({ url: 'magnet:?xt=urn:btih:abc' })).kind, 'unsupported');
  assert.equal(classifyStream(s({ rarUrls: [{ url: 'https://x/a.rar' }] })).kind, 'unsupported');
  assert.equal(classifyStream(s({})).kind, 'unsupported');
  assert.deepEqual(qualityTags(s({ name: 'Addon\n1080p', description: 'HDR10 WEB-DL' })), ['1080p', 'HDR']);
});

test('languages', () => {
  assert.equal(normalizeLanguage('eng'), 'en');
  assert.equal(normalizeLanguage('pt-BR'), 'pt');
  assert.equal(normalizeLanguage('ger'), 'de');
  assert.equal(languageName('eng', 'en'), 'English');
  assert.equal(languageName('fre', 'en'), 'French');
  assert.equal(languageName('und', 'en'), 'Unknown');
});

test('SRT, WebVTT and ASS parsing', () => {
  const srt = '﻿1\r\n00:00:01,000 --> 00:00:03,500\r\n<i>Hello</i> &amp; welcome\r\nSecond line\r\n\r\n2\r\n00:00:04,000 --> 00:00:05,000\r\n{\\an8}Top line\r\n';
  assert.deepEqual(parseSubtitles(srt), [
    { start: 1, end: 3.5, text: 'Hello & welcome\nSecond line' },
    { start: 4, end: 5, text: 'Top line' },
  ]);
  const vtt = 'WEBVTT\nKind: captions\n\nNOTE ignored\n\nintro\n00:01.000 --> 00:02.000 align:start\n<v Narrator>Short form</v>\n\n01:00:00.250 --> 01:00:01.000\nLong form\n';
  const cues = parseSubtitles(vtt);
  assert.deepEqual(cues.map((c) => c.text), ['Short form', 'Long form']);
  assert.equal(cues[1].start, 3600.25);
  const ass = '[Script Info]\nTitle: T\n\n[V4+ Styles]\nFormat: Name, Fontname\nStyle: Default,Arial\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:02.00,0:00:04.50,Default,,0,0,0,,{\\b1}Bold{\\b0}, with a comma\\Nand a break\nComment: 0,0:00:05.00,0:00:06.00,Default,,0,0,0,,ignored\n';
  assert.deepEqual(parseSubtitles(ass), [{ start: 2, end: 4.5, text: 'Bold, with a comma\nand a break' }]);
  assert.throws(() => parseSubtitles('WEBVTT\n\n'));
});

test('Windows-1252 fallback and WebVTT output with delay', () => {
  const bytes = new Uint8Array([...Buffer.from('1\n00:00:01,000 --> 00:00:02,000\nCaf'), 0xe9]);
  const cues = parseSubtitles(decodeSubtitleBytes(bytes.buffer));
  assert.equal(cues[0].text, 'Café');
  const out = toWebVTT([{ start: 1, end: 2, text: 'a < b --> c' }, { start: 0, end: 0.2, text: 'gone' }], -0.5);
  assert.equal(out, 'WEBVTT\n\n00:00:00.500 --> 00:00:01.500\na &lt; b → c\n');
  assert.deepEqual(parseSubtitles(out), [{ start: 0.5, end: 1.5, text: 'a < b → c' }]);
});

test('client: install, catalog, search, streams and subtitles across add-ons', async () => {
  const routes = {
    'https://a.example/manifest.json': { id: 'a', version: '1.0.0', name: 'Alpha', types: ['movie'], idPrefixes: ['tt'], resources: ['catalog', 'stream'], catalogs: [{ type: 'movie', id: 'pop', name: 'Popular', extra: [{ name: 'search' }] }] },
    'https://b.example/manifest.json': { id: 'b', version: '1.0.0', name: 'Beta', types: ['movie'], resources: ['stream', 'subtitles'], catalogs: [] },
    'https://a.example/catalog/movie/pop.json': { metas: [{ id: 'tt1', type: 'movie', name: 'One' }, { type: 'movie' }] },
    'https://a.example/catalog/movie/pop/search=one.json': { metas: [{ id: 'tt1', type: 'movie', name: 'One' }] },
    'https://a.example/stream/movie/tt1.json': { streams: [{ url: 'https://cdn.example/1.m3u8', name: '1080p' }] },
    'https://b.example/subtitles/movie/tt1/filename=one.mkv.json': { subtitles: [{ id: 's1', url: 'https://subs.example/1.srt', lang: 'eng' }] },
  };
  const fetcher = async (url) => {
    if (!(url in routes)) throw new Error(`404 ${url}`);
    return structuredClone(routes[url]);
  };
  const a = await installAddon('stremio://a.example/manifest.json', fetcher);
  const b = await installAddon('https://b.example', fetcher);
  const client = new AddonClient([a, b], { fetcher });

  assert.deepEqual((await client.catalog(a, a.manifest.catalogs[0])).map((m) => m.name), ['One']);
  const found = await client.search('one');
  assert.equal(found.length, 1);
  const groups = await client.streams('movie', 'tt1');
  assert.deepEqual(groups.map((g) => g.addon.manifest.name), ['Alpha', 'Beta']);
  assert.equal(groups[0].streams[0].name, '1080p');
  assert.ok(groups[1].error, 'a failing add-on reports its error instead of hiding others');

  const stream = normalizeStream({
    url: 'https://cdn.example/1.mkv',
    subtitles: [{ id: 'inline', url: 'https://subs.example/inline.vtt', lang: 'fre' }, { id: 'dup', url: 'https://subs.example/1.srt', lang: 'eng' }],
    behaviorHints: { filename: 'one.mkv' },
  });
  const subs = await client.subtitles('movie', 'tt1', stream);
  assert.deepEqual(subs.map((s) => s.url), ['https://subs.example/inline.vtt', 'https://subs.example/1.srt']);
});

test('built-in Open Movies add-on', async () => {
  const om = makeOpenMovies({ demoSubtitleUrl: 'https://app.example/demo-captions.vtt' });
  const addon = { transportUrl: om.transportUrl, manifest: om.manifest };
  const client = new AddonClient([addon], { builtIns: [om], fetcher: async () => { throw new Error('no network'); } });
  assert.equal((await client.catalog(addon, om.manifest.catalogs[0])).length, 4);
  assert.equal((await client.catalog(addon, om.manifest.catalogs[0], { skip: 100 })).length, 0);
  assert.deepEqual((await client.search('sintel')).flatMap((g) => g.metas).map((m) => m.name), ['Sintel']);
  const series = await client.meta('series', 'om:hls-test-streams');
  assert.equal(series.videos.length, 2);
  assert.equal(series.videos[0].streams.length, 1);
  const streams = await client.streams('series', 'om:hls-test-streams:1:1');
  assert.equal(classifyStream(streams[0].streams[0]).kind, 'direct');
  const subs = await client.subtitles('movie', 'om:big-buck-bunny');
  assert.equal(subs[0].label, 'English (demo captions)');
  assert.equal((await client.streams('movie', 'tt123')).length, 0, 'idPrefixes keep it out of other ids');
});

test('progress rules', async () => {
  globalThis.localStorage = { getItem: () => null, setItem: () => {} };
  const { isFinished, resumePosition } = await import('../js/store.js');
  assert.equal(resumePosition({ position: 20, duration: 3600 }), undefined, 'too early to resume');
  assert.equal(resumePosition({ position: 600, duration: 3600 }), 595);
  assert.equal(isFinished({ position: 3500, duration: 3600 }), true, 'credits on a long video');
  assert.equal(isFinished({ position: 40, duration: 90 }), false, 'short clip is not finished at 44%');
  assert.equal(isFinished({ position: 85, duration: 90 }), true);
});
