// Parses SRT, WebVTT and ASS/SSA dialogue into plain cues, and writes WebVTT.

export function decodeSubtitleBytes(buffer) {
  const bytes = new Uint8Array(buffer);
  if ((bytes[0] === 0xff && bytes[1] === 0xfe) || (bytes[0] === 0xfe && bytes[1] === 0xff)) {
    return new TextDecoder(bytes[0] === 0xff ? 'utf-16le' : 'utf-16be').decode(bytes);
  }
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    // Many older subtitle files are Windows-1252.
    return new TextDecoder('windows-1252').decode(bytes);
  }
}

export function detectFormat(text) {
  const head = text.slice(0, 512).trim();
  if (head.startsWith('WEBVTT')) return 'vtt';
  if (head.startsWith('[Script Info]') || text.includes('\nDialogue:')) return 'ass';
  return 'srt';
}

/** hh:mm:ss,mmm · hh:mm:ss.mmm · mm:ss.mmm · h:mm:ss.cc */
export function parseTimestamp(raw) {
  const fields = raw.trim().replace(',', '.').split(':');
  if (fields.length < 2 || fields.length > 3) return undefined;
  let seconds = 0;
  for (const f of fields) {
    if (!/^\d+(\.\d+)?$/.test(f)) return undefined;
    seconds = seconds * 60 + Number(f);
  }
  return seconds;
}

export function cleanMarkup(line) {
  return line
    .replace(/<[^>]*>/g, '')
    .replace(/\{[^}]*\}/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&nbsp;/g, ' ')
    .replace(/&quot;/g, '"')
    .trim();
}

export class SubtitleError extends Error {}

export function parseSubtitles(input) {
  let text = String(input).replace(/\r\n?/g, '\n');
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  const cues = detectFormat(text) === 'ass' ? parseASS(text) : parseBlocks(text);
  if (!cues.length) throw new SubtitleError('The subtitle file has no timed lines this app can read.');
  return cues.sort((a, b) => a.start - b.start || a.end - b.end);
}

function parseBlocks(text) {
  const cues = [];
  for (const block of text.split(/\n{2,}/)) {
    const lines = block.split('\n');
    const timingIndex = lines.findIndex((l) => l.includes('-->'));
    if (timingIndex < 0) continue;
    const [left, right] = lines[timingIndex].split('-->');
    const start = parseTimestamp(left ?? '');
    const end = parseTimestamp((right ?? '').trim().split(/[ \t]/)[0]);
    if (start === undefined || end === undefined || end <= start) continue;
    const body = lines.slice(timingIndex + 1).map(cleanMarkup).filter(Boolean).join('\n');
    if (body) cues.push({ start, end, text: body });
  }
  return cues;
}

function parseASS(text) {
  const cues = [];
  let inEvents = false;
  let columns = ['Layer', 'Start', 'End', 'Style', 'Name', 'MarginL', 'MarginR', 'MarginV', 'Effect', 'Text'];
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (line.startsWith('[')) {
      inEvents = line.toLowerCase() === '[events]';
      continue;
    }
    if (!inEvents) continue;
    if (line.startsWith('Format:')) {
      columns = line.slice(7).split(',').map((c) => c.trim());
      continue;
    }
    if (!line.startsWith('Dialogue:')) continue;
    const payload = line.slice(9);
    const fields = [];
    let rest = payload;
    // The text column is last and can contain commas.
    for (let i = 0; i < columns.length - 1; i++) {
      const comma = rest.indexOf(',');
      if (comma < 0) break;
      fields.push(rest.slice(0, comma).trim());
      rest = rest.slice(comma + 1);
    }
    fields.push(rest.trim());
    if (fields.length !== columns.length) continue;
    const start = parseTimestamp(fields[columns.indexOf('Start')] ?? '');
    const end = parseTimestamp(fields[columns.indexOf('End')] ?? '');
    if (start === undefined || end === undefined || end <= start) continue;
    const body = (fields[columns.indexOf('Text')] ?? '')
      .replace(/\\[Nn]/g, '\n')
      .replace(/\\h/g, ' ')
      .split('\n')
      .map(cleanMarkup)
      .filter(Boolean)
      .join('\n');
    if (body) cues.push({ start, end, text: body });
  }
  return cues;
}

function vttTime(seconds) {
  const t = Math.max(0, seconds);
  const h = Math.floor(t / 3600);
  const m = Math.floor((t % 3600) / 60);
  const s = t % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${s.toFixed(3).padStart(6, '0')}`;
}

/** Writes cues as WebVTT, shifted by `delay` seconds (positive shows them later). */
export function toWebVTT(cues, delay = 0) {
  const out = ['WEBVTT', ''];
  for (const cue of cues) {
    const start = cue.start + delay;
    const end = cue.end + delay;
    if (end <= 0) continue;
    // Replace the timing arrow before escaping, or `>` is already gone.
    const text = cue.text.replace(/-->/g, '→').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    out.push(`${vttTime(start)} --> ${vttTime(end)}`, text, '');
  }
  return out.join('\n');
}
