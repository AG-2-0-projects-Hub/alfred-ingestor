import { writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import type { ScenarioResult } from '../run.ts';

const __dirname = dirname(fileURLToPath(import.meta.url));
const reportsDir = resolve(__dirname, '../../reports');

export async function generateReport(
  runId: string,
  results: ScenarioResult[],
  totalDurationMs: number,
): Promise<string> {
  await mkdir(reportsDir, { recursive: true });

  const passed = results.filter(r => r.status === 'pass').length;
  const failed = results.filter(r => r.status === 'fail').length;
  const timestamp = new Date().toISOString();

  const html = renderHtml(runId, results, totalDurationMs, timestamp, passed, failed);
  const filename = `${timestamp.replace(/[:.]/g, '-')}-${runId.slice(0, 8)}.html`;
  const fullPath = resolve(reportsDir, filename);

  await writeFile(fullPath, html, 'utf-8');
  return fullPath;
}

function renderHtml(
  runId: string,
  results: ScenarioResult[],
  totalDurationMs: number,
  timestamp: string,
  passed: number,
  failed: number,
): string {
  const rows = results.map(r => {
    const badge = r.status === 'pass'
      ? '<span class="badge pass">PASS</span>'
      : '<span class="badge fail">FAIL</span>';

    const artifactsBlock = r.artifacts
      ? `<details><summary>Artifacts</summary><pre>${escapeHtml(
          JSON.stringify(r.artifacts, (key, value) => {
            if (typeof value === 'string' && value.length > 200 && /^[A-Za-z0-9+/=]+$/.test(value)) {
              return `[base64 png, ${value.length} chars]`;
            }
            return value;
          }, 2),
        )}</pre></details>`
      : '';

    return `
      <tr class="row-${r.status}">
        <td>${badge}</td>
        <td><code>${escapeHtml(r.id)}</code></td>
        <td>${escapeHtml(r.name)}</td>
        <td>Layer ${r.layer}</td>
        <td>${r.duration_ms} ms</td>
        <td class="details">${escapeHtml(r.details)}${artifactsBlock}</td>
      </tr>`;
  }).join('');

  return `<!doctype html>
<html><head>
<meta charset="utf-8">
<title>Alfred QA Report — ${timestamp}</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; max-width: 1100px; margin: 2rem auto; padding: 0 1rem; color: #222; }
  h1 { margin-bottom: 0.25rem; }
  .meta { color: #666; font-size: 0.9rem; margin-bottom: 1.5rem; }
  .summary { display: flex; gap: 1rem; margin: 1rem 0 2rem; }
  .stat { padding: 0.75rem 1.25rem; border-radius: 8px; background: #f3f3f3; font-weight: 600; }
  .stat.pass { background: #d4edda; color: #155724; }
  .stat.fail { background: #f8d7da; color: #721c24; }
  table { width: 100%; border-collapse: collapse; }
  th, td { padding: 0.6rem 0.5rem; text-align: left; vertical-align: top; border-bottom: 1px solid #eee; font-size: 0.92rem; }
  th { background: #fafafa; }
  .badge { display: inline-block; padding: 0.2rem 0.55rem; border-radius: 4px; font-weight: 600; font-size: 0.8rem; }
  .badge.pass { background: #c3e6cb; color: #155724; }
  .badge.fail { background: #f5c6cb; color: #721c24; }
  .row-fail td { background: #fff5f5; }
  .details { font-family: -apple-system, system-ui, sans-serif; white-space: pre-wrap; color: #444; }
  pre { background: #f7f7f7; padding: 0.5rem; border-radius: 4px; overflow-x: auto; font-size: 0.78rem; }
  code { background: #f3f3f3; padding: 0.1rem 0.3rem; border-radius: 3px; }
  details { margin-top: 0.5rem; }
  summary { cursor: pointer; color: #555; font-size: 0.85rem; }
</style>
</head><body>
  <h1>Alfred QA Report</h1>
  <div class="meta">
    Run <code>${runId}</code> · ${timestamp} · ${totalDurationMs} ms total
  </div>
  <div class="summary">
    <div class="stat pass">✓ ${passed} passed</div>
    <div class="stat fail">✗ ${failed} failed</div>
    <div class="stat">${results.length} total</div>
  </div>
  <table>
    <thead><tr><th>Result</th><th>ID</th><th>Scenario</th><th>Layer</th><th>Duration</th><th>Details</th></tr></thead>
    <tbody>${rows}</tbody>
  </table>
</body></html>`;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}
