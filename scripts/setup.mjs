#!/usr/bin/env node
/**
 * Install npm workspaces + Python API requirements (cross-platform).
 */
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const REQUIREMENTS = path.join(ROOT, 'apps', 'api', 'requirements.txt');

function isWindows() {
  return process.platform === 'win32';
}

function runNpm(args) {
  // npm is a .cmd on Windows — shell required.
  console.log(`> npm ${args.join(' ')}`);
  const result = spawnSync('npm', args, {
    cwd: ROOT,
    stdio: 'inherit',
    shell: isWindows(),
    env: process.env,
  });
  if (result.error) {
    console.error(result.error.message);
    process.exit(1);
  }
  if (result.status !== 0) process.exit(result.status ?? 1);
}

/** Never shell:true for Python — breaks `-c` on Windows. */
function runPython(cmd, args) {
  console.log(`> ${cmd} ${args.join(' ')}`);
  const result = spawnSync(cmd, args, {
    cwd: ROOT,
    stdio: 'inherit',
    shell: false,
    env: process.env,
  });
  if (result.error) {
    console.error(result.error.message);
    process.exit(1);
  }
  if (result.status !== 0) process.exit(result.status ?? 1);
}

function runCapture(cmd, args) {
  return spawnSync(cmd, args, {
    encoding: 'utf8',
    cwd: ROOT,
    shell: false,
    env: process.env,
  });
}

function pythonCandidates() {
  const list = [];
  list.push({ cmd: 'python3', args: [] });
  if (isWindows()) {
    list.push({ cmd: 'py', args: ['-3.12'] });
    list.push({ cmd: 'py', args: ['-3'] });
  } else {
    list.push({ cmd: 'python3.12', args: [] });
    list.push({ cmd: 'python3.11', args: [] });
  }
  list.push({ cmd: 'python', args: [] });
  return list;
}

function isCondaPath(executable) {
  const p = (executable || '').toLowerCase();
  return p.includes('miniconda') || p.includes('anaconda') || p.includes(`${path.sep}conda${path.sep}`);
}

function scorePython(info, index) {
  let score = 100 - index;
  if (info.minor >= 11 && info.minor <= 13) score += 50;
  else if (info.minor === 10) score += 20;
  else if (info.minor >= 14) score -= 30;
  if (isCondaPath(info.executable)) score -= 40;
  return score;
}

function findPython() {
  /** @type {{ cmd: string, args: string[], executable: string, minor: number, index: number }[]} */
  const found = [];
  pythonCandidates().forEach((c, index) => {
    const probe = runCapture(c.cmd, [
      ...c.args,
      '-c',
      'import sys; print(sys.version_info[0]); print(sys.version_info[1]); print(sys.executable)',
    ]);
    if (probe.error || probe.status !== 0) return;
    const lines = (probe.stdout || '')
      .trim()
      .split(/\r?\n/)
      .map((l) => l.trim())
      .filter(Boolean);
    if (lines[0] !== '3' || !lines[2]) return;
    const minor = Number(lines[1]);
    if (Number.isNaN(minor)) return;
    found.push({ ...c, executable: lines[2], minor, index });
  });
  if (!found.length) return null;
  found.sort((a, b) => scorePython(b, b.index) - scorePython(a, a.index));
  const preferred = found[0];
  return { cmd: preferred.cmd, args: preferred.args };
}

function main() {
  console.log('Installing npm workspaces…');
  runNpm(['install']);

  if (!fs.existsSync(REQUIREMENTS)) {
    console.error(`Missing ${REQUIREMENTS}`);
    process.exit(1);
  }

  const py = findPython();
  if (!py) {
    console.error(
      [
        'No Python 3 found (tried python3, py -3.12, py -3, python).',
        'Install Python 3.11+ then re-run: npm run setup',
      ].join('\n'),
    );
    process.exit(1);
  }

  const label = [py.cmd, ...py.args].join(' ');
  console.log(`Installing API requirements with ${label}…`);
  runPython(py.cmd, [...py.args, '-m', 'pip', 'install', '-r', REQUIREMENTS]);

  console.log('\nSetup complete. Next:');
  console.log('  npm run dev');
  console.log('Optional: copy .env.example → .env at repo root');
}

main();
