#!/usr/bin/env node
// Texture look-test captures (lane G2, docs/TEXTURE_LOOK.md). Loads the build once per treatment with
// `--looktest=tex --treatment=T --ltmem`, takes a picture of every fixed camera (the page advances to the next
// camera when window.__lt_next is set), then writes a side-by-side sheet per camera (flat | grain | source).
//
//   node tools/tex_shots.js [--out=DIR] [--treatments=flat,grain,source] [--cams=v1,v2-trail] [--single] [--scale=2] [--timeout=SECONDS]
//
// Output: DIR/<treatment>/NN-name.png, DIR/<treatment>/mem.txt (the game's memory lines), DIR/compare/NN-name.png.
// --cams (substrings of camera ids) takes only those cameras, in one page load; --single loads one page per camera.
// Default DIR /home/claude/screens/g2, 844x390 CSS pixels, device scale 2 (use --scale=3 for the phone-shaped
// memory measurement: the game page caps the ratio at 2 itself, see docs/PERF_BUDGET.md). Needs `python3 tools/build.py`
// first and Playwright with Chromium (as tools/shots.js). Each client points at a dead relay.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
let out = '/home/claude/screens/g2';
let treatments = ['flat', 'grain', 'source'];
let cams = [];
let scale = 2;
let timeout = 300;
let single = false;
for (const a of process.argv.slice(2)) {
  if (a.startsWith('--out=')) out = a.slice(6);
  else if (a.startsWith('--treatments=')) treatments = a.slice(13).split(',');
  else if (a.startsWith('--cams=')) cams = a.slice(7).split(',');
  else if (a.startsWith('--scale=')) scale = Number(a.slice(8));
  else if (a === '--single') single = true;
  else if (a.startsWith('--timeout=')) timeout = Number(a.slice(10));
  else { console.error(`unknown option ${a}`); process.exit(2); }
}
if (out === ROOT || out.startsWith(ROOT + path.sep)) { console.error('out must be outside the repo'); process.exit(2); }
// Camera names in order (keep in step with _define_cams in tex_looktest.gd).
const CAMS = ['v1-grass', 'v2-trail-mud', 'v3-water-edge', 'v4-tree-cards', 'v4b-tree-nocards', 'v5a-wall-square', 'v5b-wall-30deg',
  'v5c-wood-wall', 'v6a-duel-plain', 'v6b-duel-armour', 'v6z-duel-empty', 'v7-banner', 'w1-hearthvale', 'w2-greywood', 'w3-ashlands']
  .map((n, i) => `${String(i + 1).padStart(2, '0')}-${n}`);

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

async function run(browser, base, treatment, only, seq) {
  const dir = path.join(out, treatment);
  fs.mkdirSync(dir, { recursive: true });
  const ctx = await browser.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: scale });
  const page = await ctx.newPage();
  const errors = [];
  const memLines = [];
  let settled = null;
  let wake = null;
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    const t = m.text();
    if (t.startsWith('LOOKTEST cam ')) { settled = t.split(' ')[2]; if (wake) wake(); }
    if (t.startsWith('LOOKTEST mem')) memLines.push(t);
    if (t.startsWith('WebSocket connection to') || t.includes('GPU stall')) return;
    if (m.type() === 'error' || /SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:/.test(t)) errors.push(t.slice(0, 400));
  });
  const todo = only ? [only] : (Array.isArray(seq) ? seq : CAMS);
  const args = ['--looktest=tex', `--treatment=${treatment}`, '--ltmem'].concat(only ? [`--ltcam=${only}`] : [`--ltstart=${todo[0]}`]);
  await page.goto(`${base}/index.html?relay=ws://127.0.0.1:9&${args.map((a) => 'arg=' + encodeURIComponent(a)).join('&')}`);
  const done = [];
  for (let i = 0; i < todo.length; i++) {
    const want = todo[i];
    const t0 = Date.now();
    while (settled !== want && (Date.now() - t0) / 1000 < timeout) await new Promise((r) => { wake = r; setTimeout(r, 1000); });
    if (settled !== want) { errors.push(`timed out waiting for ${want}`); break; }
    await page.waitForTimeout(1200);
    await page.screenshot({ path: path.join(dir, `${want}.png`), timeout: 180000 });
    done.push(want);
    if (!only) await page.evaluate((n) => { window.__lt_next = n; }, i + 1 < todo.length ? CAMS.indexOf(todo[i + 1]) : 99);
  }
  fs.appendFileSync(path.join(dir, 'mem.txt'), memLines.map((l) => l.slice(l.indexOf('mem'))).join('\n') + '\n');
  await ctx.close();
  return { done, errors };
}

server.listen(0, '127.0.0.1', async () => {
  const { chromium } = require('playwright');
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  let failed = 0;
  const wanted = cams.length ? CAMS.filter((c) => cams.some((w) => c.includes(w))) : [];
  for (const t of treatments) {
    fs.rmSync(path.join(out, t, 'mem.txt'), { force: true });
    const jobs = single && wanted.length ? wanted : [null];
    for (const only of jobs) {
      const t0 = Date.now();
      let r;
      for (let attempt = 0; attempt < 2; attempt++) {
        try { r = await run(browser, base, t, only, wanted.length ? wanted : null); } catch (e) { r = { done: [], errors: [e.message] }; }
        if (!r.errors.some((e) => e.startsWith('timed out'))) break;
      }
      const bad = r.errors.filter((e) => !e.startsWith('timed out') || true);
      console.log(`${bad.length ? 'FAIL' : 'ok  '} ${t}${only ? ' ' + only : ''}: ${r.done.length} shots (${((Date.now() - t0) / 1000).toFixed(0)}s)${bad.length ? '\n  ' + bad.join('\n  ') : ''}`);
      if (bad.length) failed++;
    }
  }
  await browser.close();
  server.close();
  // Side-by-side sheets: flat | grain | source for every camera that exists in all treatments asked for.
  const py = `
import sys, os
from PIL import Image, ImageDraw
out, ts = sys.argv[1], sys.argv[2].split(',')
os.makedirs(os.path.join(out, 'compare'), exist_ok=True)
names = sorted(set.intersection(*[set(f for f in os.listdir(os.path.join(out, t)) if f.endswith('.png')) for t in ts if os.path.isdir(os.path.join(out, t))]))
for n in names:
    ims = [Image.open(os.path.join(out, t, n)).convert('RGB') for t in ts]
    w, h = ims[0].size
    sheet = Image.new('RGB', (w * len(ims), h + 28), (20, 20, 20))
    d = ImageDraw.Draw(sheet)
    for i, im in enumerate(ims):
        sheet.paste(im, (i * w, 28))
        d.text((i * w + 8, 8), ts[i].upper(), fill=(230, 230, 230))
    sheet.save(os.path.join(out, 'compare', n))
print('sheets:', len(names))
`;
  try { console.log(execFileSync('python3', ['-c', py, out, treatments.join(',')]).toString().trim()); } catch (e) { console.log('sheets failed: ' + e.message); }
  process.exit(failed ? 1 : 0);
});
