#!/usr/bin/env node
// Golden Shots: a fixed, repeatable set of screenshots at iPhone sizes, so a visual
// change can be judged before/after from the same camera spots.
//
//   node tools/shots.js [outdir] [name...]    capture the named shots (all by default), landscape
//   node tools/shots.js --portrait [...]      capture portrait instead (the game is played landscape-only;
//                                              portrait shows the game's own framing, not what players see)
//   node tools/shots.js --list                print the shot names
//   node tools/shots.js --regions [outdir]    one landscape shot per land region the seven shots do not
//                                              cover (forest, marsh, quarry, ruins, ashlands), at fixed spots
//                                              with the default follow camera (written as r<n>-<region>-landscape.png)
//
// Uses the current build (run `python3 tools/build.py` first). Serves the repo like
// smoke.js, loads the game once per shot and orientation (the game picks its 3D render
// scale from the window size at start, so each size needs its own load), and passes
// `--golden=<slug>` to the game, which fixes time of day, weather, hero and camera
// and prints "GOLDEN ready <slug>" when the picture is settled (see overworld_bot.gd,
// duel_bot.gd). Each client is a fresh browser profile (empty save) and points at a dead
// relay, so nothing reaches the public shared world.
//
// Writes <nn>-<slug>-landscape.png (or -portrait.png with --portrait) and index.html (a contact
// sheet) into outdir, which must be outside the repo. Exit 1 if any shot fails or the
// page logs a script error. Options: --scale=N (device scale factor, default 2),
// --timeout=SECONDS (per shot, default 300).
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SHOTS = [
  ['road-wide', 'hero on the road, wide view, daylight'],
  ['tower-hall', 'inside the tower, hall and corridor, torch light'],
  ['duel-mid', 'duel, hero vs enemy, enemy attack in progress (HUD hidden)'],
  ['hero-close', 'hero close-up, gear'],
  ['terrain-graze', 'terrain at a grazing camera angle'],
  ['wall-close', 'close-up of a house wall'],
  ['duel-hud', 'the HUD during a fight'],
].map(([slug, about], i) => ({ slug, about, id: `${String(i + 1).padStart(2, '0')}-${slug}` }));
const ALL_ORIENTATIONS = [['portrait', 390, 844], ['landscape', 844, 390]];

let scale = 2;
let timeout = 300;
let list = false;
let portrait = false;
let regions = false;
const pos = [];
for (const a of process.argv.slice(2)) {
  if (a === '--list') list = true;
  else if (a === '--portrait') portrait = true;
  else if (a === '--regions') regions = true;
  else if (a.startsWith('--scale=')) scale = Number(a.slice(8));
  else if (a.startsWith('--timeout=')) timeout = Number(a.slice(10));
  else if (a.startsWith('-')) { console.error(`unknown option ${a}`); process.exit(2); }
  else pos.push(a);
}
// Region shots: `--shot=x --shot-when=pvp --at=X,Z` puts a fresh-save hero at a spot, by day, with no
// movement; "pvp" makes the game wait instead of saving its own picture. Ready = terrain chunk count stable.
const REGIONS = [
  ['forest', -120, 20], ['marsh', -60, 120], ['quarry', 150, -20], ['ruins', 150, -170], ['ashlands', 0, -165],
].map(([slug, x, z], i) => ({ slug, x, z, id: `r${i + 1}-${slug}` }));
const ORIENTATIONS = ALL_ORIENTATIONS.filter(([o]) => o === (portrait ? 'portrait' : 'landscape'));
if (list) {
  for (const s of SHOTS) console.log(`${s.id}  ${s.about}`);
  process.exit(0);
}
const find = (n) => SHOTS.find((s) => s.slug === n || s.id === n || String(Number(n)).padStart(2, '0') === s.id.slice(0, 2) && /^\d+$/.test(n));
let outdir = path.join(os.tmpdir(), 'ashgrave-shots');
if (pos.length && !find(pos[0])) outdir = path.resolve(pos.shift());
const chosen = regions ? [] : pos.length ? pos.map((n) => find(n) || (console.error(`unknown shot ${n}`), process.exit(2))) : SHOTS;
if (outdir === ROOT || outdir.startsWith(ROOT + path.sep)) {
  console.error('outdir must be outside the repo');
  process.exit(2);
}
fs.mkdirSync(outdir, { recursive: true });

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };
// Each `arg=` query parameter on index.html becomes one game user arg in GODOT_CONFIG.
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  let rel = decodeURIComponent(url.pathname);
  if (rel === '/') rel = '/index.html';
  const file = path.join(ROOT, path.normalize(rel));
  if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404).end();
    return;
  }
  const type = TYPES[path.extname(file)] || 'application/octet-stream';
  if (path.basename(file) === 'index.html') {
    const args = url.searchParams.getAll('arg');
    let html = fs.readFileSync(file, 'utf8');
    if (args.length) {
      if (!html.includes('"args":[]')) {
        res.writeHead(500).end('index.html no longer has "args":[] in GODOT_CONFIG; update tools/shots.js');
        return;
      }
      html = html.replace('"args":[]', `"args":${JSON.stringify(['--', ...args])}`);
    }
    res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' }).end(html);
    return;
  }
  res.writeHead(200, { 'Content-Type': type });
  fs.createReadStream(file).pipe(res);
});

async function captureRegion(browser, base, r) {
  const errors = [];
  const ctx = await browser.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: scale });
  const page = await ctx.newPage();
  const counts = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    const text = m.text();
    const c = /^PERFLOG .*chunks=(\d+)/.exec(text);
    if (c) counts.push(Number(c[1]));
    if (text.startsWith('WebSocket connection to')) return;
    if (m.type() === 'error' || /SCRIPT ERROR|Parse Error/.test(text)) errors.push(text);
  });
  const t0 = Date.now();
  const args = [`--shot=/tmp/none.png`, '--shot-when=pvp', `--at=${r.x},${r.z}`, '--perflog'];
  await page.goto(`${base}/index.html?relay=ws://127.0.0.1:9&${args.map((a) => 'arg=' + encodeURIComponent(a)).join('&')}`);
  let ok = false;
  while ((Date.now() - t0) / 1000 < timeout) {
    await page.waitForTimeout(3000);
    const n = counts.length;
    if (n >= 3 && counts[n - 1] > 0 && counts[n - 1] === counts[n - 2] && counts[n - 2] === counts[n - 3]) { ok = true; break; }
  }
  const file = `${r.id}-landscape.png`;
  if (ok) {
    await page.waitForTimeout(2000);
    await page.screenshot({ path: path.join(outdir, file) });
  }
  await ctx.close();
  console.log(`${ok && !errors.length ? 'ok  ' : 'FAIL'} ${file} (${((Date.now() - t0) / 1000).toFixed(0)}s)${errors.length ? '\n  ' + errors.map((e) => e.slice(0, 300)).join('\n  ') : ''}`);
  return ok && !errors.length;
}

async function capture(browser, base, shot, [orient, w, h]) {
  const errors = [];
  const ctx = await browser.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: scale });
  const page = await ctx.newPage();
  let ready = null;
  const readyP = new Promise((r) => { ready = r; });
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    const text = m.text();
    if (text.startsWith(`GOLDEN ready`)) ready(true);
    if (text.startsWith('GOLDEN unknown')) errors.push(text);
    // The dead relay is expected to refuse connections.
    if (text.startsWith('WebSocket connection to')) return;
    if (m.type() === 'error' || /SCRIPT ERROR|Parse Error/.test(text)) errors.push(text);
  });
  const t0 = Date.now();
  const q = `relay=ws://127.0.0.1:9&arg=${encodeURIComponent('--golden=' + shot.slug)}`;
  await page.goto(`${base}/index.html?${q}`);
  // The page covers a portrait screen with "Turn your phone sideways to play". Hide that so the
  // portrait shot shows the game's own portrait framing (not what a player sees on a phone).
  await page.addStyleTag({ content: '#rotate{display:none !important}' });
  const ok = await Promise.race([readyP, new Promise((r) => setTimeout(() => r(false), timeout * 1000))]);
  const file = `${shot.id}-${orient}.png`;
  if (ok) {
    await page.waitForTimeout(1500);
    await page.screenshot({ path: path.join(outdir, file) });
  }
  await ctx.close();
  const secs = ((Date.now() - t0) / 1000).toFixed(0);
  const problems = (ok ? [] : ['timed out before the game said it was ready']).concat(errors.map((e) => e.slice(0, 300)));
  console.log(`${problems.length ? 'FAIL' : 'ok  '} ${file} (${secs}s)${problems.length ? '\n  ' + problems.join('\n  ') : ''}`);
  return problems.length === 0;
}

function sheet(done) {
  const cells = chosen.map((s) => {
    const imgs = ORIENTATIONS.map(([o]) => {
      const f = `${s.id}-${o}.png`;
      return fs.existsSync(path.join(outdir, f)) && done.has(f) ? `<a href="${f}"><img src="${f}" class="${o}"></a>` : `<div class="missing ${o}">${f} missing</div>`;
    }).join('');
    return `<section><h2>${s.id}</h2><p>${s.about}</p><div class="pair">${imgs}</div></section>`;
  }).join('\n');
  fs.writeFileSync(path.join(outdir, 'index.html'), `<!DOCTYPE html>
<meta charset="utf-8"><title>Ashgrave golden shots</title>
<style>
body{background:#181818;color:#ddd;font:14px sans-serif;margin:16px}
h2{margin:0;font-size:16px}p{margin:2px 0 8px;color:#999}
section{margin-bottom:28px}.pair{display:flex;gap:12px;align-items:flex-start}
img.portrait{height:560px}img.landscape{height:260px}
.missing{border:1px dashed #a44;color:#a44;padding:20px}
</style>
<h1>Ashgrave golden shots</h1>
${cells}
`);
}

server.listen(0, '127.0.0.1', async () => {
  const { chromium } = require('playwright');
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({
    args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
  });
  const t0 = Date.now();
  const done = new Set();
  let failed = 0;
  if (regions) {
    for (const r of REGIONS) {
      let ok = false;
      try { ok = await captureRegion(browser, base, r); } catch (e) { console.log(`FAIL ${r.id}: ${e.message}`); }
      if (!ok) failed++;
    }
  }
  for (const shot of chosen) {
    for (const o of ORIENTATIONS) {
      let ok = false;
      try { ok = await capture(browser, base, shot, o); } catch (e) { console.log(`FAIL ${shot.id}-${o[0]}: ${e.message}`); }
      if (ok) done.add(`${shot.id}-${o[0]}.png`); else failed++;
    }
  }
  await browser.close();
  server.close();
  if (!regions) sheet(done);
  console.log(`${failed ? failed + ' failed' : 'all ok'}, ${((Date.now() - t0) / 1000).toFixed(0)}s total, contact sheet ${path.join(outdir, 'index.html')}`);
  process.exit(failed ? 1 : 0);
});
