'use strict';
// Child processes tracked per job so a timeout can kill them.

const { spawn } = require('node:child_process');

const running = new Set();

function run(cmd, args, { cwd, env, timeoutMs = 25 * 60 * 1000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { cwd, env: { ...process.env, ...env }, stdio: ['ignore', 'pipe', 'pipe'] });
    running.add(child);
    let stderr = '';
    child.stderr.on('data', (d) => (stderr = (stderr + d).slice(-4000)));
    child.stdout.on('data', () => {});
    const timer = setTimeout(() => child.kill('SIGKILL'), timeoutMs);
    child.on('error', (e) => {
      clearTimeout(timer);
      running.delete(child);
      reject(e);
    });
    child.on('close', (code, signal) => {
      clearTimeout(timer);
      running.delete(child);
      if (code === 0) resolve();
      else reject(Object.assign(new Error(`${cmd} exited ${code ?? signal}: ${stderr}`), { code: 'engine-failed' }));
    });
  });
}

function killAll() {
  for (const c of running) c.kill('SIGKILL');
  running.clear();
}

module.exports = { run, killAll };
