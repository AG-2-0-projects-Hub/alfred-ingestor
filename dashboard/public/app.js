'use strict';

/* HostWhisperer command dashboard — vanilla frontend.
 * Migration note: every request goes through API_BASE. To host this as an admin
 * sub-site later, point API_BASE at the hosted API — nothing else changes. */
const API_BASE = '';

const $ = (sel) => document.querySelector(sel);
const el = (tag, cls, txt) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (txt != null) n.textContent = txt;
  return n;
};

async function api(path, opts) {
  const res = await fetch(API_BASE + path, opts);
  if (!res.ok) {
    let msg = res.statusText;
    try { msg = (await res.json()).error || msg; } catch {}
    throw new Error(msg);
  }
  return res.json();
}

function toast(msg, kind) {
  const t = el('div', 'toast' + (kind ? ' ' + kind : ''), msg);
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 3200);
}

/* ---------- collapse/expand for the three top cards ---------- */
document.querySelectorAll('.card-head[data-toggle]').forEach((btn) => {
  btn.addEventListener('click', () => {
    const card = btn.closest('.card');
    const body = card.querySelector('.card-body');
    const open = card.classList.toggle('open');
    body.hidden = !open;
  });
});

/* ---------- ROADMAP ---------- */
const STATUS_CYCLE = { todo: 'progress', progress: 'done', done: 'todo' };
const STATUS_ICON = { todo: '⬜', progress: '🔨', done: '✅' };

async function loadRoadmap() {
  const data = await api('/api/roadmap');
  $('#roadmapSummary').textContent =
    `${data.summary.trackCount} tracks · ${data.summary.doneItems}/${data.summary.totalItems} done · ${data.summary.percent}%`;

  const body = $('#roadmapBody');
  body.innerHTML = '';

  data.tracks.forEach((t) => {
    const track = el('div', 'track');

    const head = el('button', 'track-head');
    head.appendChild(el('span', 'track-num', String(t.number)));
    head.appendChild(el('span', 'track-name', t.title));
    const prog = el('span', 'track-prog');
    const bar = el('span', 'bar');
    const fill = el('i');
    const pct = t.summary.total ? Math.round((t.summary.done / t.summary.total) * 100) : 0;
    fill.style.width = pct + '%';
    bar.appendChild(fill);
    prog.appendChild(bar);
    prog.appendChild(el('span', 'frac', `${t.summary.done}/${t.summary.total}`));
    head.appendChild(prog);
    head.addEventListener('click', () => track.classList.toggle('open'));
    track.appendChild(head);

    const items = el('div', 'track-items');
    t.items.forEach((it) => {
      const row = el('div', 'item' + (it.status === 'done' ? ' done' : ''));

      const toggle = el('button', 'status-toggle', STATUS_ICON[it.status] || '⬜');
      toggle.title = 'Click to change status';
      toggle.addEventListener('click', async (e) => {
        e.stopPropagation();
        const next = STATUS_CYCLE[it.status] || 'progress';
        try {
          await api('/api/roadmap/update', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ text: it.text, next }),
          });
          it.status = next;
          toggle.textContent = STATUS_ICON[next];
          row.classList.toggle('done', next === 'done');
          refreshSummaries();
        } catch (err) { toast(err.message, 'err'); }
      });
      row.appendChild(toggle);

      row.appendChild(el('span', 'tier ' + (it.tier || 'none')));
      row.appendChild(el('span', 'item-text', it.text));
      if (it.milestone) row.appendChild(el('span', 'ms ' + it.milestone, it.milestone));
      items.appendChild(row);
    });
    track.appendChild(items);
    body.appendChild(track);
  });
}

/* ---------- QA ---------- */
async function loadScenarios() {
  const data = await api('/api/scenarios');
  const s = data.summary;
  $('#qaSummary').textContent =
    `${s.passing} pass · ${s.failing} fail · ${s.pending} pending · ${s.skipped} skipped`;

  const body = $('#qaBody');
  body.innerHTML = '';

  data.sections.forEach((sec) => {
    const wrap = el('div', 'qa-section');
    const head = el('button', 'qa-sec-head');
    head.appendChild(el('span', 'qa-sec-letter', sec.letter));
    head.appendChild(el('span', 'qa-sec-title', sec.title));
    const dots = el('span', 'qa-dots');
    sec.scenarios.forEach((sc) => dots.appendChild(el('span', 'dot ' + sc.status)));
    head.appendChild(dots);
    head.addEventListener('click', () => wrap.classList.toggle('open'));
    wrap.appendChild(head);

    const rows = el('div', 'qa-rows');
    sec.scenarios.forEach((sc) => {
      const row = el('div', 'qa-row');
      row.appendChild(el('span', 'code', sc.code || ''));
      row.appendChild(el('span', 'nm', sc.name));
      if (sc.layer) row.appendChild(el('span', 'layer', 'L' + sc.layer));
      row.appendChild(el('span', 'st-label ' + sc.status, sc.status));
      rows.appendChild(row);
    });
    wrap.appendChild(rows);
    body.appendChild(wrap);
  });
}

/* ---------- GIT ---------- */
async function loadGit() {
  const data = await api('/api/git');
  $('#branchChip').textContent = data.branch + (data.dirty ? ` · ●${data.dirty}` : ' · clean');
  const last = data.log[0] ? data.log[0].subject : '—';
  $('#gitSummary').textContent = `${data.branch} · last: ${last.slice(0, 42)}${last.length > 42 ? '…' : ''}`;

  const body = $('#gitBody');
  body.innerHTML = '';
  const br = el('div', 'git-branch');
  br.innerHTML = `on <b>${data.branch}</b>`;
  body.appendChild(br);

  data.log.forEach((c) => {
    const row = el('div', 'commit');
    row.appendChild(el('span', 'hash', c.hash));
    row.appendChild(el('span', 'subj', c.subject));
    body.appendChild(row);
  });

  const filesWrap = el('div', 'git-files');
  filesWrap.appendChild(el('div', 'fh', 'Uncommitted'));
  if (!data.files.length) {
    filesWrap.appendChild(el('div', 'clean', '✓ working tree clean'));
  } else {
    data.files.forEach((f) => {
      const row = el('div', 'gfile');
      row.appendChild(el('span', 'gc', f.code || '·'));
      row.appendChild(el('span', 'gf', f.file));
      filesWrap.appendChild(row);
    });
  }
  body.appendChild(filesWrap);
}

/* ---------- attention strip ---------- */
async function loadAttention() {
  const data = await api('/api/attention');
  const strip = $('#attention');
  strip.innerHTML = '';
  if (!data.items.length) { strip.hidden = true; return; }
  strip.hidden = false;
  strip.appendChild(el('span', 'att-title', '⚠ Needs attention'));
  data.items.forEach((i) => strip.appendChild(el('span', 'att-item', i.label)));
}

function refreshSummaries() {
  loadAttention().catch(() => {});
  loadRoadmap().catch(() => {});
}

/* ---------- QA smoke run (SSE) ---------- */
$('#btnQa').addEventListener('click', () => {
  const term = $('#terminal');
  const out = $('#terminalOut');
  term.hidden = false;
  out.textContent = '';
  $('#btnQa').disabled = true;

  fetch(API_BASE + '/api/qa/smoke', { method: 'POST' }).then((res) => {
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buf = '';
    const pump = () => reader.read().then(({ done, value }) => {
      if (done) { $('#btnQa').disabled = false; return; }
      buf += decoder.decode(value, { stream: true });
      const events = buf.split('\n\n');
      buf = events.pop();
      for (const ev of events) {
        const evtLine = ev.match(/event: (.+)/);
        const dataLine = ev.match(/data: (.+)/);
        if (!evtLine || !dataLine) continue;
        const kind = evtLine[1];
        const payload = JSON.parse(dataLine[1]);
        if (kind === 'log') { out.textContent += payload; out.scrollTop = out.scrollHeight; }
        else if (kind === 'done') {
          out.textContent += `\n[exit ${payload.code}]\n`;
          toast(payload.code === 0 ? 'QA smoke passed' : 'QA smoke finished with failures', payload.code === 0 ? 'ok' : 'err');
          loadScenarios().catch(() => {});
        }
      }
      return pump();
    });
    pump();
  }).catch((e) => { toast(e.message, 'err'); $('#btnQa').disabled = false; });
});
$('#termClose').addEventListener('click', () => { $('#terminal').hidden = true; });

/* ---------- boot ---------- */
$('#btnRefresh').addEventListener('click', boot);
function boot() {
  loadAttention().catch((e) => toast('attention: ' + e.message, 'err'));
  loadRoadmap().catch((e) => { $('#roadmapSummary').textContent = 'error'; toast('roadmap: ' + e.message, 'err'); });
  loadScenarios().catch((e) => { $('#qaSummary').textContent = 'error'; toast('qa: ' + e.message, 'err'); });
  loadGit().catch((e) => { $('#gitSummary').textContent = 'error'; toast('git: ' + e.message, 'err'); });
}
boot();
