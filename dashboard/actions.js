'use strict';

/**
 * actions.js — LOCAL-ONLY action layer.
 *
 * Everything with a filesystem/process side-effect lives here and NOWHERE else.
 * The read layer (server.js routes for roadmap/scenarios/git-status) stays pure so
 * it can migrate to a serverless admin sub-site unchanged. When hosted, these
 * actions get reworked or disabled behind admin auth — that swap touches only
 * this file.
 *
 * Scope is deliberately narrow: this is an OVERVIEW, not a workbench. Only two
 * actions live here — toggle a roadmap item's status, and run the QA smoke test.
 * Git commit/push is done from the chat, not the dashboard.
 *
 * Runs inside WSL (the server is launched via `wsl bash -c`), so `npm` is
 * directly on PATH — no `wsl bash -c` re-prefixing needed here.
 */

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const RUNNER_DIR = path.join(ROOT, '_tests', 'runner');
const ROADMAP_PATH = path.join(ROOT, 'ROADMAP.md');

const GLYPH_FOR = { done: '✅', progress: '🔨', todo: '' };

/**
 * Cycle a roadmap bullet's leading status glyph: todo → progress → done → todo.
 * Located by exact match on the bullet's raw inner text (glyph-stripped) so we
 * never touch the wrong line. Non-destructive to surrounding prose.
 */
function updateRoadmapItem({ text, next }) {
  if (!text) throw new Error('Item text is required');
  const target = String(next || '').toLowerCase();
  if (!(target in GLYPH_FOR)) throw new Error(`Invalid status: ${next}`);

  const md = fs.readFileSync(ROADMAP_PATH, 'utf8');
  const lines = md.split('\n');

  const norm = (s) =>
    s.replace(/\*\*/g, '').replace(/\*/g, '').replace(/\s+/g, ' ').trim();
  const wanted = norm(text);

  let matchIdx = -1;
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^-\s+(.*)$/);
    if (!m) continue;
    // Strip any existing leading status glyph before comparing.
    let inner = m[1].trimStart();
    for (const g of Object.values(GLYPH_FOR)) {
      if (g && inner.startsWith(g)) { inner = inner.slice(g.length).trimStart(); break; }
    }
    if (norm(inner) === wanted) {
      if (matchIdx !== -1) throw new Error('Ambiguous item text — matched more than one line');
      matchIdx = i;
    }
  }
  if (matchIdx === -1) throw new Error('Item not found in ROADMAP.md');

  // Rebuild the line with the new glyph.
  const original = lines[matchIdx];
  const indentMatch = original.match(/^(-\s+)(.*)$/);
  let inner = indentMatch[2].trimStart();
  for (const g of Object.values(GLYPH_FOR)) {
    if (g && inner.startsWith(g)) { inner = inner.slice(g.length).trimStart(); break; }
  }
  const glyph = GLYPH_FOR[target];
  lines[matchIdx] = `${indentMatch[1]}${glyph ? glyph + ' ' : ''}${inner}`;

  fs.writeFileSync(ROADMAP_PATH, lines.join('\n'), 'utf8');
  return { status: target, line: lines[matchIdx].trim() };
}

/**
 * Run the QA smoke test, streaming stdout/stderr line-by-line to `onData`.
 * Resolves with the exit code. Used by the SSE endpoint.
 */
function runQaSmoke(onData) {
  return new Promise((resolve) => {
    const child = spawn('npm', ['run', 'smoke'], { cwd: RUNNER_DIR, env: process.env });
    const pipe = (buf) => onData(buf.toString());
    child.stdout.on('data', pipe);
    child.stderr.on('data', pipe);
    child.on('error', (err) => { onData(`\n[dashboard] failed to start runner: ${err.message}\n`); resolve(1); });
    child.on('close', (code) => resolve(code));
  });
}

module.exports = { updateRoadmapItem, runQaSmoke, ROOT };
