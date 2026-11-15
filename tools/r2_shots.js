#!/usr/bin/env node
// Stage R2 pictures (docs/RIG_R2.md): the rigged hero in the real game, from the debug golden shots r2-* in overworld_bot.gd.
// Needs a `python3 tools/build.py --looktest` pack (the release pack holds no rig) and Playwright with Chromium.
//
//   node tools/r2_shots.js [--out=DIR] [--only=name,name] [--scale=2]
//
// One page per picture, one at a time. Names: stand walk run sprint gather head tower, w-<weapon>, s-<shield>, h-<helm>,
// a-<armour> (items from items.gd), prim-stand (no --rig, for comparison) and lum / lum_empty (stand with the hero hidden,
// for tools/g3_measure.py: written to DIR/after/stand.png and DIR/after/measure/stand_empty.png). DIR default
// /home/claude/screens/r2, outside the repo.
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
let out = '/home/claude/screens/r2';
let only = [];
let scale = 2;
for (const a of process.argv.slice(2)) {
  if (a.startsWith('--out=')) out = a.slice(6);
  else if (a.startsWith('--only=')) only = a.slice(7).split(',');
  else if (a.startsWith('--scale=')) scale = Number(a.slice(8));
  else { console.error(`unknown option ${a}`); process.exit(2); }
}
if (out === ROOT || out.startsWith(ROOT + path.sep)) { console.error('out must be outside the repo'); process.exit(2); }

const G = (golden, equip, extra = []) => ({ golden, equip, extra });
const JOBS = {
  stand: G('r2-stand'), walk: G('r2-walk'), run: G('r2-run'), sprint: G('r2-sprint'), gather: G('r2-gather'), head: G('r2-head'),
  tower: G('tower-hall'),
  'w-longsword': G('r2-gear', 'iron_longsword'), 'w-twin': G('r2-gear', 'twin_fangs'), 'w-great': G('r2-gear', 'pyre_greatsword'),
  'w-brand': G('r2-gear', 'wardens_brand'), 'w-frost': G('r2-gear', 'frostbite_pair'),
  's-heater': G('r2-gear', 'heater'), 's-buckler': G('r2-gear', 'buckler'), 's-tower': G('r2-gear', 'tower_shield'),
  'h-sallet': G('r2-head', 'plain_sallet'), 'h-great': G('r2-head', 'watchers_helm'), 'h-hood': G('r2-head', 'duelists_hood'),
  'a-warden': G('r2-gear', 'wardens_plate,watchers_helm,tower_shield,pyre_greatsword'), 'a-leather': G('r2-gear', 'duelists_leathers,duelists_hood,buckler,twin_fangs'),
  'a-ranged': G('r2-gear', 'hunters_bow'), 'a-knives': G('r2-gear', 'throwing_knives'), 'a-spell': G('r2-gear', 'ember_bolt'),
  'prim-stand': G('r2-stand', '', ['no-rig']), 'prim-head': G('r2-head', '', ['no-rig']), 'head-dark': G('r2-head', '', ['dark']),
  lum: G('r2-stand'), lum_empty: G('r2-stand', '', ['hide']),
};
const names = (only.length ? only : Object.keys(JOBS)).filter((n) => JOBS[n]);

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

async function main() {
  const { chromium } = require('playwright');
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  fs.mkdirSync(path.join(out, 'after', 'measure'), { recursive: true });
  let bad = 0;
  for (const name of names) {
    const job = JOBS[name];
    const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
    const page = await (await browser.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: scale })).newPage();
    const errors = [];
    let ready;
    const readyP = new Promise((r) => { ready = r; });
    page.on('pageerror', (e) => errors.push(String(e)));
    page.on('console', (m) => {
      const t = m.text();
      if (t.startsWith('GOLDEN ready')) ready(true);
      if (/hero=(rig|primitive)/.test(t) && /^(LAND|WORLD)/.test(t)) console.log(`  ${t}`);
      if (t.startsWith('WebSocket connection to')) return;
      if (m.type() === 'error' || /SCRIPT ERROR|Parse Error/.test(t)) errors.push(t.slice(0, 300));
    });
    const args = ['--golden=' + job.golden];
    if (job.equip) args.push('--goldequip=' + job.equip);
    if (!job.extra.includes('no-rig')) args.push('--rig');
    if (job.extra.includes('hide')) args.push('--goldhide');
    if (job.extra.includes('dark')) args.push('--faceshade=0.12');
    await page.goto(`${base}/index.html?relay=ws://127.0.0.1:9&${args.map((a) => 'arg=' + encodeURIComponent(a)).join('&')}`);
    const ok = await Promise.race([readyP, new Promise((r) => setTimeout(() => r(false), 240000))]);
    if (ok) {
      await page.waitForTimeout(2500);
      const file = name === 'lum' ? path.join(out, 'after', 'stand.png') : name === 'lum_empty' ? path.join(out, 'after', 'measure', 'stand_empty.png') : path.join(out, name + '.png');
      await page.screenshot({ path: file });
    }
    await browser.close();
    console.log(`${ok && !errors.length ? 'ok  ' : 'FAIL'} ${name}${errors.length ? '\n  ' + errors.slice(0, 3).join('\n  ') : ''}`);
    if (!ok || errors.length) bad++;
  }
  server.close();
  process.exit(bad ? 1 : 0);
}
main();
