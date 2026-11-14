#!/usr/bin/env node
// Textured ground and water, real game (lane G3, docs/TEXTURE_LOOK.md): before / after pictures and the fighter-to-ground pairs.
//
//   node tools/g3_shots.js [--out=DIR] [--modes=before,after] [--only=name,name] [--quality=safe|full] [--mem] [--scale=2] [--timeout=SECONDS]
//
// before = flat (`--flatground`: Full quality otherwise, textures held off), after = the build as it is. Names: the land views
// (g3-hearthvale, g3-greywood, g3-ashlands, g3-water, g3-trail, g3-trail-ash: debug golden shots in overworld_bot.gd) and the real duels
// (duel-hearthvale, duel-greywood, duel-ashlands, duel-mud, duel-trail: `--g3duel` in overworld_bot.gd). Each duel also writes
// <name>_empty.png, the same frame with both fighters hidden (duel_bot.gd), into DIR/<mode>/measure/ (for tools/g3_measure.py).
// --mem also prints the last PERFLOG line of each page (texture and video memory). DIR must be outside the repo (default
// /home/claude/screens/g3). Needs `python3 tools/build.py` first and Playwright with Chromium, as tools/shots.js.
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
let out = '/home/claude/screens/g3';
let modes = ['before', 'after'];
let only = [];
let quality = '';
let mem = false;
let scale = 2;
let timeout = 300;
for (const a of process.argv.slice(2)) {
  if (a.startsWith('--out=')) out = a.slice(6);
  else if (a.startsWith('--modes=')) modes = a.slice(8).split(',');
  else if (a.startsWith('--only=')) only = a.slice(7).split(',');
  else if (a.startsWith('--quality=')) quality = a.slice(10);
  else if (a === '--mem') mem = true;
  else if (a.startsWith('--scale=')) scale = Number(a.slice(8));
  else if (a.startsWith('--timeout=')) timeout = Number(a.slice(10));
  else { console.error(`unknown option ${a}`); process.exit(2); }
}
if (out === ROOT || out.startsWith(ROOT + path.sep)) { console.error('out must be outside the repo'); process.exit(2); }

// yaw: forward is (sin, cos), so PI faces north (-z).
const JOBS = [
  { name: 'g3-hearthvale', golden: 'g3-hearthvale' }, { name: 'g3-greywood', golden: 'g3-greywood' },
  { name: 'g3-ashlands', golden: 'g3-ashlands' }, { name: 'g3-water', golden: 'g3-water' },
  { name: 'g3-trail', golden: 'g3-trail' }, { name: 'g3-trail-ash', golden: 'g3-trail-ash' },
  { name: 'duel-hearthvale', at: [10, 58], yaw: Math.PI }, { name: 'duel-greywood', at: [-120, 20], yaw: 0 },
  { name: 'duel-ashlands', at: [30, -165], yaw: Math.PI * 0.5 }, { name: 'duel-mud', at: [86.5, 40], yaw: 0 },
  { name: 'duel-trail', at: [0, -50], yaw: Math.PI },
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
  if (mode === 'before') args.push('--flatground');
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
