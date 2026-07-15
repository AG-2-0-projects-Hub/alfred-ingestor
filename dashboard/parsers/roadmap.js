'use strict';

/**
 * roadmap.js — Portable read-layer parser for ROADMAP.md.
 *
 * Pure function of a markdown string → structured JSON. No filesystem, no shell.
 * This keeps it trivially re-hostable as a serverless route later.
 *
 * It understands our own doc conventions (see ROADMAP.md):
 *   - §5 matrix table:  | Track | M0 ... | M1 ... | M2 ... | M3 ... |
 *   - §6 track detail:  ### Track N — Title, with `- **M0:**` style bullets
 *   - inline tiers:     🔴 necessary / 🟡 helpful / 🟢 nice
 *   - leading status:   an OPTIONAL glyph right after "- " marks progress
 *                       (🔨 in-progress, ✅ done). Absent = todo.
 */

const TIER = { '🔴': 'necessary', '🟡': 'helpful', '🟢': 'nice' };
const STATUS_GLYPH = { '✅': 'done', '🔨': 'progress' };
const GLYPHS = Object.keys(STATUS_GLYPH);

/** Detect the highest-priority tier mentioned in a piece of text. */
function detectTier(text) {
  if (text.includes('🔴')) return 'necessary';
  if (text.includes('🟡')) return 'helpful';
  if (text.includes('🟢')) return 'nice';
  return null;
}

/** Detect which milestone (M0–M3) a bullet belongs to, if any. */
function detectMilestone(text) {
  const m = text.match(/\bM([0-3])\b/);
  return m ? `M${m[1]}` : null;
}

/** Strip a leading status glyph from a bullet's inner text; return {status, text}. */
function splitStatus(inner) {
  const trimmed = inner.trimStart();
  const first = [...trimmed][0];
  if (GLYPHS.includes(first)) {
    return { status: STATUS_GLYPH[first], text: trimmed.slice(first.length).trimStart() };
  }
  return { status: 'todo', text: trimmed };
}

/** Build a stable id for a bullet from its track number + normalized text. */
function bulletId(trackNum, text) {
  let hash = 0;
  const basis = `${trackNum}::${text}`;
  for (let i = 0; i < basis.length; i++) {
    hash = (hash * 31 + basis.charCodeAt(i)) | 0;
  }
  return `t${trackNum}-${(hash >>> 0).toString(36)}`;
}

/** Parse the §5 matrix table into rows keyed by milestone. */
function parseMatrix(md) {
  const lines = md.split('\n');
  const headerIdx = lines.findIndex((l) => /^\|\s*Track\s*\|/.test(l));
  if (headerIdx === -1) return [];

  const rows = [];
  for (let i = headerIdx + 2; i < lines.length; i++) {
    const line = lines[i];
    if (!line.startsWith('|')) break;
    const cells = line.split('|').slice(1, -1).map((c) => c.trim());
    if (cells.length < 5) continue;
    const name = cells[0].replace(/\*\*/g, '').trim();
    rows.push({
      track: name,
      m0: cells[1],
      m1: cells[2],
      m2: cells[3],
      m3: cells[4],
    });
  }
  return rows;
}

/** Parse the §6 track-detail sections into tracks with per-bullet metadata. */
function parseTracks(md) {
  const lines = md.split('\n');
  const tracks = [];
  let current = null;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    const header = line.match(/^###\s+Track\s+(\d+)\s+—\s+(.+?)\s*(?:\*\(new\)\*)?\s*$/);
    if (header) {
      if (current) tracks.push(current);
      current = {
        number: parseInt(header[1], 10),
        title: header[2].replace(/\*/g, '').trim(),
        objective: null,
        items: [],
      };
      continue;
    }

    // Stop collecting once we leave the track-detail section (§6).
    if (/^##\s/.test(line) && current) {
      tracks.push(current);
      current = null;
    }
    if (!current) continue;

    const obj = line.match(/^\*Objective:\*\s*(.+)$/);
    if (obj) {
      current.objective = obj[1].trim();
      continue;
    }

    // Top-level bullets only (2 leading spaces or fewer). Sub-bullets are context.
    const bullet = line.match(/^-\s+(.*)$/);
    if (bullet) {
      const { status, text } = splitStatus(bullet[1]);
      const clean = text.replace(/\*\*/g, '').replace(/\*/g, '');
      current.items.push({
        id: bulletId(current.number, clean),
        raw: bullet[1].trimStart(),
        text: clean,
        milestone: detectMilestone(text),
        tier: detectTier(text),
        status,
      });
    }
  }
  if (current) tracks.push(current);
  return tracks;
}

/** Parse a simple two-column-plus markdown table starting at a matching header. */
function parseTableAfter(md, headerRegex) {
  const lines = md.split('\n');
  const idx = lines.findIndex((l) => headerRegex.test(l));
  if (idx === -1) return [];
  const out = [];
  for (let i = idx + 2; i < lines.length; i++) {
    if (!lines[i].startsWith('|')) break;
    out.push(lines[i].split('|').slice(1, -1).map((c) => c.replace(/\*\*/g, '').trim()));
  }
  return out;
}

function parseRisks(md) {
  return parseTableAfter(md, /^\|\s*#\s*\|\s*Risk\s*\|/).map((c) => ({
    id: c[0],
    risk: c[1],
    severity: c[2],
    mitigation: c[3],
    tier: detectTier(c[4] || ''),
  }));
}

function parseDecisions(md) {
  return parseTableAfter(md, /^\|\s*#\s*\|\s*Decision/).map((c) => ({
    id: c[0],
    decision: c[1],
    gates: c[2],
    status: c[3],
  }));
}

/** Top-level entry: markdown string → full roadmap model. */
function parseRoadmap(md) {
  const versionMatch = md.match(/\*\*Version:\*\*\s*(.+)/);
  const tracks = parseTracks(md);

  // Roll up per-track completion from item statuses.
  let totalItems = 0;
  let doneItems = 0;
  for (const t of tracks) {
    const done = t.items.filter((it) => it.status === 'done').length;
    t.summary = { total: t.items.length, done };
    totalItems += t.items.length;
    doneItems += done;
  }

  return {
    version: versionMatch ? versionMatch[1].trim() : null,
    matrix: parseMatrix(md),
    tracks,
    risks: parseRisks(md),
    decisions: parseDecisions(md),
    summary: {
      trackCount: tracks.length,
      totalItems,
      doneItems,
      percent: totalItems ? Math.round((doneItems / totalItems) * 100) : 0,
    },
  };
}

module.exports = { parseRoadmap, splitStatus, STATUS_GLYPH };
