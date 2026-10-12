import { AddonClient, installAddon } from './client.js';
import { makeOpenMovies } from './openMovies.js';
import { openPlayer } from './player.js';
import {
  catalogName, classifyStream, episodeLabel, episodesOf, isBrowsable, isSingleVideo, mergeMeta,
  qualityTags, seasonsOf, supportsPaging,
} from './protocol.js';
import { Library, loadAddons, progressFraction, saveAddons } from './store.js';

// ---------------------------------------------------------------- State

const openMovies = makeOpenMovies({ demoSubtitleUrl: new URL('demo-captions.vtt', document.baseURI).href });
const BUILT_INS = [openMovies];
const builtInAddons = BUILT_INS.map(({ transportUrl, manifest }) => ({ transportUrl, manifest }));

const state = {
  addons: initialAddons(),
  library: new Library(),
  metaCache: new Map(), // "type/id" -> meta, so detail pages draw instantly
  search: '',
  scroll: new Map(),
};
state.client = makeClient();

function initialAddons() {
  const stored = loadAddons();
  if (!Array.isArray(stored)) return [...builtInAddons];
  // Built-in manifests ship with the page, so always use the current copy.
  return stored
    .filter((a) => a && typeof a.transportUrl === 'string' && a.manifest)
    .map((a) => builtInAddons.find((b) => b.transportUrl === a.transportUrl) ?? a);
}

function makeClient() {
  return new AddonClient(state.addons, { builtIns: BUILT_INS });
}

function addonsChanged() {
  saveAddons(state.addons);
  state.client = makeClient();
}

// ---------------------------------------------------------------- Helpers

const $ = (sel, el = document) => el.querySelector(sel);
const view = $('#view');
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const enc = encodeURIComponent;

function safeUrl(url) {
  if (!url) return '';
  try {
    const parsed = new URL(url, location.href);
    return parsed.protocol === 'https:' || parsed.protocol === 'http:' ? parsed.href : '';
  } catch {
    return '';
  }
}

const initials = (name) => name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase();
const cacheMeta = (meta) => state.metaCache.set(`${meta.type}/${meta.id}`, meta);
const titleHref = (meta) => `#/title/${enc(meta.type)}/${enc(meta.id)}`;
const typeLabel = (t) => ({ movie: 'Movies', series: 'Series', channel: 'Channels', tv: 'Live TV' })[t] ?? t.charAt(0).toUpperCase() + t.slice(1);

let toastTimer;
function toast(message, ms = 2500) {
  const el = $('#toast');
  el.textContent = message;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, ms);
}

const ICON = {
  back: '<svg viewBox="0 0 24 24"><path d="M15 5l-7 7 7 7"/></svg>',
  play: '<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>',
  link: '<svg viewBox="0 0 24 24"><path d="M14 4h6v6h-2V7.4l-7.3 7.3-1.4-1.4L16.6 6H14zM5 6h6v2H6v10h10v-5h2v7H4V6z"/></svg>',
  blocked: '<svg viewBox="0 0 24 24"><path d="M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zm-5.3 4.1 10.2 10.2A7 7 0 0 1 6.7 7.1zm1.4-1.4a7 7 0 0 1 10.2 10.2z"/></svg>',
  up: '<svg viewBox="0 0 24 24"><path d="M6 15l6-6 6 6"/></svg>',
  down: '<svg viewBox="0 0 24 24"><path d="M6 9l6 6 6-6"/></svg>',
  remove: '<svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18"/></svg>',
  search: '<svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="6"/><path d="m20 20-4.5-4.5"/></svg>',
  bookmark: '<svg viewBox="0 0 24 24"><path d="M6 3h12v18l-6-4-6 4z"/></svg>',
};

function posterHTML(meta, { progress } = {}) {
  cacheMeta(meta);
  const img = safeUrl(meta.poster);
  const meter = progress !== undefined ? `<div class="meter"><i style="width:${Math.round(progress * 100)}%"></i></div>` : '';
  return `<a class="poster" data-shape="${esc(meta.posterShape ?? 'poster')}" href="${titleHref(meta)}">
    <div class="art">
      <span class="initials" aria-hidden="true">${esc(initials(meta.name))}</span>
      ${img ? `<img src="${esc(img)}" alt="" loading="lazy" decoding="async" onerror="this.remove()">` : ''}
      ${meter}
    </div>
    <span class="name">${esc(meta.name)}</span>
    ${meta.releaseInfo ? `<span class="year">${esc(meta.releaseInfo)}</span>` : ''}
  </a>`;
}

const skeleton = (n = 5) => `<div class="skeleton" aria-hidden="true">${'<span></span>'.repeat(n)}</div>`;

const emptyHTML = (title, body, action = '') =>
  `<div class="empty"><h3>${esc(title)}</h3><p>${esc(body)}</p>${action}</div>`;

function setHeader(title, { back = false } = {}) {
  const bar = $('.topbar');
  bar.innerHTML = `${back ? `<button class="back" data-back aria-label="Back">${ICON.back}</button>` : ''}<h1 id="screen-title">${esc(title)}</h1>`;
  document.title = back ? `${title} · Streamline` : 'Streamline';
}

$('.topbar').addEventListener('click', (e) => {
  if (!e.target.closest('[data-back]')) return;
  // Go back within the app when there is somewhere to go; a deep link opened
  // directly has no in-app history, so fall back to Discover.
  if (history.state?.navigated) history.back();
  else location.hash = '#/discover';
});

// ---------------------------------------------------------------- Router

let renderToken = 0;
let currentHash = '';

function parseRoute() {
  try {
    const parts = location.hash.replace(/^#\/?/, '').split('/').filter(Boolean).map(decodeURIComponent);
    return parts.length ? parts : ['discover'];
  } catch {
    return ['discover'];
  }
}

function render() {
  state.scroll.set(currentHash, window.scrollY);
  currentHash = location.hash;
  const token = ++renderToken;
  const [screen, ...args] = parseRoute();
  const tab = ['discover', 'search', 'library', 'addons'].includes(screen) ? screen : null;
  document.querySelectorAll('.tabs a').forEach((a) => {
    if (a.dataset.tab === tab) a.setAttribute('aria-current', 'page');
    else a.removeAttribute('aria-current');
  });

  const screens = {
    discover: renderDiscover,
    search: renderSearch,
    library: renderLibrary,
    addons: renderAddons,
    title: renderTitle,
    episode: renderEpisode,
    catalog: renderCatalog,
  };
  (screens[screen] ?? renderDiscover)(token, ...args);
  window.scrollTo(0, state.scroll.get(currentHash) ?? 0);
}

const stale = (token) => token !== renderToken;

window.addEventListener('hashchange', () => {
  history.replaceState({ ...(history.state ?? {}), navigated: true }, '');
  render();
});

// ---------------------------------------------------------------- Discover

function renderDiscover(token) {
  setHeader('Discover');
  const rows = state.addons.flatMap((addon) =>
    addon.manifest.catalogs.filter(isBrowsable).map((catalog) => ({ addon, catalog }))
  );
  const continuing = state.library.continueWatching();

  let html = '';
  if (continuing.length) {
    html += `<section class="section" aria-labelledby="cw-h">
      <div class="section-head"><h2 id="cw-h">Continue Watching</h2></div>
      <div class="strip">${continuing.map(progressCardHTML).join('')}</div>
    </section>`;
  }
  rows.forEach(({ addon, catalog }, i) => {
    const href = `#/catalog/${enc(addon.transportUrl)}/${enc(catalog.type)}/${enc(catalog.id)}`;
    html += `<section class="section" aria-labelledby="row-${i}">
      <div class="section-head">
        <div><h2 id="row-${i}">${esc(catalogName(catalog))}</h2>
        <span class="sub">${esc(typeLabel(catalog.type))} · ${esc(addon.manifest.name)}</span></div>
        <a href="${href}">See all</a>
      </div>
      <div data-row="${i}">${skeleton()}</div>
    </section>`;
  });
  if (!rows.length) {
    html += emptyHTML('No catalogs yet', 'Install an add-on with a catalog to fill this page.', '<a class="btn primary" href="#/addons">Manage add-ons</a>');
  }
  view.innerHTML = html;

  rows.forEach(async ({ addon, catalog }, i) => {
    let content;
    try {
      const metas = await state.client.catalog(addon, catalog);
      content = metas.length
        ? `<div class="strip">${metas.slice(0, 30).map((m) => posterHTML(m)).join('')}</div>`
        : '<p class="pad small muted">Nothing in this catalog right now.</p>';
    } catch (error) {
      content = `<p class="pad small muted">${esc(error.message)}</p>`;
    }
    if (stale(token)) return;
    const slot = view.querySelector(`[data-row="${i}"]`);
    if (slot) slot.innerHTML = content;
  });
}

function progressCardHTML(p) {
  const img = safeUrl(p.poster);
  const left = Math.max(1, Math.round((p.duration - p.position) / 60));
  return `<button class="poster" data-shape="landscape" data-resume="${esc(p.videoId)}" style="background:none;border:0;padding:0;text-align:left;cursor:pointer">
    <div class="art">
      <span class="initials" aria-hidden="true">${esc(initials(p.title))}</span>
      ${img ? `<img src="${esc(img)}" alt="" loading="lazy" onerror="this.remove()">` : ''}
      <div class="meter"><i style="width:${Math.round(progressFraction(p) * 100)}%"></i></div>
    </div>
    <span class="name">${esc(p.title)}</span>
    <span class="year">${esc(p.episodeLabel || `${left} min left`)}</span>
  </button>`;
}

// ---------------------------------------------------------------- Catalog grid

function renderCatalog(token, transportUrl, type, catalogId) {
  const addon = state.addons.find((a) => a.transportUrl === transportUrl);
  const catalog = addon?.manifest.catalogs.find((c) => c.type === type && c.id === catalogId);
  if (!addon || !catalog) {
    setHeader('Catalog', { back: true });
    view.innerHTML = emptyHTML('Catalog not found', 'The add-on that provided it may have been removed.');
    return;
  }
  setHeader(catalogName(catalog), { back: true });
  view.innerHTML = `<p class="pad small muted">${esc(typeLabel(catalog.type))} · ${esc(addon.manifest.name)}</p>
    <div class="grid" id="grid"></div>
    <div id="grid-end" class="pad small muted" style="padding-block:24px;text-align:center">Loading…</div>`;

  const grid = $('#grid');
  const end = $('#grid-end');
  const seen = new Set();
  let loading = false;
  let done = false;

  async function more() {
    if (loading || done) return;
    loading = true;
    try {
      const page = await state.client.catalog(addon, catalog, { skip: seen.size });
      if (stale(token)) return;
      const fresh = page.filter((m) => !seen.has(m.id));
      fresh.forEach((m) => seen.add(m.id));
      if (fresh.some((m) => m.posterShape === 'landscape')) grid.classList.add('wide');
      grid.insertAdjacentHTML('beforeend', fresh.map((m) => posterHTML(m)).join(''));
      // Add-ons that ignore `skip` send the same page again.
      if (!fresh.length || !supportsPaging(catalog)) done = true;
      end.textContent = done ? (seen.size ? '' : 'Nothing in this catalog right now.') : 'Loading…';
    } catch (error) {
      done = true;
      end.textContent = error.message;
    } finally {
      loading = false;
    }
    if (!done && end.getBoundingClientRect().top < innerHeight + 400) more();
  }

  const observer = new IntersectionObserver((entries) => {
    if (stale(token)) return observer.disconnect();
    if (entries.some((e) => e.isIntersecting)) more();
  }, { rootMargin: '400px' });
  observer.observe(end);
  more();
}

// ---------------------------------------------------------------- Search

let searchTimer;
function renderSearch(token) {
  setHeader('Search');
  view.innerHTML = `
    <form class="search-box" role="search" onsubmit="return false">
      ${ICON.search}
      <input id="search-input" class="field" type="search" placeholder="Movies, series, channels" autocomplete="off" enterkeyhint="search" aria-label="Search your add-ons" value="${esc(state.search)}">
    </form>
    <div id="results"></div>`;
  const input = $('#search-input');
  input.addEventListener('input', () => {
    state.search = input.value;
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => runSearch(token), 350);
  });
  if (!state.search) setTimeout(() => input.focus(), 50);
  runSearch(token);
}

async function runSearch(token) {
  const results = $('#results');
  if (!results) return;
  const query = state.search.trim();
  if (!query) {
    results.innerHTML = emptyHTML('Search your add-ons', 'Every installed add-on that supports search is searched at once.');
    return;
  }
  results.innerHTML = `<div class="section">${skeleton()}</div>`;
  const groups = await state.client.search(query);
  if (stale(token) || state.search.trim() !== query) return;
  results.innerHTML = groups.length
    ? groups.map((g, i) => `<section class="section" aria-labelledby="sr-${i}">
        <div class="section-head"><div><h2 id="sr-${i}">${esc(catalogName(g.catalog))}</h2>
        <span class="sub">${esc(typeLabel(g.catalog.type))} · ${esc(g.addon.manifest.name)}</span></div></div>
        <div class="strip">${g.metas.map((m) => posterHTML(m)).join('')}</div>
      </section>`).join('')
    : emptyHTML(`No results for “${query}”`, 'Try another title, or install an add-on that covers it.');
}

// ---------------------------------------------------------------- Title

async function renderTitle(token, type, id) {
  const preview = state.metaCache.get(`${type}/${id}`) ?? { id, type, name: '', posterShape: 'poster' };
  setHeader(preview.name || 'Loading…', { back: true });
  view.innerHTML = titleHeaderHTML(preview, true) + `<div id="below">${skeleton(3)}</div>`;
  wireTitleHeader(preview);

  const full = await state.client.meta(type, id);
  if (stale(token)) return;
  const meta = mergeMeta(full, preview.name ? preview : null) ?? preview;
  if (!meta.name) {
    view.innerHTML = emptyHTML('Title not found', 'None of your add-ons could describe this title.');
    return;
  }
  cacheMeta(meta);
  setHeader(meta.name, { back: true });
  view.innerHTML = titleHeaderHTML(meta, false) + '<div id="below"></div>';
  wireTitleHeader(meta);

  const below = $('#below');
  if (isSingleVideo(meta)) {
    below.innerHTML = `<section class="section"><div class="section-head"><h2>Streams</h2></div><div class="streams" id="streams">${skeleton(1)}</div></section>`;
    loadStreams(token, $('#streams'), meta, null);
  } else {
    renderEpisodes(below, meta);
  }
}

function titleHeaderHTML(meta, loading) {
  const backdrop = safeUrl(meta.background ?? meta.poster);
  const facts = [meta.releaseInfo, meta.runtime, meta.imdbRating ? `★ ${meta.imdbRating}` : null].filter(Boolean);
  const saved = state.library.isSaved(meta.id);
  // Without artwork, skip the backdrop so the title isn't pushed down by an empty block.
  const showHero = backdrop || loading;
  return `${showHero ? `<div class="hero"><div class="backdrop">${backdrop ? `<img src="${esc(backdrop)}" alt="" onerror="this.closest('.hero')?.remove()">` : ''}</div></div>` : ''}
    <div class="title-block${showHero ? '' : ' no-hero'}">
      <h2>${esc(meta.name || ' ')}</h2>
      ${facts.length ? `<div class="facts">${facts.map((f) => `<span>${esc(f)}</span>`).join('')}</div>` : ''}
      ${meta.genres?.length ? `<div class="chips">${meta.genres.slice(0, 5).map((g) => `<span class="chip">${esc(g)}</span>`).join('')}</div>` : ''}
      ${meta.description ? `<p class="description clamped" tabindex="0" title="Tap to expand">${esc(meta.description)}</p>` : ''}
      ${meta.cast?.length ? `<p class="small muted" style="margin:0">Cast: ${esc(meta.cast.slice(0, 6).join(', '))}</p>` : ''}
      ${loading ? '' : `<div class="actions"><button class="btn" data-save aria-pressed="${saved}">${ICON.bookmark}<span>${saved ? 'Saved' : 'Save'}</span></button></div>`}
    </div>`;
}

function wireTitleHeader(meta) {
  const desc = view.querySelector('.description');
  desc?.addEventListener('click', () => desc.classList.toggle('clamped'));
  const save = view.querySelector('[data-save]');
  save?.addEventListener('click', () => {
    const isSaved = state.library.toggleSaved(meta);
    save.setAttribute('aria-pressed', String(isSaved));
    save.querySelector('span').textContent = isSaved ? 'Saved' : 'Save';
    toast(isSaved ? 'Saved to your library' : 'Removed from your library');
  });
}

function renderEpisodes(container, meta) {
  const seasons = seasonsOf(meta);
  let season = seasons[0];
  const draw = () => {
    const list = episodesOf(meta, seasons.length ? season : undefined);
    container.querySelector('#episodes').innerHTML = list.map((v) => {
      const thumb = safeUrl(v.thumbnail);
      const p = state.library.progressFor(v.id);
      return `<li><a href="#/episode/${enc(meta.type)}/${enc(meta.id)}/${enc(v.id)}" class="${thumb ? '' : 'no-thumb'}">
        ${thumb ? `<div class="thumb"><img src="${esc(thumb)}" alt="" loading="lazy" onerror="this.remove()"></div>` : ''}
        <div>
          ${episodeLabel(v) ? `<div class="label">${esc(episodeLabel(v))}</div>` : ''}
          <div class="ep-title">${esc(v.title)}</div>
          ${v.overview ? `<div class="overview">${esc(v.overview)}</div>` : ''}
          ${p ? `<div class="meter"><i style="width:${Math.round(progressFraction(p) * 100)}%"></i></div>` : ''}
        </div>
      </a></li>`;
    }).join('') || '<li class="pad small muted">No episodes listed.</li>';
  };
  container.innerHTML = `<section class="section">
    <div class="section-head"><h2>Episodes</h2>
    ${seasons.length > 1 ? `<select class="season" id="season" aria-label="Season">${seasons.map((s) => `<option value="${s}">${s === 0 ? 'Specials' : `Season ${s}`}</option>`).join('')}</select>` : ''}
    </div>
    <ul class="episodes" id="episodes"></ul>
  </section>`;
  container.querySelector('#season')?.addEventListener('change', (e) => {
    season = Number(e.target.value);
    draw();
  });
  draw();
}

// ---------------------------------------------------------------- Episode

async function renderEpisode(token, type, id, videoId) {
  setHeader('Loading…', { back: true });
  view.innerHTML = skeleton(2);
  let meta = state.metaCache.get(`${type}/${id}`);
  if (!meta?.videos) {
    meta = mergeMeta(await state.client.meta(type, id), meta);
    if (stale(token)) return;
    if (meta) cacheMeta(meta);
  }
  const video = meta?.videos?.find((v) => v.id === videoId);
  if (!meta || !video) {
    setHeader('Episode', { back: true });
    view.innerHTML = emptyHTML('Episode not found', 'The add-on no longer lists this episode.');
    return;
  }
  setHeader(meta.name, { back: true });
  const thumb = safeUrl(video.thumbnail ?? meta.background);
  view.innerHTML = `
    ${thumb ? `<div class="hero"><div class="backdrop"><img src="${esc(thumb)}" alt="" onerror="this.remove()"></div></div>` : ''}
    <div class="title-block${thumb ? '' : ' no-hero'}">
      ${episodeLabel(video) ? `<div class="facts"><span>${esc(episodeLabel(video))}</span>${video.released ? `<span>${esc(video.released.slice(0, 10))}</span>` : ''}</div>` : ''}
      <h2>${esc(video.title)}</h2>
      ${video.overview ? `<p class="description">${esc(video.overview)}</p>` : ''}
    </div>
    <section class="section"><div class="section-head"><h2>Streams</h2></div><div class="streams" id="streams">${skeleton(1)}</div></section>`;
  loadStreams(token, $('#streams'), meta, video);
}

// ---------------------------------------------------------------- Streams

async function loadStreams(token, container, meta, video) {
  const videoId = video?.id ?? meta.id;
  let groups;
  // Per the protocol, streams embedded in a video are used exclusively.
  if (video?.streams?.length) {
    groups = [{ addon: { manifest: { name: 'Included with this title' } }, streams: video.streams }];
  } else {
    groups = await state.client.streams(meta.type, videoId);
  }
  if (stale(token)) return;

  const total = groups.reduce((n, g) => n + g.streams.length, 0);
  if (!total) {
    container.innerHTML = groups.length
      ? emptyHTML('No streams', 'Your add-ons didn’t return any streams for this title.') +
        groups.filter((g) => g.error).map((g) => `<p class="error-line">${esc(g.addon.manifest.name)}: ${esc(g.error)}</p>`).join('')
      : emptyHTML('No streams', 'None of your add-ons provide streams for this title.', '<a class="btn" href="#/addons">Manage add-ons</a>');
    return;
  }

  const registry = [];
  container.innerHTML = groups.map((g) => `<div class="stream-group">
      <h3>${esc(g.addon.manifest.name)}</h3>
      ${g.error ? `<p class="error-line">${esc(g.error)}</p>` : ''}
      ${g.streams.map((s) => {
        const index = registry.push({ stream: s, addonName: g.addon.manifest.name }) - 1;
        return streamHTML(s, index);
      }).join('')}
    </div>`).join('');

  container.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-stream]');
    if (!button) return;
    const { stream, addonName } = registry[Number(button.dataset.stream)];
    play({ meta, video, stream, addonName });
  });
}

function streamHTML(stream, index) {
  const verdict = classifyStream(stream, { secureContext: location.protocol === 'https:' });
  const tags = qualityTags(stream).map((t) => `<span class="tag">${esc(t)}</span>`).join('');
  const name = stream.name?.trim() || 'Stream';
  const body = `<div class="body">
      <div class="title-row"><span class="stream-name">${esc(name)}</span>${tags}</div>
      ${stream.description ? `<div class="desc">${esc(stream.description)}</div>` : ''}
      ${verdict.reason ? `<div class="note">${esc(verdict.reason)}</div>` : ''}
      ${verdict.warning ? `<div class="note">${esc(verdict.warning)}</div>` : ''}
    </div>`;
  if (verdict.kind === 'direct') {
    return `<button class="stream" data-stream="${index}"><span class="icon">${ICON.play}</span>${body}</button>`;
  }
  if (verdict.kind === 'youtube' || verdict.kind === 'external') {
    return `<a class="stream" href="${esc(verdict.url)}" target="_blank" rel="noopener"><span class="icon">${ICON.link}</span>${body}</a>`;
  }
  return `<div class="stream" aria-disabled="true"><span class="icon">${ICON.blocked}</span>${body}</div>`;
}

function play({ meta, video, stream, addonName }) {
  const verdict = classifyStream(stream, { secureContext: location.protocol === 'https:' });
  if (verdict.kind !== 'direct') return;
  openPlayer(
    { meta, video, stream, addonName, url: verdict.url },
    { client: state.client, library: state.library, toast, onClose: refreshAfterPlayback }
  );
}

function refreshAfterPlayback() {
  // Progress meters and Continue Watching may have changed.
  const [screen] = parseRoute();
  if (screen === 'discover' || screen === 'library') render();
}

function resume(videoId) {
  const p = state.library.progressFor(videoId);
  if (!p) return;
  const meta = state.metaCache.get(`${p.metaType}/${p.metaId}`) ?? { id: p.metaId, type: p.metaType, name: p.title, poster: p.poster };
  if (p.stream && classifyStream(p.stream).kind === 'direct') {
    const video = p.videoId === p.metaId ? null : { id: p.videoId, title: p.episodeLabel ?? p.title };
    play({ meta, video, stream: p.stream, addonName: p.addonName });
  } else {
    location.hash = titleHref(meta);
  }
}

view.addEventListener('click', (event) => {
  const card = event.target.closest('[data-resume]');
  if (card) resume(card.dataset.resume);
});

// ---------------------------------------------------------------- Library

function renderLibrary() {
  setHeader('Library');
  const continuing = state.library.continueWatching();
  const saved = state.library.saved;
  if (!continuing.length && !saved.length) {
    view.innerHTML = emptyHTML('Your library is empty', 'Titles you save and videos you start watching appear here.', '<a class="btn primary" href="#/discover">Browse</a>');
    return;
  }
  let html = '';
  if (continuing.length) {
    html += `<section class="section"><div class="section-head"><h2>Continue Watching</h2></div><div class="list">
      ${continuing.map((p) => {
        const img = safeUrl(p.poster);
        return `<div class="row">
          <button class="thumb" data-resume="${esc(p.videoId)}" aria-label="Resume ${esc(p.title)}" style="border:0;padding:0;cursor:pointer">${img ? `<img src="${esc(img)}" alt="" loading="lazy" onerror="this.remove()">` : ''}</button>
          <div data-resume="${esc(p.videoId)}" style="cursor:pointer">
            <div class="row-title">${esc(p.title)}</div>
            <div class="row-sub">${esc(p.episodeLabel ?? `${Math.max(1, Math.round((p.duration - p.position) / 60))} min left`)}</div>
            <div class="meter"><i style="width:${Math.round(progressFraction(p) * 100)}%"></i></div>
          </div>
          <div class="row-actions"><button class="icon-btn" data-forget="${esc(p.videoId)}" aria-label="Remove ${esc(p.title)} from Continue Watching">${ICON.remove}</button></div>
        </div>`;
      }).join('')}
    </div></section>`;
  }
  if (saved.length) {
    html += `<section class="section"><div class="section-head"><h2>Saved</h2></div>
      <div class="grid">${saved.map((m) => posterHTML(m)).join('')}</div></section>`;
  }
  view.innerHTML = html;
  view.querySelectorAll('[data-forget]').forEach((b) =>
    b.addEventListener('click', () => {
      state.library.removeProgress(b.dataset.forget);
      renderLibrary();
    })
  );
}

// ---------------------------------------------------------------- Add-ons

function renderAddons() {
  setHeader('Add-ons');
  const missing = builtInAddons.filter((b) => !state.addons.some((a) => a.transportUrl === b.transportUrl));
  view.innerHTML = `
    <section class="section">
      <div class="section-head"><h2>Add an add-on</h2></div>
      <form class="form" id="install-form" novalidate>
        <input id="addon-url" class="field" type="url" inputmode="url" autocapitalize="off" autocorrect="off" spellcheck="false"
          placeholder="https://example.com/manifest.json" aria-label="Add-on manifest URL" required>
        <button class="btn primary" id="install-btn" type="submit">Install</button>
        <p class="error" id="install-error" hidden></p>
        <p class="hint">Paste a manifest URL or a stremio:// install link. Streams play when they are direct HTTPS video or HLS links. Only install add-ons for content you have the right to watch.</p>
      </form>
    </section>
    <section class="section">
      <div class="section-head"><h2>Installed</h2><span class="sub">Order decides who answers first</span></div>
      <div class="list">${state.addons.map(addonRowHTML).join('') || '<p class="pad small muted" style="background:var(--ink);margin:0;padding-block:14px">No add-ons installed.</p>'}</div>
    </section>
    ${missing.length ? `<section class="section"><div class="section-head"><h2>Built-in</h2></div>
      <div class="pad">${missing.map((b) => `<button class="btn" data-restore="${esc(b.transportUrl)}">Restore ${esc(b.manifest.name)}</button>`).join(' ')}</div></section>` : ''}`;

  const form = $('#install-form');
  const input = $('#addon-url');
  const button = $('#install-btn');
  const error = $('#install-error');
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!input.value.trim()) return input.focus();
    button.disabled = true;
    button.textContent = 'Installing…';
    error.hidden = true;
    try {
      const addon = await installAddon(input.value);
      const index = state.addons.findIndex((a) => a.transportUrl === addon.transportUrl || a.manifest.id === addon.manifest.id);
      if (index >= 0) state.addons[index] = addon;
      else state.addons.push(addon);
      addonsChanged();
      toast(`${addon.manifest.name} installed`);
      renderAddons();
    } catch (e) {
      error.textContent = e.message;
      error.hidden = false;
      button.disabled = false;
      button.textContent = 'Install';
    }
  });

  view.querySelectorAll('[data-move]').forEach((b) =>
    b.addEventListener('click', () => {
      const i = Number(b.dataset.index);
      const j = i + Number(b.dataset.move);
      [state.addons[i], state.addons[j]] = [state.addons[j], state.addons[i]];
      addonsChanged();
      renderAddons();
    })
  );
  view.querySelectorAll('[data-remove]').forEach((b) =>
    b.addEventListener('click', () => {
      if (b.dataset.confirm !== 'yes') {
        b.dataset.confirm = 'yes';
        b.classList.add('danger');
        b.setAttribute('aria-label', 'Tap again to remove');
        toast('Tap again to remove');
        setTimeout(() => { b.dataset.confirm = ''; b.classList.remove('danger'); }, 3000);
        return;
      }
      const removed = state.addons.splice(Number(b.dataset.index), 1)[0];
      addonsChanged();
      toast(`${removed.manifest.name} removed`);
      renderAddons();
    })
  );
  view.querySelectorAll('[data-restore]').forEach((b) =>
    b.addEventListener('click', () => {
      state.addons.unshift(builtInAddons.find((a) => a.transportUrl === b.dataset.restore));
      addonsChanged();
      renderAddons();
    })
  );
}

function addonRowHTML(addon, index, all) {
  const m = addon.manifest;
  const logo = safeUrl(m.logo);
  const caps = [...new Set(m.resources.map((r) => r.name))].concat(m.types.map(typeLabel)).join(' · ');
  return `<div class="row addon-row">
    <div class="logo">${logo ? `<img src="${esc(logo)}" alt="" onerror="this.remove()">` : esc(initials(m.name))}</div>
    <div class="addon-detail">
      <div class="row-title">${esc(m.name)} <span class="muted small" style="font-weight:400">v${esc(m.version)}</span></div>
      ${m.description ? `<p>${esc(m.description)}</p>` : ''}
      <div class="caps">${esc(caps)}</div>
      ${m.behaviorHints?.configurationRequired ? '<div class="warn">This add-on must be configured on its website first. Install the configured URL instead.</div>' : ''}
      <div class="row-actions">
        <button class="icon-btn" data-move="-1" data-index="${index}" aria-label="Move ${esc(m.name)} up" ${index === 0 ? 'disabled' : ''}>${ICON.up}</button>
        <button class="icon-btn" data-move="1" data-index="${index}" aria-label="Move ${esc(m.name)} down" ${index === all.length - 1 ? 'disabled' : ''}>${ICON.down}</button>
        <button class="icon-btn" data-remove data-index="${index}" aria-label="Remove ${esc(m.name)}">${ICON.remove}</button>
      </div>
    </div>
  </div>`;
}

// ---------------------------------------------------------------- Start

if (!location.hash) history.replaceState(null, '', '#/discover');
render();
