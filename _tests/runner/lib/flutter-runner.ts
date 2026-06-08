import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const frontendDir = resolve(__dirname, '../../../frontend');

// Runs `flutter test <relativePath>` against the frontend project.
// Returns parsed result: pass/fail + raw stdout for the HTML report.
export async function runFlutterTest(
  relativeTestPath: string,
): Promise<{ pass: boolean; stdout: string; stderr: string }> {
  return new Promise(resolveP => {
    // Snap path for Flutter on WSL — matches the convention in the project.
    // XDG_RUNTIME_DIR workaround to dodge the snap XDG warning.
    const env = {
      ...process.env,
      XDG_RUNTIME_DIR: '/tmp/xdg-flutter-qa',
    };

    const stdoutChunks: string[] = [];
    const stderrChunks: string[] = [];

    const child = spawn(
      '/snap/bin/flutter',
      ['test', '--reporter=expanded', relativeTestPath],
      { cwd: frontendDir, env },
    );

    child.stdout.on('data', d => stdoutChunks.push(d.toString()));
    child.stderr.on('data', d => stderrChunks.push(d.toString()));

    child.on('close', code => {
      resolveP({
        pass: code === 0,
        stdout: stdoutChunks.join(''),
        stderr: stderrChunks.join(''),
      });
    });

    child.on('error', err => {
      resolveP({
        pass: false,
        stdout: stdoutChunks.join(''),
        stderr: `Failed to spawn flutter: ${err.message}`,
      });
    });
  });
}
