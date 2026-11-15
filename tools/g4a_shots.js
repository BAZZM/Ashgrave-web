#!/usr/bin/env node
// Textured trees, real game (lane G4a, docs/TEXTURE_LOOK.md): before / after pictures. Derived from tools/g3_shots.js.
//
//   node tools/g4a_shots.js [--out=DIR] [--modes=before,after] [--only=name,name] [--extra=--cards,...] [--quality=safe|full] [--mem] [--scale=2] [--timeout=SECONDS]
//
// before = Build 19's look (`--flattrees`: trees flat, ground and water textured), after = the build as it is. Names: hearthvale, greywood,
// conifer, close, close-pine (golden shots in overworld_bot.gd: g4a-*, g3-greywood) and duel-greywood (`--g3duel`). A duel also writes
// <name>_empty.png (both fighters hidden) into DIR/<mode>/measure/. --mem prints the last PERFLOG line of each page and appends it to
// DIR/<mode>/mem.txt. DIR must be outside the repo (default /home/claude/screens/g4a). Needs `python3 tools/build.py` first and Playwright with Chromium.
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
let out = '/home/claude/screens/g4a';
let modes = ['before', 'after'];
let only = [];
let quality = '';
let mem = false;
const extra = [];
let scale = 2;
let timeout = 300;
for (const a of process.argv.slice(2)) {
  if (a.startsWith('--out=')) out = a.slice(6);
  else if (a.startsWith('--modes=')) modes = a.slice(8).split(',');
  else if (a.startsWith('--only=')) only = a.slice(7).split(',');
  else if (a.startsWith('--quality=')) quality = a.slice(10);
  else if (a === '--mem') mem = true;
  else if (a.startsWith('--extra=')) extra.push(...a.slice(8).split(','));
  else if (a.startsWith('--scale=')) scale = Number(a.slice(8));
  else if (a.startsWith('--timeout=')) timeout = Number(a.slice(10));
  else { console.error(`unknown option ${a}`); process.exit(2); }
}
if (out === ROOT || out.startsWith(ROOT + path.sep)) { console.error('out must be outside the repo'); process.exit(2); }

// yaw: forward is (sin, cos), so PI faces north (-z).
const JOBS = [
  { name: 'hearthvale', golden: 'g4a-hearthvale' }, { name: 'greywood', golden: 'g3-greywood' },
  { name: 'conifer', golden: 'g4a-conifer' }, { name: 'close', golden: 'g4a-close' }, { name: 'close-pine', golden: 'g4a-close-pine' },
  { name: 'node', golden: 'g4a-node' }, { name: 'node-pine', golden: 'g4a-node-pine' },
  { name: 'duel-greywood', at: [-120, 20], yaw: 0 },
].filter((j) => !only.length || only.includes(j.name));

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  let rel = decodeURIComponent(url.pathname);
  if (rel === '/') rel = '/index.html';
  const file = path.join(ROOT, path.normalize(rel));
  if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404).end(); return; }
  const type = TYPES[path.extname(file)] || 'application/octet-stream';
  if (path.basename(file) === 'index.html') {
    const args = url.searchParams.getAll('arg');
    let html = fs.readFileSync(file, 'utf8');
    if (args.length) html = html.replace('"args":[]', `"args":${JSON.stringify(['--', ...args])}`);
    res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' }).end(html);
    return;
  }
  res.writeHead(200, { 'Content-Type': type });
  fs.createReadStream(file).pipe(res);
});

async function capture(browser, base, job, mode) {
  const dir = path.join(out, mode);
  fs.mkdirSync(path.join(dir, 'measure'), { recursive: true });
  const ctx = await browser.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: scale });
  const page = await ctx.newPage();
  const errors = [];
  let perf = '';
  const waiters = {};
  const seen = {};
  const say = (k) => { seen[k] = true; if (waiters[k]) waiters[k](); };
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    const t = m.text();
    if (t.startsWith('GOLDEN ready')) say('golden');
    if (t.startsWith('G3SHOT full')) say('full');
    if (t.startsWith('G3SHOT empty')) say('empty');
    if (t.startsWith('PERFLOG')) perf = t;
    if (t.startsWith('WebSocket connection to') || t.includes('GPU stall')) return;
    if (m.type() === 'error' || /SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:/.test(t)) errors.push(t.slice(0, 300));
  });
  const wait = async (k) => {
    const t0 = Date.now();
    while (!seen[k] && (Date.now() - t0) / 1000 < timeout) await new Promise((r) => { waiters[k] = r; setTimeout(r, 1000); });
    return !!seen[k];
  };
  const args = [];
  if (job.golden) args.push(`--golden=${job.golden}`);
  else args.push(`--at=${job.at[0]},${job.at[1]}`, `--g3duel=${job.yaw}`, '--g3empty', '--shot=/tmp/none.png', '--shot-when=pvp');
  if (mode === 'before') args.push('--flattrees');
  args.push(...extra);
  if (mem) args.push('--perflog');
  const t0 = Date.now();
  await page.goto(`${base}/index.html?relay=ws://127.0.0.1:9${quality ? '&quality=' + quality : ''}&${args.map((a) => 'arg=' + encodeURIComponent(a)).join('&')}`);
  let ok = false;
  if (job.golden) {
    if (await wait('golden')) {
      await page.waitForTimeout(1500);
      await page.screenshot({ path: path.join(dir, `${job.name}.png`), timeout: 180000 });
      ok = true;
    }
  } else if (await wait('full')) {
    await page.waitForTimeout(500);
    await page.screenshot({ path: path.join(dir, `${job.name}.png`), timeout: 180000 });
    await page.evaluate(() => { window.__g3_hide = true; });
    if (await wait('empty')) {
      await page.waitForTimeout(500);
      await page.screenshot({ path: path.join(dir, 'measure', `${job.name}_empty.png`), timeout: 180000 });
      ok = true;
    }
  }
  if (mem && perf) fs.appendFileSync(path.join(dir, 'mem.txt'), `${job.name} ${quality || 'full'}: ${perf}\n`);
  await ctx.close();
  console.log(`${ok && !errors.length ? 'ok  ' : 'FAIL'} ${mode}/${job.name} (${((Date.now() - t0) / 1000).toFixed(0)}s)${mem && perf ? '\n  ' + perf : ''}${!ok ? '\n  timed out' : ''}${errors.length ? '\n  ' + errors.join('\n  ') : ''}`);
  return ok && !errors.length;
}

server.listen(0, '127.0.0.1', async () => {
  const { chromium } = require('playwright');
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  let failed = 0;
  for (const mode of modes) for (const job of JOBS) {
    let ok = false;
    try { ok = await capture(browser, base, job, mode); } catch (e) { console.log(`FAIL ${mode}/${job.name}: ${e.message}`); }
    if (!ok) failed++;
  }
  await browser.close();
  server.close();
  process.exit(failed ? 1 : 0);
});
