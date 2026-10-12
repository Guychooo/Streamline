// Stremio add-on protocol: URLs, manifests, matching and lenient models.
// https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md

export const BUILTIN_SCHEME = 'builtin://';

const str = (v) => (typeof v === 'string' ? v : typeof v === 'number' ? String(v) : undefined);
const int = (v) => {
  if (typeof v === 'number' && Number.isFinite(v)) return Math.trunc(v);
  if (typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v))) return Math.trunc(Number(v));
  return undefined;
};
const strArray = (v) => (Array.isArray(v) ? v.filter((x) => typeof x === 'string') : undefined);
const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

/** Maps each element and drops the ones that fail, so one bad item never hides a list. */
export function lossy(list, fn) {
  if (!Array.isArray(list)) return [];
  const out = [];
  for (const item of list) {
    try {
      const value = fn(item);
      if (value) out.push(value);
    } catch {
      /* skip malformed element */
    }
  }
  return out;
}

// ---------------------------------------------------------------- URLs

export class AddonError extends Error {}

/** Turns what someone pastes into a canonical https manifest URL. */
export function normalizeTransportUrl(input) {
  let text = String(input ?? '').trim();
  if (!text) throw new AddonError('Enter an add-on address.');
  if (/^stremio:\/\//i.test(text)) text = 'https://' + text.slice('stremio://'.length);
  else if (!text.includes('://')) text = 'https://' + text;

  let url;
  try {
    url = new URL(text);
  } catch {
    throw new AddonError(`"${input}" isn't a valid add-on address.`);
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') {
    throw new AddonError(`Add-ons served over ${url.protocol.replace(':', '')} aren't supported. Use an https manifest URL.`);
  }
  if (!url.hostname) throw new AddonError(`"${input}" isn't a valid add-on address.`);
  let path = url.pathname.replace(/\/+$/, '');
  if (!path.endsWith('/manifest.json')) path += '/manifest.json';
  url.pathname = path;
  url.hash = '';
  return url.toString();
}

export function baseUrl(manifestUrl) {
  return manifestUrl.split('?')[0].replace(/\/manifest\.json$/, '').replace(/\/+$/, '');
}

/**
 * `{resource}/{type}/{id}[/{extra}].json`, encoded the way the official SDK
 * router decodes it: segments with encodeURIComponent, extras as a query string.
 */
export function resourcePath({ resource, type, id, extra = [] }) {
  const segments = [resource, type, id].map(encodeURIComponent);
  const extras = extra.filter(([, value]) => value !== undefined && value !== null && String(value) !== '');
  if (extras.length) {
    segments.push(extras.map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&'));
  }
  return segments.join('/') + '.json';
}

// ---------------------------------------------------------------- Manifest

function normalizeResource(raw) {
  if (typeof raw === 'string') return { name: raw, short: true };
  if (!isObject(raw) || typeof raw.name !== 'string') return null;
  return { name: raw.name, types: strArray(raw.types), idPrefixes: strArray(raw.idPrefixes), short: false };
}

function normalizeCatalog(raw) {
  if (!isObject(raw) || typeof raw.type !== 'string' || str(raw.id) === undefined) return null;
  let extra;
  if (Array.isArray(raw.extra)) {
    extra = lossy(raw.extra, (e) =>
      isObject(e) && typeof e.name === 'string'
        ? { name: e.name, isRequired: e.isRequired === true, options: strArray(e.options) }
        : null
    );
  } else {
    // Older manifests use two string arrays.
    const supported = strArray(raw.extraSupported) ?? [];
    const required = new Set(strArray(raw.extraRequired) ?? []);
    extra = supported.map((name) => ({ name, isRequired: required.has(name) }));
    for (const name of required) if (!supported.includes(name)) extra.push({ name, isRequired: true });
  }
  return { type: raw.type, id: str(raw.id), name: str(raw.name), extra };
}

export function normalizeManifest(raw) {
  if (!isObject(raw) || typeof raw.id !== 'string' || typeof raw.name !== 'string') {
    throw new AddonError('That address did not return an add-on manifest.');
  }
  return {
    id: raw.id,
    version: str(raw.version) ?? '0.0.0',
    name: raw.name,
    description: str(raw.description),
    logo: str(raw.logo),
    types: strArray(raw.types) ?? [],
    idPrefixes: strArray(raw.idPrefixes),
    resources: lossy(raw.resources, normalizeResource),
    catalogs: lossy(raw.catalogs, normalizeCatalog),
    behaviorHints: isObject(raw.behaviorHints) ? raw.behaviorHints : {},
  };
}

/** Whether `addon` should be asked for `resource` on an item of `type` with `id`. */
export function supports(addon, resource, type, id) {
  const m = addon.manifest;
  const entry = m.resources.find((r) => r.name === resource);
  if (!entry) return false;
  const types = entry.short ? m.types : entry.types ?? m.types;
  const prefixes = entry.short ? m.idPrefixes : entry.idPrefixes;
  if (!types.includes(type)) return false;
  if (!prefixes || prefixes.length === 0) return true;
  return prefixes.some((p) => id.startsWith(p));
}

export const isBrowsable = (c) => !c.extra.some((e) => e.isRequired);
export const isSearchable = (c) =>
  c.extra.some((e) => e.name === 'search') && c.extra.every((e) => !e.isRequired || e.name === 'search');
export const supportsPaging = (c) => c.extra.some((e) => e.name === 'skip');
export const catalogName = (c) => c.name || c.id.charAt(0).toUpperCase() + c.id.slice(1);

// ---------------------------------------------------------------- Meta

export function normalizeSubtitle(raw) {
  if (!isObject(raw) || typeof raw.url !== 'string') return null;
  return { id: str(raw.id) ?? raw.url, url: raw.url, lang: str(raw.lang) ?? 'und', label: str(raw.label) };
}

export function normalizeStream(raw) {
  if (!isObject(raw)) return null;
  const hints = isObject(raw.behaviorHints) ? raw.behaviorHints : {};
  const archive = ['rarUrls', 'zipUrls', '7zipUrls', 'tgzUrls', 'tarUrls'].some((k) => k in raw);
  return {
    url: str(raw.url),
    ytId: str(raw.ytId),
    infoHash: str(raw.infoHash),
    fileIdx: int(raw.fileIdx),
    externalUrl: str(raw.externalUrl),
    nzbUrl: str(raw.nzbUrl),
    archive,
    name: str(raw.name),
    description: str(raw.description) ?? str(raw.title),
    subtitles: lossy(raw.subtitles, normalizeSubtitle),
    behaviorHints: {
      notWebReady: hints.notWebReady === true,
      proxyHeaders: isObject(hints.proxyHeaders) ? hints.proxyHeaders : undefined,
      filename: str(hints.filename),
      videoHash: str(hints.videoHash),
      videoSize: int(hints.videoSize),
    },
  };
}

export function normalizeVideo(raw) {
  if (!isObject(raw) || str(raw.id) === undefined) return null;
  const season = int(raw.season);
  const episode = int(raw.episode) ?? int(raw.number);
  return {
    id: str(raw.id),
    title: str(raw.title) ?? str(raw.name) ?? (episode !== undefined ? `Episode ${episode}` : 'Video'),
    released: str(raw.released),
    thumbnail: str(raw.thumbnail),
    overview: str(raw.overview) ?? str(raw.description),
    season,
    episode,
    streams: Array.isArray(raw.streams) ? lossy(raw.streams, normalizeStream) : undefined,
  };
}

export function normalizeMeta(raw) {
  if (!isObject(raw) || str(raw.id) === undefined) return null;
  return {
    id: str(raw.id),
    type: str(raw.type) ?? 'other',
    name: str(raw.name) ?? 'Untitled',
    poster: str(raw.poster),
    posterShape: ['poster', 'square', 'landscape'].includes(raw.posterShape) ? raw.posterShape : 'poster',
    background: str(raw.background),
    logo: str(raw.logo),
    description: str(raw.description),
    releaseInfo: str(raw.releaseInfo) ?? str(raw.year),
    imdbRating: str(raw.imdbRating),
    runtime: str(raw.runtime),
    genres: strArray(raw.genres),
    cast: strArray(raw.cast),
    videos: Array.isArray(raw.videos) ? lossy(raw.videos, normalizeVideo) : undefined,
  };
}

/** Fills fields missing in `meta` from `fallback` (usually the catalog preview). */
export function mergeMeta(meta, fallback) {
  if (!meta) return fallback;
  if (!fallback) return meta;
  const out = { ...meta };
  for (const key of ['poster', 'background', 'logo', 'description', 'releaseInfo', 'imdbRating', 'genres', 'runtime']) {
    if (out[key] === undefined) out[key] = fallback[key];
  }
  return out;
}

export const isSingleVideo = (meta) => !meta.videos || meta.videos.length === 0;

/** Season numbers ascending, specials (0) last. */
export function seasonsOf(meta) {
  const all = new Set((meta.videos ?? []).map((v) => v.season).filter((s) => s !== undefined));
  const regular = [...all].filter((s) => s > 0).sort((a, b) => a - b);
  return all.has(0) ? [...regular, 0] : regular;
}

export function episodesOf(meta, season) {
  const list = (meta.videos ?? []).filter((v) => season === undefined || v.season === season);
  return list.sort((a, b) => (a.episode ?? 0) - (b.episode ?? 0) || String(a.released ?? '').localeCompare(String(b.released ?? '')));
}

export function episodeLabel(video) {
  if (!video) return undefined;
  if (video.season !== undefined && video.episode !== undefined) return `S${video.season} · E${video.episode}`;
  if (video.episode !== undefined) return `E${video.episode}`;
  return undefined;
}

// ---------------------------------------------------------------- Playback

/**
 * What a browser on iPhone can do with a stream.
 * kind: direct | youtube | external | unsupported
 */
export function classifyStream(stream, { secureContext = true } = {}) {
  if (stream.url) {
    let url;
    try {
      url = new URL(stream.url);
    } catch {
      return { kind: 'unsupported', reason: 'The stream address is malformed.' };
    }
    const scheme = url.protocol.replace(':', '');
    if (scheme === 'magnet') return { kind: 'unsupported', reason: "Torrent links can't play in a browser." };
    if (scheme !== 'http' && scheme !== 'https') {
      return { kind: 'unsupported', reason: `${scheme.toUpperCase()} links can't play in a browser.` };
    }
    if (stream.behaviorHints.proxyHeaders?.request && Object.keys(stream.behaviorHints.proxyHeaders.request).length) {
      return { kind: 'unsupported', reason: 'This stream needs custom request headers, which browsers can’t send.' };
    }
    const warnings = [];
    if (secureContext && scheme === 'http') warnings.push('Insecure http link. Safari may block it.');
    if (stream.behaviorHints.notWebReady) warnings.push('The add-on says this format may not play in a browser.');
    return { kind: 'direct', url: url.toString(), warning: warnings.join(' ') || undefined };
  }
  if (stream.ytId) {
    return { kind: 'youtube', url: `https://www.youtube.com/watch?v=${encodeURIComponent(stream.ytId)}` };
  }
  if (stream.externalUrl) {
    if (/^https?:\/\//i.test(stream.externalUrl)) return { kind: 'external', url: stream.externalUrl };
    return { kind: 'unsupported', reason: 'This link only works inside the Stremio app.' };
  }
  if (stream.infoHash) {
    return { kind: 'unsupported', reason: 'Torrent streams need a local streaming server, which a phone browser can’t run.' };
  }
  if (stream.nzbUrl || stream.archive) {
    return { kind: 'unsupported', reason: 'Usenet and archive sources aren’t supported.' };
  }
  return { kind: 'unsupported', reason: 'The stream has no playable source.' };
}

/** Pulls recognisable quality tags out of a stream's name and description. */
export function qualityTags(stream) {
  const text = `${stream.name ?? ''} ${stream.description ?? ''}`;
  const tags = [];
  const res = text.match(/\b(2160p|4k|1440p|1080p|720p|480p|360p)\b/i);
  if (res) tags.push(res[1].toLowerCase() === '4k' ? '4K' : res[1].toLowerCase());
  if (/\b(HDR10\+?|HDR|DV|Dolby ?Vision)\b/i.test(text)) tags.push('HDR');
  if (/\bHLS\b|\.m3u8/i.test(text + (stream.url ?? ''))) tags.push('HLS');
  return tags;
}

// ---------------------------------------------------------------- Languages

const ISO639_2_TO_1 = {
  eng: 'en', fre: 'fr', fra: 'fr', ger: 'de', deu: 'de', spa: 'es', ita: 'it', por: 'pt', rus: 'ru',
  jpn: 'ja', kor: 'ko', chi: 'zh', zho: 'zh', ara: 'ar', heb: 'he', hin: 'hi', tur: 'tr', pol: 'pl',
  dut: 'nl', nld: 'nl', swe: 'sv', nor: 'no', nob: 'nb', dan: 'da', fin: 'fi', gre: 'el', ell: 'el',
  cze: 'cs', ces: 'cs', hun: 'hu', rum: 'ro', ron: 'ro', ukr: 'uk', vie: 'vi', tha: 'th', ind: 'id',
  may: 'ms', msa: 'ms', per: 'fa', fas: 'fa', bul: 'bg', hrv: 'hr', srp: 'sr', slo: 'sk', slk: 'sk',
  slv: 'sl', est: 'et', lav: 'lv', lit: 'lt', cat: 'ca', baq: 'eu', eus: 'eu', glg: 'gl', ice: 'is', isl: 'is',
  ben: 'bn', tam: 'ta', tel: 'te', urd: 'ur', fil: 'fil', tgl: 'tl',
};

/** "en-US", "eng" and "en" all become "en". */
export function normalizeLanguage(code) {
  if (!code || typeof code !== 'string') return undefined;
  const base = code.split(/[-_]/)[0].toLowerCase();
  return ISO639_2_TO_1[base] ?? base;
}

// Used when the browser has no language-name data of its own.
const ENGLISH_NAMES = {
  en: 'English', fr: 'French', de: 'German', es: 'Spanish', it: 'Italian', pt: 'Portuguese', ru: 'Russian',
  ja: 'Japanese', ko: 'Korean', zh: 'Chinese', ar: 'Arabic', he: 'Hebrew', hi: 'Hindi', tr: 'Turkish',
  pl: 'Polish', nl: 'Dutch', sv: 'Swedish', no: 'Norwegian', nb: 'Norwegian Bokmål', da: 'Danish',
  fi: 'Finnish', el: 'Greek', cs: 'Czech', hu: 'Hungarian', ro: 'Romanian', uk: 'Ukrainian',
  vi: 'Vietnamese', th: 'Thai', id: 'Indonesian', ms: 'Malay', fa: 'Persian', bg: 'Bulgarian',
  hr: 'Croatian', sr: 'Serbian', sk: 'Slovak', sl: 'Slovenian', et: 'Estonian', lv: 'Latvian',
  lt: 'Lithuanian', ca: 'Catalan', eu: 'Basque', gl: 'Galician', is: 'Icelandic', bn: 'Bengali',
  ta: 'Tamil', te: 'Telugu', ur: 'Urdu', fil: 'Filipino', tl: 'Tagalog',
};

export function languageName(code, locale) {
  const normalized = normalizeLanguage(code);
  if (!normalized || normalized === 'und') return 'Unknown';
  try {
    const names = new Intl.DisplayNames([locale ?? (globalThis.navigator?.language || 'en')], { type: 'language' });
    const name = names.of(normalized);
    if (name && name.toLowerCase() !== normalized) return name.charAt(0).toUpperCase() + name.slice(1);
  } catch {
    /* fall through */
  }
  // Otherwise the protocol says to show the raw value.
  return ENGLISH_NAMES[normalized] ?? code;
}

export const subtitleName = (s) => s.label || languageName(s.lang);
