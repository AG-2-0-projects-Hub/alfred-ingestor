'use strict';

/**
 * scenarios.js — Portable read-layer parser for _tests/scenarios.md.
 *
 * Pure function of a markdown string → structured JSON. No filesystem, no shell.
 *
 * Doc conventions (see _tests/scenarios.md):
 *   - `## A. Section title`      → section grouping
 *   - `### A1. Scenario name`    → one scenario
 *   - `- **status:** passing`    → YAML-ish metadata lines
 *   - layer may be "1", "2", "4" or a compound like "1 + 2"
 */

const STATUSES = ['passing', 'failing', 'pending', 'skipped'];

/** Pull a `- **key:** value` metadata value out of a scenario block. */
function metaValue(block, key) {
  const re = new RegExp(`^-\\s*\\*\\*${key}:\\*\\*\\s*(.+)$`, 'm');
  const m = block.match(re);
  return m ? m[1].trim() : null;
}

function normalizeStatus(raw) {
  if (!raw) return 'pending';
  const found = STATUSES.find((s) => raw.toLowerCase().includes(s));
  return found || 'pending';
}

function parseScenarios(md) {
  const lines = md.split('\n');
  const scenarios = [];
  let section = null;
  let sectionLetter = null;

  // Collect scenario blocks by scanning for ### headers.
  const blocks = [];
  let currentHeader = null;
  let buffer = [];

  const flush = () => {
    if (currentHeader) blocks.push({ header: currentHeader, section, sectionLetter, body: buffer.join('\n') });
    buffer = [];
  };

  for (const line of lines) {
    const sec = line.match(/^##\s+([A-Z])\.\s+(.+)$/);
    if (sec) {
      flush();
      currentHeader = null;
      sectionLetter = sec[1];
      section = sec[2].trim();
      continue;
    }
    const head = line.match(/^###\s+(.+)$/);
    if (head) {
      flush();
      currentHeader = head[1].trim();
      continue;
    }
    if (currentHeader) buffer.push(line);
  }
  flush();

  for (const b of blocks) {
    // Skip non-scenario ### blocks (only keep ones with an id or status).
    const id = metaValue(b.body, 'id');
    const statusRaw = metaValue(b.body, 'status');
    if (!id && !statusRaw) continue;

    const layerRaw = metaValue(b.body, 'layer');
    scenarios.push({
      code: (b.header.match(/^([A-Z]\d+)\b/) || [])[1] || null,
      name: b.header.replace(/^[A-Z]\d+\.\s*/, '').trim(),
      section: b.section,
      sectionLetter: b.sectionLetter,
      id,
      layer: layerRaw,
      status: normalizeStatus(statusRaw),
      lastTested: metaValue(b.body, 'last_tested'),
    });
  }

  const summary = { passing: 0, failing: 0, pending: 0, skipped: 0, total: scenarios.length };
  for (const s of scenarios) summary[s.status]++;

  // Group by section for the collapsed UI.
  const sections = {};
  for (const s of scenarios) {
    const key = s.sectionLetter || '?';
    if (!sections[key]) sections[key] = { letter: key, title: s.section, scenarios: [] };
    sections[key].scenarios.push(s);
  }

  return {
    scenarios,
    sections: Object.values(sections),
    summary,
  };
}

module.exports = { parseScenarios };
