// Talks to every installed add-on and merges their answers.
import {
  AddonError, BUILTIN_SCHEME, baseUrl, isSearchable, lossy, normalizeManifest, normalizeMeta,
  normalizeStream, normalizeSubtitle, normalizeTransportUrl, resourcePath, supports,
} from './protocol.js';

export async function fetchJson(url, { timeout = 20000 } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);
  try {
    let response;
    try {
      response = await fetch(url, { signal: controller.signal, headers: { Accept: 'application/json' } });
    } catch (error) {
      if (error.name === 'AbortError') throw new AddonError('The add-on took too long to answer.');
      throw new AddonError('Couldn’t reach the add-on. Check the address and your connection.');
    }
    if (response.status === 404) throw new AddonError('The add-on has nothing for this request.');
    if (!response.ok) throw new AddonError(`The add-on answered with HTTP ${response.status}.`);
    try {
      return await response.json();
    } catch {
      throw new AddonError('The add-on sent a response this app couldn’t read.');
    }
  } finally {
    clearTimeout(timer);
  }
}

export class AddonClient {
  /**
   * @param addons   installed add-ons: { transportUrl, manifest }
   * @param builtIns built-in add-ons: { transportUrl, manifest, answer(request) }
   */
  constructor(addons, { builtIns = [], fetcher = fetchJson } = {}) {
    this.addons = addons;
    this.builtIns = new Map(builtIns.map((b) => [b.transportUrl, b]));
    this.fetcher = fetcher;
  }

  async request(addon, request) {
    if (addon.transportUrl.startsWith(BUILTIN_SCHEME)) {
      const builtIn = this.builtIns.get(addon.transportUrl);
      if (!builtIn) throw new AddonError('This built-in add-on is no longer available.');
      return builtIn.answer(request);
    }
    return this.fetcher(`${baseUrl(addon.transportUrl)}/${resourcePath(request)}`);
  }

  async catalog(addon, catalog, { skip = 0, extra = [] } = {}) {
    const extras = [...extra];
    if (skip > 0) extras.push(['skip', String(skip)]);
    const json = await this.request(addon, { resource: 'catalog', type: catalog.type, id: catalog.id, extra: extras });
    return lossy(json?.metas, normalizeMeta);
  }

  async search(query) {
    const q = query.trim();
    if (!q) return [];
    const jobs = this.addons.flatMap((addon) => addon.manifest.catalogs.filter(isSearchable).map((catalog) => ({ addon, catalog })));
    const results = await Promise.all(
      jobs.map(async ({ addon, catalog }) => {
        try {
          const metas = await this.catalog(addon, catalog, { extra: [['search', q]] });
          return metas.length ? { addon, catalog, metas } : null;
        } catch {
          return null;
        }
      })
    );
    return results.filter(Boolean);
  }

  /** First meta-capable add-on, in install order, that answers. */
  async meta(type, id) {
    for (const addon of this.addons) {
      if (!supports(addon, 'meta', type, id)) continue;
      try {
        const meta = normalizeMeta((await this.request(addon, { resource: 'meta', type, id }))?.meta);
        if (meta) return meta;
      } catch {
        /* try the next add-on */
      }
    }
    return null;
  }

  /** Streams from every add-on that claims the video, grouped and in install order. */
  async streams(type, videoId) {
    const candidates = this.addons.filter((a) => supports(a, 'stream', type, videoId));
    return Promise.all(
      candidates.map(async (addon) => {
        try {
          const json = await this.request(addon, { resource: 'stream', type, id: videoId });
          return { addon, streams: lossy(json?.streams, normalizeStream) };
        } catch (error) {
          return { addon, streams: [], error: error.message };
        }
      })
    );
  }

  /** Stream-attached subtitles first, then add-on subtitles, without duplicates. */
  async subtitles(type, videoId, stream) {
    const extra = [];
    const hints = stream?.behaviorHints ?? {};
    if (hints.videoHash) extra.push(['videoHash', hints.videoHash]);
    if (hints.videoSize) extra.push(['videoSize', String(hints.videoSize)]);
    if (hints.filename) extra.push(['filename', hints.filename]);
    const candidates = this.addons.filter((a) => supports(a, 'subtitles', type, videoId));
    const lists = await Promise.all(
      candidates.map(async (addon) => {
        try {
          const json = await this.request(addon, { resource: 'subtitles', type, id: videoId, extra });
          return lossy(json?.subtitles, normalizeSubtitle);
        } catch {
          return [];
        }
      })
    );
    const seen = new Set();
    return [...(stream?.subtitles ?? []), ...lists.flat()].filter((s) => !seen.has(s.url) && seen.add(s.url));
  }
}

/** Validates the input, downloads the manifest and returns the add-on. */
export async function installAddon(input, fetcher = fetchJson) {
  const transportUrl = normalizeTransportUrl(input);
  const manifest = normalizeManifest(await fetcher(transportUrl));
  return { transportUrl, manifest };
}
