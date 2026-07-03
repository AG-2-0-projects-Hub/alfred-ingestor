'use strict';

/**
 * server.js — HostWhisperer local command dashboard.
 *
 * Two clearly separated layers:
 *   READ layer   — pure data (roadmap, scenarios, git status, attention).
 *                  No shell side-effects → portable to a serverless admin sub-site.
 *   ACTION layer — everything in ./actions.js (git commit/push, QA run, roadmap edit).
 *                  Local-only; the obvious swap point when hosted.
 *
 * AUTH hook: `requireAdmin` is a no-op on localhost. When this becomes an admin
 * sub-site, put the gate there and it protects every route below it.
 */

const express = require('express');
const fs = require('fs');
const path = require('path');

const { parseRoadmap } = require('./parsers/roadmap');
const { parseScenarios } = require('./parsers/scenarios');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const ROADMAP_PATH = path.join(ROOT, 'ROADMAP.md');
const SCENARIOS_PATH = path.join(ROOT, '_tests', 'scenarios.md');
const PORT = process.env.PORT || 3333;

const app = express();
app.use(express.json());

// --- AUTH hook (no-op locally; insertion point for admin gating when hosted) ---
function requireAdmin(req, res, next) {
  return next();
}

// --- small helpers ------------------------------------------------------------
function readFileSafe(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch { return null; }
}
function git(args) {
  try {
    return execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 }).trim();
  } catch { return ''; }
}

// =============================================================================
// READ LAYER (portable — no shell side-effects beyond read-only git queries)
// =============================================================================

app.get('/api/roadmap', requireAdmin, (req, res) => {
  const md = readFileSafe(ROADMAP_PATH);
  if (md === null) return res.status(404).json({ error: 'ROADMAP.md not found' });
  res.json(parseRoadmap(md));
});

app.get('/api/scenarios', requireAdmin, (req, res) => {
  const md = readFileSafe(SCENARIOS_PATH);
  if (md === null) return res.status(404).json({ error: 'scenarios.md not found' });
  res.json(parseScenarios(md));
});

app.get('/api/git', requireAdmin, (req, res) => {
  const branch = git(['rev-parse', '--abbrev-ref', 'HEAD']);
  const log = git(['log', '--oneline', '-8']).split('\n').filter(Boolean).map((l) => {
    const sp = l.indexOf(' ');
    return { hash: l.slice(0, sp), subject: l.slice(sp + 1) };
  });
  const statusRaw = git(['status', '--short']).split('\n').filter(Boolean);
  const files = statusRaw.map((l) => ({ code: l.slice(0, 2).trim(), file: l.slice(3) }));
  res.json({ branch, log, files, dirty: files.length });
});

/** Derived "needs attention" summary that powers the top strip. */
app.get('/api/attention', requireAdmin, (req, res) => {
  const items = [];

  const statusRaw = git(['status', '--short']).split('\n').filter(Boolean);
  if (statusRaw.length) items.push({ kind: 'git', label: `${statusRaw.length} uncommitted file${statusRaw.length > 1 ? 's' : ''}` });

  const scMd = readFileSafe(SCENARIOS_PATH);
  if (scMd) {
    const { summary } = parseScenarios(scMd);
    if (summary.failing) items.push({ kind: 'qa', label: `${summary.failing} failing scenario${summary.failing > 1 ? 's' : ''}` });
  }

  const rmMd = readFileSafe(ROADMAP_PATH);
  if (rmMd) {
    const { tracks } = parseRoadmap(rmMd);
    let unmet = 0;
    for (const t of tracks) for (const it of t.items) if (it.tier === 'necessary' && it.status !== 'done') unmet++;
    if (unmet) items.push({ kind: 'roadmap', label: `${unmet} 🔴 necessary item${unmet > 1 ? 's' : ''} open` });
  }

  res.json({ items });
});

// =============================================================================
// ACTION LAYER (local-only — isolated in ./actions.js)
// Git commit/push intentionally excluded — committing is done from the chat,
// not the dashboard. The dashboard is an overview + two lightweight actions:
// roadmap status toggle and the QA smoke run.
// =============================================================================
const actions = require('./actions');

app.post('/api/roadmap/update', requireAdmin, (req, res) => {
  try { res.json({ ok: true, ...actions.updateRoadmapItem(req.body || {}) }); }
  catch (e) { res.status(400).json({ error: e.message }); }
});

/** QA smoke test — Server-Sent Events stream of live runner output. */
app.post('/api/qa/smoke', requireAdmin, (req, res) => {
  res.set({
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
  });
  res.flushHeaders();
  const send = (event, data) => res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  send('start', { at: new Date().toISOString() });

  actions.runQaSmoke((chunk) => send('log', chunk))
    .then((code) => { send('done', { code }); res.end(); })
    .catch((e) => { send('done', { code: 1, error: e.message }); res.end(); });
});

// --- static frontend ----------------------------------------------------------
app.use(express.static(path.join(__dirname, 'public')));

app.listen(PORT, () => {
  console.log(`\n  hostwhisperer · command  →  http://localhost:${PORT}\n  project root: ${ROOT}\n`);
});
