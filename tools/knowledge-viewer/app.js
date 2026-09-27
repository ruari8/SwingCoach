const $ = selector => document.querySelector(selector);
let library, selected, clipEnd = null;
const available = new Set();
const media = path => '/media/' + path.split('/').map(encodeURIComponent).join('/');
const time = seconds => `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, '0')}`;
const label = key => key.replaceAll('_', ' ');
function node(tag, text, className) {
  const el = document.createElement(tag);
  if (text !== undefined) el.textContent = text;
  if (className) el.className = className;
  return el;
}
function link(text, url) {
  const a = node('a', text); a.href = url; a.target = '_blank'; a.rel = 'noopener'; return a;
}
function valueView(value) {
  if (Array.isArray(value)) {
    const ul = node('ul');
    value.forEach(v => { const li = node('li'); li.append(valueView(v)); ul.append(li); });
    if (!value.length) ul.append(node('li', 'None recorded.'));
    return ul;
  }
  if (value && typeof value === 'object') {
    const dl = node('dl');
    Object.entries(value).forEach(([k, v]) => { dl.append(node('dt', label(k))); const dd = node('dd'); dd.append(valueView(v)); dl.append(dd); });
    return dl;
  }
  return node('span', value == null ? 'Not recorded.' : String(value));
}
function seek(start, end = null) {
  const video = $('video');
  if (!video) return;
  clipEnd = end;
  video.currentTime = start;
  video.play().catch(() => { $('#playback-status').textContent = 'Press play to watch this moment.'; });
  $('#playback-status').textContent = end === null ? `From ${time(start)}` : `${time(start)}–${time(end)}`;
}
function renderList() {
  const terms = $('#search').value.toLowerCase().split(/\s+/).filter(Boolean);
  const cases = library.cases.filter(c => (!$('#source').value || c.source_id === $('#source').value)
    && (!$('#phase').value || (c.tags.phase || []).includes($('#phase').value))
    && terms.every(t => JSON.stringify(c).toLowerCase().includes(t)));
  $('#count').textContent = `${cases.length} of ${library.cases.length} cases`;
  $('#cases').replaceChildren();
  cases.forEach(c => {
    const b = node('button', undefined, 'case'); b.type = 'button';
    b.setAttribute('aria-current', String(c.id === selected));
    b.append(node('strong', c.title), node('small', c.publisher), node('small', (c.tags.phase || []).join(' · ')));
    b.onclick = () => { location.hash = encodeURIComponent(c.id); };
    $('#cases').append(b);
  });
  if (!cases.length) $('#cases').append(node('p', 'No cases match. Try fewer words or clear the filters.'));
}
async function selectCase(id) {
  const c = library.cases.find(c => c.id === id);
  if (!c) return;
  selected = c.id; clipEnd = null; renderList();
  const source = library.sources.find(s => s.source_id === c.source_id);
  const detail = $('#detail'); detail.replaceChildren();
  detail.append(node('p', c.publisher, 'eyebrow'), node('h2', c.title), node('p', c.source_title, 'meta'));
  const tags = node('div'); Object.values(c.tags).flat().forEach(t => tags.append(node('span', t, 'tag'))); detail.append(tags);
  detail.append(node('p', 'Source checked · Independent coach validation pending. Applicability to your swing still needs evidence.', 'note'));
  if (available.has(source.assets.video)) {
    const video = node('video'); video.controls = true; video.preload = 'metadata'; video.playsInline = true;
    video.src = media(source.assets.video); detail.append(video);
    video.addEventListener('timeupdate', () => { if (clipEnd !== null && video.currentTime >= clipEnd && $('#stop-at-end').checked) { video.pause(); clipEnd = null; } });
    const playback = node('div', undefined, 'playback'); const status = node('span', 'Choose an evidence moment below.'); status.id = 'playback-status';
    const toggle = node('label', 'Stop at end of moment'); const check = node('input'); check.type = 'checkbox'; check.checked = true; check.id = 'stop-at-end'; toggle.prepend(check);
    playback.append(status, toggle); detail.append(playback);
  } else detail.append(node('p', 'Video is not on this computer. The coaching record and original source link remain available.', 'note'));
  const links = node('div', undefined, 'source-links'); links.append(link('Open original source ↗', source.url));
  if (available.has(source.assets.reading_index)) links.append(link('Full transcript ↗', media(source.assets.reading_index)));
  detail.append(links);
  const copy = node('div', undefined, 'case-copy'); detail.append(copy);
  for (const [key, heading] of [['coaching_finding', 'What the coach saw'], ['coach_reasoning', 'Why this advice'], ['intervention', 'What to do'], ['applicability', 'When this applies'], ['unknowns', 'What remains unknown'], ['observed_result', 'What happened afterwards'], ['selection', 'Choosing and reassessing this case']]) {
    copy.append(node('h3', heading), valueView(c[key]));
  }
  if (c.alternative_case_ids.length) {
    copy.append(node('h3', 'Related decisions'));
    c.alternative_case_ids.forEach(id => { const other = library.cases.find(x => x.id === id); if (other) { const p = node('p'); const a = node('a', other.title); a.href = '#' + encodeURIComponent(id); p.append(a); copy.append(p); } });
  }
  detail.append(node('h3', 'Watch the evidence'));
  c.evidence.forEach(e => {
    const section = node('section', undefined, 'evidence');
    const b = node('button', `${time(e.span_seconds[0])}–${time(e.span_seconds[1])} · Play moment`, 'action');
    b.disabled = !available.has(source.assets.video); b.onclick = () => { seek(...e.span_seconds); $('video')?.scrollIntoView({behavior:'smooth', block:'center'}); };
    section.append(b, node('p', e.summary), node('p', `${e.attribution || ''} · ${label(e.kind || '')}`, 'meta'));
    const frames = node('div', undefined, 'frames');
    (e.frames || []).forEach(f => {
      if (!available.has(f.path)) return;
      const frame = node('button', undefined, 'frame'); const img = node('img'); img.src = media(f.path); img.alt = f.observation || `Frame at ${time(f.time_seconds)}`; img.loading = 'lazy';
      frame.append(img, node('span', `${time(f.time_seconds)} · ${f.observation || ''}`)); frame.onclick = () => seek(f.time_seconds); frames.append(frame);
    });
    section.append(frames);
    if (e.limitations?.length) section.append(valueView(e.limitations));
    detail.append(section);
  });
  const provenance = node('details'); provenance.append(node('summary', 'Source context and extraction coverage'), valueView(source.context), valueView(source.coverage)); detail.append(provenance);
  const raw = node('details'); raw.append(node('summary', 'Structured case record'), node('pre', JSON.stringify(c, null, 2))); detail.append(raw);
  if (available.has(source.assets.transcript)) {
    const transcript = node('details'); transcript.append(node('summary', 'Timestamped transcript')); const rows = node('div', undefined, 'transcript'); transcript.append(rows); detail.append(transcript);
    try {
      const response = await fetch(media(source.assets.transcript)); if (!response.ok) throw Error('Transcript unavailable');
      const segments = await response.json();
      if (selected !== id) return;
      (Array.isArray(segments) ? segments : segments.segments || []).forEach(s => {
        const b = node('button', `${time(s.start)}  ${s.text}`); b.onclick = () => seek(s.start, s.end); rows.append(b);
      });
    } catch { rows.append(node('p', 'Could not load the local transcript.', 'error')); }
  }
}
async function init() {
  try {
    const response = await fetch('/api/library'); if (!response.ok) throw Error('Library request failed');
    library = await response.json(); library.available_assets.forEach(p => available.add(p));
    $('#stats').textContent = `${library.sources.length} sources · ${library.cases.length} coaching cases · Local videos and timestamped evidence`;
    library.sources.forEach(s => { const option = node('option', `${s.publisher} · ${s.title}`); option.value = s.source_id; $('#source').append(option); });
    [...new Set(library.cases.flatMap(c => c.tags.phase || []))].sort().forEach(p => { const option = node('option', p); option.value = p; $('#phase').append(option); });
    for (const id of ['search', 'source', 'phase']) $('#' + id).addEventListener('input', renderList);
    window.addEventListener('hashchange', () => selectCase(decodeURIComponent(location.hash.slice(1))));
    const id = decodeURIComponent(location.hash.slice(1));
    await selectCase(library.cases.some(c => c.id === id) ? id : 'DcqwwGio81y-C02');
  } catch (error) { $('#stats').textContent = `Could not load library: ${error.message}`; }
}
init();
