// Full-screen player: native <video> (Safari plays HLS itself), hls.js
// elsewhere, an audio picker, and a subtitle picker that covers tracks
// inside the stream and subtitle files from add-ons.
import { episodeLabel, languageName, normalizeLanguage, subtitleName } from './protocol.js';
import { decodeSubtitleBytes, parseSubtitles, toWebVTT } from './subtitles.js';
import { loadPrefs, resumePosition, savePrefs } from './store.js';

const HLS_SRC = 'https://cdn.jsdelivr.net/npm/hls.js@1.5.13/dist/hls.min.js';
let hlsPromise;
function loadHls() {
  if (window.Hls) return Promise.resolve(window.Hls);
  hlsPromise ??= new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = HLS_SRC;
    script.onload = () => resolve(window.Hls);
    script.onerror = () => {
      hlsPromise = undefined;
      reject(new Error('Couldn’t load the HLS player.'));
    };
    document.head.append(script);
  });
  return hlsPromise;
}

const ICONS = {
  close: '<svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18"/></svg>',
  audio: '<svg viewBox="0 0 24 24"><path d="M4 10v4M8 7v10M12 4v16M16 8v8M20 11v2"/></svg>',
  subs: '<svg viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="14" rx="3"/><path d="M7 13h4M13 13h4M7 16h7"/></svg>',
  check: '<svg class="check" viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7"/></svg>',
};

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

export function formatTime(seconds) {
  const t = Math.max(0, Math.floor(seconds));
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const s = String(t % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${s}` : `${m}:${s}`;
}

let active = null;

/**
 * @param req  { meta, video, stream, addonName, url }
 * @param deps { client, library, toast, onClose }
 */
export function openPlayer(req, deps) {
  if (active) active.teardown();
  const root = document.getElementById('player-root');
  const videoId = req.video?.id ?? req.meta.id;
  const subtitleLine = req.video
    ? [episodeLabel(req.video), req.video.title !== req.meta.name ? req.video.title : null].filter(Boolean).join(' · ')
    : req.addonName ?? '';

  root.innerHTML = `
    <div class="player-bar">
      <button class="icon-btn" data-act="close" aria-label="Close player">${ICONS.close}</button>
      <div class="titles">
        <div class="t1">${esc(req.meta.name)}</div>
        <div class="t2">${esc(subtitleLine)}</div>
      </div>
      <button class="icon-btn" data-act="audio" aria-label="Audio track" hidden>${ICONS.audio}</button>
      <button class="icon-btn" data-act="subs" aria-label="Subtitles" aria-pressed="false">${ICONS.subs}</button>
    </div>
    <div class="player-stage">
      <video playsinline controls autoplay preload="auto"></video>
    </div>`;
  root.hidden = false;
  document.body.style.overflow = 'hidden';

  const video = root.querySelector('video');
  const audioBtn = root.querySelector('[data-act="audio"]');
  const subsBtn = root.querySelector('[data-act="subs"]');

  let hls = null;
  let externalSubs = [];
  let externalCues = null;
  let externalTrackEl = null;
  let selection = { kind: 'off' };
  let delay = 0;
  let userChoseAudio = false;
  let userChoseSubs = false;
  let lastSaved = -Infinity;
  let closed = false;
  const ownTracks = new Set();
  const blobUrls = [];
  const cueCache = new Map();
  const prefs = loadPrefs();
  const startAt = resumePosition(deps.library.progressFor(videoId));

  // ------------------------------------------------------------ source

  const isHls = /\.m3u8($|\?)|\/\.m3u8|m3u8/i.test(req.url);
  const nativeHls = video.canPlayType('application/vnd.apple.mpegurl') !== '';

  async function attachSource() {
    if (isHls && !nativeHls) {
      try {
        const Hls = await loadHls();
        if (closed) return;
        if (Hls?.isSupported()) {
          hls = new Hls({ renderTextTracksNatively: true });
          hls.on(Hls.Events.AUDIO_TRACKS_UPDATED, refresh);
          hls.on(Hls.Events.AUDIO_TRACK_SWITCHED, refresh);
          hls.on(Hls.Events.SUBTITLE_TRACKS_UPDATED, refresh);
          hls.on(Hls.Events.ERROR, (_e, data) => {
            if (data?.fatal) showError(data.type === 'networkError'
              ? 'The stream server couldn’t be reached or refused the request.'
              : 'This stream couldn’t be decoded in this browser.');
          });
          hls.loadSource(req.url);
          hls.attachMedia(video);
        } else {
          video.src = req.url;
        }
      } catch (error) {
        showError(error.message);
        return;
      }
    } else {
      video.src = req.url;
    }
    video.play().catch(() => { /* needs a tap; native controls are showing */ });
  }

  video.addEventListener('loadedmetadata', () => {
    if (startAt !== undefined && Number.isFinite(video.duration) && video.duration > startAt) {
      video.currentTime = startAt;
      deps.toast(`Resuming from ${formatTime(startAt)}`);
    }
    refresh();
    // Safari fills in HLS text tracks a moment after metadata.
    setTimeout(refresh, 400);
  }, { once: true });

  video.addEventListener('error', () => {
    const code = video.error?.code;
    showError(
      code === 2 ? 'The stream server couldn’t be reached.'
        : code === 3 ? 'The video data couldn’t be decoded.'
        : code === 4 ? 'This format or link can’t play in this browser.'
        : 'This stream couldn’t be played.'
    );
  });

  video.audioTracks?.addEventListener?.('addtrack', refresh);
  video.audioTracks?.addEventListener?.('change', refresh);
  video.textTracks?.addEventListener?.('addtrack', refresh);

  function showError(message) {
    if (closed || root.querySelector('.player-error')) return;
    const box = document.createElement('div');
    box.className = 'player-error';
    box.innerHTML = `<h3>Playback failed</h3><p>${esc(message)}</p><button class="btn primary" data-act="close">Close</button>`;
    root.querySelector('.player-stage').append(box);
  }

  // ------------------------------------------------------------ tracks

  function audioOptions() {
    if (hls) {
      return hls.audioTracks.map((t, i) => ({
        label: t.name || languageName(t.lang), lang: t.lang, selected: hls.audioTrack === i,
        select: () => { hls.audioTrack = i; },
      }));
    }
    const list = video.audioTracks;
    if (!list) return [];
    return Array.from(list).map((t, i) => ({
      label: t.label || languageName(t.language), lang: t.language, selected: t.enabled,
      select: () => { for (let j = 0; j < list.length; j++) list[j].enabled = j === i; },
    }));
  }

  function nativeTextTracks() {
    return Array.from(video.textTracks).filter(
      (t) => !ownTracks.has(t) && (t.kind === 'subtitles' || t.kind === 'captions') && !/forced/i.test(t.label)
    );
  }

  function embeddedOptions() {
    if (hls) {
      return hls.subtitleTracks.map((t, i) => ({
        key: `h${i}`, label: t.name || languageName(t.lang), lang: t.lang,
        selected: selection.kind === 'embedded' && selection.key === `h${i}`,
        apply: () => { hls.subtitleDisplay = true; hls.subtitleTrack = i; },
      }));
    }
    return nativeTextTracks().map((t, i) => ({
      key: `n${i}`, label: t.label || languageName(t.language), lang: t.language,
      selected: selection.kind === 'embedded' && selection.key === `n${i}`,
      apply: () => { for (const other of video.textTracks) other.mode = other === t ? 'showing' : 'disabled'; },
    }));
  }

  function disableEmbedded() {
    if (hls) hls.subtitleTrack = -1;
    for (const t of video.textTracks) if (!ownTracks.has(t)) t.mode = 'disabled';
  }

  function removeExternalTrack() {
    if (externalTrackEl) {
      externalTrackEl.track.mode = 'disabled';
      ownTracks.delete(externalTrackEl.track);
      externalTrackEl.remove();
      externalTrackEl = null;
    }
  }

  function chooseOff(remember) {
    selection = { kind: 'off' };
    removeExternalTrack();
    externalCues = null;
    disableEmbedded();
    if (remember) savePrefs({ ...loadPrefs(), subLang: 'off' });
    refresh();
  }

  function chooseEmbedded(option, remember) {
    selection = { kind: 'embedded', key: option.key };
    removeExternalTrack();
    externalCues = null;
    disableEmbedded();
    option.apply();
    if (remember && option.lang) savePrefs({ ...loadPrefs(), subLang: normalizeLanguage(option.lang) });
    refresh();
  }

  async function chooseExternal(sub, remember) {
    selection = { kind: 'external', id: sub.id };
    disableEmbedded();
    removeExternalTrack();
    refresh();
    try {
      let cues = cueCache.get(sub.url);
      if (!cues) {
        deps.toast(`Loading ${subtitleName(sub)} subtitles…`);
        let response;
        try {
          response = await fetch(sub.url);
        } catch {
          throw new Error('The subtitle server doesn’t allow access from a browser.');
        }
        if (!response.ok) throw new Error(`The subtitle server answered with HTTP ${response.status}.`);
        cues = parseSubtitles(decodeSubtitleBytes(await response.arrayBuffer()));
        cueCache.set(sub.url, cues);
      }
      if (closed || selection.kind !== 'external' || selection.id !== sub.id) return;
      externalCues = cues;
      mountExternal(sub);
      // Remember the language only once the file has actually loaded.
      if (remember) savePrefs({ ...loadPrefs(), subLang: normalizeLanguage(sub.lang) });
      deps.toast(`${subtitleName(sub)} subtitles on`);
    } catch (error) {
      if (selection.kind === 'external' && selection.id === sub.id) {
        selection = { kind: 'off' };
        refresh();
      }
      deps.toast(`Couldn’t load subtitles. ${error.message}`, 4000);
    }
  }

  function mountExternal(sub) {
    removeExternalTrack();
    const url = URL.createObjectURL(new Blob([toWebVTT(externalCues, delay)], { type: 'text/vtt' }));
    blobUrls.push(url);
    const el = document.createElement('track');
    el.kind = 'subtitles';
    el.label = subtitleName(sub);
    el.srclang = normalizeLanguage(sub.lang) || 'und';
    el.src = url;
    el.default = true;
    el.dataset.external = sub.id;
    video.append(el);
    ownTracks.add(el.track);
    el.track.mode = 'showing';
    externalTrackEl = el;
  }

  function shiftDelay(delta) {
    delay = delta === 0 ? 0 : Math.round((delay + delta) * 100) / 100;
    const sub = externalSubs.find((s) => selection.kind === 'external' && s.id === selection.id);
    if (sub && externalCues) mountExternal(sub);
    const out = document.querySelector('.sheet output');
    if (out) out.textContent = formatDelay();
  }

  const formatDelay = () => (delay === 0 ? '0.00 s' : `${delay > 0 ? '+' : '−'}${Math.abs(delay).toFixed(2)} s`);

  /** Re-applies the languages chosen in earlier sessions, until the viewer picks. */
  function applyPrefs() {
    if (!userChoseAudio && prefs.audioLang) {
      const options = audioOptions();
      const match = options.find((o) => normalizeLanguage(o.lang) === prefs.audioLang);
      if (match && !match.selected) match.select();
    }
    if (userChoseSubs || !prefs.subLang) return;
    if (prefs.subLang === 'off') {
      if (selection.kind !== 'off') chooseOff(false);
      return;
    }
    if (selection.kind !== 'off') return;
    const embedded = embeddedOptions().find((o) => normalizeLanguage(o.lang) === prefs.subLang);
    if (embedded) return chooseEmbedded(embedded, false);
    const external = externalSubs.find((s) => normalizeLanguage(s.lang) === prefs.subLang);
    if (external) chooseExternal(external, false);
  }

  function refresh() {
    if (closed) return;
    // Pick up a track Safari's own menu turned on.
    if (!hls && selection.kind !== 'external') {
      const showing = nativeTextTracks().findIndex((t) => t.mode === 'showing');
      if (showing >= 0) selection = { kind: 'embedded', key: `n${showing}` };
    }
    audioBtn.hidden = audioOptions().length < 2;
    subsBtn.setAttribute('aria-pressed', String(selection.kind !== 'off'));
    applyPrefs();
  }

  // ------------------------------------------------------------ sheets

  function openSheet(kind) {
    closeSheet();
    const scrim = document.createElement('div');
    scrim.className = 'sheet-scrim';
    const sheet = document.createElement('div');
    sheet.className = 'sheet';
    sheet.setAttribute('role', 'menu');
    sheet.setAttribute('aria-label', kind === 'audio' ? 'Audio' : 'Subtitles');
    const option = (label, checked, act) =>
      `<button class="option" role="menuitemradio" aria-checked="${checked}" data-pick="${esc(act)}"><span>${esc(label)}</span>${ICONS.check}</button>`;

    let html = '<div class="grabber"></div>';
    const actions = new Map();
    if (kind === 'audio') {
      html += '<h4>Audio</h4>';
      audioOptions().forEach((o, i) => {
        actions.set(`a${i}`, () => { userChoseAudio = true; o.select(); if (o.lang) savePrefs({ ...loadPrefs(), audioLang: normalizeLanguage(o.lang) }); });
        html += option(o.label, o.selected, `a${i}`);
      });
    } else {
      html += '<h4>Subtitles</h4>';
      actions.set('off', () => { userChoseSubs = true; chooseOff(true); });
      html += option('Off', selection.kind === 'off', 'off');
      const embedded = embeddedOptions();
      if (embedded.length) {
        html += '<h4>In this stream</h4>';
        embedded.forEach((o) => {
          actions.set(o.key, () => { userChoseSubs = true; chooseEmbedded(o, true); });
          html += option(o.label, o.selected, o.key);
        });
      }
      if (externalSubs.length) {
        html += '<h4>From add-ons</h4>';
        externalSubs.forEach((s, i) => {
          actions.set(`x${i}`, () => { userChoseSubs = true; chooseExternal(s, true); });
          html += option(subtitleName(s), selection.kind === 'external' && selection.id === s.id, `x${i}`);
        });
      }
      if (!embedded.length && !externalSubs.length) {
        html += '<p class="pad small muted">No subtitles were found in this stream or from your add-ons.</p>';
      }
      if (selection.kind === 'external') {
        html += `<h4>Timing</h4>
          <div class="timing">
            <button class="btn" data-shift="-0.25" aria-label="Show subtitles earlier">−0.25</button>
            <output aria-live="polite">${formatDelay()}</output>
            <button class="btn" data-shift="0.25" aria-label="Show subtitles later">+0.25</button>
            <button class="btn" data-shift="0">Reset</button>
          </div>`;
      }
    }
    sheet.innerHTML = html;
    sheet.addEventListener('click', (event) => {
      const pick = event.target.closest('[data-pick]');
      if (pick) {
        actions.get(pick.dataset.pick)?.();
        closeSheet();
        refresh();
        return;
      }
      const shift = event.target.closest('[data-shift]');
      if (shift) shiftDelay(Number(shift.dataset.shift));
    });
    scrim.addEventListener('click', closeSheet);
    root.append(scrim, sheet);
    sheet.querySelector('[aria-checked="true"], button')?.focus({ preventScroll: true });
  }

  function closeSheet() {
    root.querySelectorAll('.sheet, .sheet-scrim').forEach((el) => el.remove());
  }

  // ------------------------------------------------------------ progress

  function save(position) {
    const duration = video.duration;
    // Live streams have no finite duration and nothing to resume.
    if (!Number.isFinite(duration) || duration <= 0 || !Number.isFinite(position)) return;
    lastSaved = position;
    deps.library.record({
      videoId,
      metaId: req.meta.id,
      metaType: req.meta.type,
      title: req.meta.name,
      episodeLabel: req.video ? subtitleLine : undefined,
      poster: req.meta.background ?? req.meta.poster ?? req.video?.thumbnail,
      position,
      duration,
      stream: req.stream,
      addonName: req.addonName,
    });
  }

  video.addEventListener('timeupdate', () => {
    if (Math.abs(video.currentTime - lastSaved) >= 10 && video.currentTime > 0) save(video.currentTime);
  });
  video.addEventListener('pause', () => save(video.currentTime));
  video.addEventListener('ended', () => save(video.duration));

  // ------------------------------------------------------------ lock screen

  if ('mediaSession' in navigator && 'MediaMetadata' in window) {
    try {
      navigator.mediaSession.metadata = new MediaMetadata({
        title: req.meta.name,
        artist: subtitleLine || 'Streamline',
        artwork: [req.meta.poster, req.meta.background].filter(Boolean).map((src) => ({ src })),
      });
    } catch { /* optional */ }
  }

  // ------------------------------------------------------------ wiring

  root.addEventListener('click', onClick);
  function onClick(event) {
    const act = event.target.closest('[data-act]')?.dataset.act;
    if (act === 'close') history.back();
    else if (act === 'audio') openSheet('audio');
    else if (act === 'subs') openSheet('subs');
  }

  // The system back gesture closes the player instead of leaving the page.
  history.pushState({ streamlinePlayer: true }, '', location.href);
  window.addEventListener('popstate', onPop);
  function onPop() { teardown(); }

  function teardown() {
    if (closed) return;
    closed = true;
    if (video.currentTime > 0) save(video.currentTime);
    window.removeEventListener('popstate', onPop);
    root.removeEventListener('click', onClick);
    video.pause();
    hls?.destroy();
    video.removeAttribute('src');
    video.load();
    blobUrls.forEach((u) => URL.revokeObjectURL(u));
    root.hidden = true;
    root.innerHTML = '';
    document.body.style.overflow = '';
    active = null;
    deps.onClose?.();
  }

  active = { teardown };
  attachSource();
  deps.client
    .subtitles(req.meta.type, videoId, req.stream)
    .then((subs) => {
      if (closed) return;
      externalSubs = subs;
      refresh();
    })
    .catch(() => {});

  return active;
}

export const playerIsOpen = () => active !== null;
