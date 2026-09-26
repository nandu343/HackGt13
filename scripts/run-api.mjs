#!/usr/bin/env node
/**
 * Cross-platform API launcher.
 * Finds a working Python, ensures deps, runs uvicorn so `app` always resolves.
 */
import { spawnSync, spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const API_DIR = path.join(ROOT, 'apps', 'api');
const REQUIREMENTS = path.join(API_DIR, 'requirements.txt');
const HOST = process.env.API_HOST || '0.0.0.0';
const PORT = process.env.API_PORT || '8000';

function isWindows() {
  return process.platform === 'win32';
}

/** @returns {{ cmd: string, args: string[] }[]} */
function pythonCandidates() {
  const list = [];
  // Order: python3 → py -3.12 → py -3 → python (then score by version / non-conda).
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

/**
 * Never use shell:true for Python — on Windows it breaks `-c` / semicolons.
 * @returns {{ status: number|null, stdout: string, stderr: string, error?: Error }}
 */
function runCapture(cmd, args, opts = {}) {
  const result = spawnSync(cmd, args, {
    encoding: 'utf8',
    cwd: opts.cwd || ROOT,
    env: opts.env || process.env,
    shell: false,
  });
  return {
    status: result.status,
    stdout: (result.stdout || '').trim(),
    stderr: (result.stderr || '').trim(),
    error: result.error,
  };
}

function isCondaPath(executable) {
  const p = (executable || '').toLowerCase();
  return p.includes('miniconda') || p.includes('anaconda') || p.includes(`${path.sep}conda${path.sep}`);
}

function looksBroken(stderr, stdout) {
  const text = `${stderr}\n${stdout}`.toLowerCase();
  return (
    text.includes('microsoft store') ||
    text.includes('python was not found') ||
    text.includes('not recognized') ||
    (text.includes('conda') &&
      (text.includes('failed to activate') ||
        text.includes('not a conda environment') ||
        text.includes('conda-meta')))
  );
}

/**
 * @param {{ cmd: string, args: string[] }} candidate
 * @returns {{ ok: boolean, executable?: string, major?: number, minor?: number }}
 */
function pythonWorks(candidate) {
  const probe = runCapture(candidate.cmd, [
    ...candidate.args,
    '-c',
    'import sys; print(sys.executable); print(sys.version_info[0]); print(sys.version_info[1])',
  ]);
  if (probe.error || probe.status !== 0) return { ok: false };
  if (looksBroken(probe.stderr, probe.stdout)) return { ok: false };
  const lines = probe.stdout.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  const executable = lines[0];
  const major = Number(lines[1]);
  const minor = Number(lines[2]);
  if (!executable || major !== 3 || Number.isNaN(minor)) return { ok: false };
  return { ok: true, executable, major, minor };
}

/** Prefer 3.11–3.13 (wheels); demote very new/old minors and conda. */
function scorePython(info, index) {
  let score = 100 - index; // stable order among equals
  if (info.minor >= 11 && info.minor <= 13) score += 50;
  else if (info.minor === 10) score += 20;
  else if (info.minor >= 14) score -= 30; // may lack binary wheels yet
  if (isCondaPath(info.executable)) score -= 40;
  return score;
}

/**
 * @param {{ cmd: string, args: string[] }} py
 */
function hasFastapi(py) {
  const check = runCapture(py.cmd, [...py.args, '-c', 'import fastapi, uvicorn']);
  return check.status === 0 && !check.error;
}

/**
 * @param {{ cmd: string, args: string[] }} py
 */
function pipInstall(py) {
  if (!fs.existsSync(REQUIREMENTS)) {
    console.error(`Missing requirements: ${REQUIREMENTS}`);
    process.exit(1);
  }
  console.log(`Installing API deps with ${[py.cmd, ...py.args].join(' ')}…`);
  const result = spawnSync(
    py.cmd,
    [...py.args, '-m', 'pip', 'install', '-r', REQUIREMENTS],
    {
      cwd: ROOT,
      stdio: 'inherit',
      shell: false,
      env: process.env,
    },
  );
  if (result.status !== 0) {
    console.error('pip install failed. Install Python 3.11+ and retry: npm run setup');
    process.exit(result.status ?? 1);
  }
}

function findPython() {
  const tried = [];
  /** @type {{ candidate: { cmd: string, args: string[] }, executable: string, major: number, minor: number, index: number }[]} */
  const found = [];

  pythonCandidates().forEach((candidate, index) => {
    const label = [candidate.cmd, ...candidate.args].join(' ');
    tried.push(label);
    const result = pythonWorks(candidate);
    if (!result.ok || !result.executable) return;
    found.push({
      candidate,
      executable: result.executable,
      major: result.major ?? 3,
      minor: result.minor ?? 0,
      index,
    });
  });

  if (!found.length) {
    console.error(
      [
        'No working Python 3 found.',
        `Tried: ${tried.join(', ')}`,
        'Install Python 3.11+ from https://www.python.org/downloads/',
        'On Windows, enable "py launcher". On Mac: brew install python@3.12',
      ].join('\n'),
    );
    process.exit(1);
  }

  found.sort((a, b) => scorePython(b, b.index) - scorePython(a, a.index));
  const preferred = found[0];
  console.log(
    `Resolved ${preferred.executable} (3.${preferred.minor})`,
  );
  return preferred.candidate;
}

function main() {
  if (!fs.existsSync(path.join(API_DIR, 'app', 'main.py'))) {
    console.error(`API not found at ${API_DIR}`);
    process.exit(1);
  }

  const py = findPython();
  const label = [py.cmd, ...py.args].join(' ');
  console.log(`Using Python: ${label}`);

  if (!hasFastapi(py)) {
    console.warn('fastapi/uvicorn missing — installing apps/api/requirements.txt…');
    pipInstall(py);
    if (!hasFastapi(py)) {
      console.error('fastapi still missing after pip install.');
      process.exit(1);
    }
  }

  const env = {
    ...process.env,
    // Ensure `import app` works even if cwd changes
    PYTHONPATH: [API_DIR, process.env.PYTHONPATH].filter(Boolean).join(path.delimiter),
  };

  const uvicornArgs = [
    ...py.args,
    '-m',
    'uvicorn',
    'app.main:app',
    '--reload',
    '--host',
    HOST,
    '--port',
    String(PORT),
  ];

  console.log(
    `Starting API at http://${HOST}:${PORT} (cwd=${path.relative(ROOT, API_DIR) || '.'})`,
  );

  const child = spawn(py.cmd, uvicornArgs, {
    cwd: API_DIR,
    env,
    stdio: 'inherit',
    shell: false,
  });

  child.on('exit', (code, signal) => {
    if (signal) process.kill(process.pid, signal);
    process.exit(code ?? 1);
  });
}

main();
