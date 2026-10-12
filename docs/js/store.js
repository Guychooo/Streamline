// Local persistence. Everything lives in this browser only.

const KEYS = { addons: 'streamline.addons', library: 'streamline.library', prefs: 'streamline.prefs' };

function read(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

function write(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    /* storage full or unavailable: keep working in memory */
  }
}

export const loadAddons = () => read(KEYS.addons, null);
export const saveAddons = (addons) => write(KEYS.addons, addons);

export const loadPrefs = () => read(KEYS.prefs, {});
export const savePrefs = (prefs) => write(KEYS.prefs, prefs);

// Progress rules match the native app: resume after 30 s; done at 92 %, or with
// under 2 min left on anything longer than 20 min (the end credits).
export const progressFraction = (p) => (p.duration > 0 ? Math.min(Math.max(p.position / p.duration, 0), 1) : 0);
export const isFinished = (p) =>
  p.duration > 0 && (progressFraction(p) >= 0.92 || (p.duration > 1200 && p.duration - p.position < 120));
export const resumePosition = (p) => (p && p.position >= 30 && !isFinished(p) ? Math.max(p.position - 5, 0) : undefined);

export class Library {
  constructor() {
    const data = read(KEYS.library, {});
    this.progress = data.progress ?? {};
    this.saved = data.saved ?? [];
  }

  persist() {
    write(KEYS.library, { progress: this.progress, saved: this.saved });
  }

  continueWatching() {
    return Object.values(this.progress)
      .filter((p) => !isFinished(p) && p.position >= 30)
      .sort((a, b) => b.updatedAt - a.updatedAt);
  }

  progressFor(videoId) {
    return this.progress[videoId];
  }

  record(progress) {
    this.progress[progress.videoId] = { ...progress, updatedAt: Date.now() };
    this.persist();
  }

  removeProgress(videoId) {
    delete this.progress[videoId];
    this.persist();
  }

  isSaved(id) {
    return this.saved.some((m) => m.id === id);
  }

  toggleSaved(meta) {
    const index = this.saved.findIndex((m) => m.id === meta.id);
    if (index >= 0) this.saved.splice(index, 1);
    else {
      const { videos, ...compact } = meta;
      this.saved.unshift(compact);
    }
    this.persist();
    return index < 0;
  }
}
