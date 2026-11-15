#!/usr/bin/env node
// RigVisual look-test captures and cost runs (docs/RIG_PLAN.md R1, docs/RIG_R1.md). Needs a
// `python3 tools/build.py --looktest` pack (the release pack leaves the rig out) and Playwright with Chromium.
//
//   node tools/rig_shots.js [--out=DIR] [--scale=2]       shots: one page with `--looktest=rig-shots`, one picture per
//                                                         pose (knight and skeleton warrior, front and three-quarter),
//                                                         then the knight alone and the empty ground for tools/g3_measure.py
//   node tools/rig_shots.js --perf=0,1,6,18 [--ph]        cost: one page per count with `--looktest=rig-perf=N`
//                                                         (--ph adds `ph-perf=N` PlaceholderVisual runs); prints the lines
//
// Default DIR /home/claude/screens/r1 (outside the repo): DIR/NN-pose.png, DIR/after/lum-knight.png and
// DIR/after/measure/lum-knight_empty.png (run `python3 tools/g3_measure.py DIR after`), DIR/perf.txt.
// One browser at a time; each page points at a dead relay.
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
let out = '/home/claude/screens/r1';
let scale = 2;
let perf = null;
let ph = false;
for (const a of process.argv.slice(2)) {
  if (a.startsWith('--out=')) out = a.slice(6);
  else if (a.startsWith('--scale=')) scale = Number(a.slice(8));
  else if (a.startsWith('--perf=')) perf = a.slice(7).split(',').map(Number);
  else if (a === '--ph') ph = true;
  else { console.error(`unknown option ${a}`); process.exit(2); }
}
if (out === ROOT || out.startsWith(ROOT + path.sep)) { console.error('out must be outside the repo'); process.exit(2); }
// Keep in step with SHOTS in rig_looktest.gd.
const SHOTS = ['idle', 'slash', 'windup-over', 'parry', 'stagger', 'death', 'walk', 'lum-knight', 'lum-knight_empty'];

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

async function open(browser, base, args, onLine) {
  const ctx = await browser.newContext({ viewport: { width: 844, height: 390 }, deviceScaleFactor: scale });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    const t = m.text();
    onLine(t);
    if (t.startsWith('WebSocket connection to') || t.includes('GPU stall')) return;
    if (m.type() === 'error' || /SCRIPT ERROR|Parse Error|SHADER ERROR|ERROR:/.test(t)) errors.push(t.slice(0, 400));
  });
  await page.goto(`${base}/index.html?relay=ws://127.0.0.1:9&${args.map((a) => 'arg=' + encodeURIComponent(a)).join('&')}`);
  return { ctx, page, errors };
}

const waitFor = async (test, secs) => { const t0 = Date.now(); while (!test() && (Date.now() - t0) / 1000 < secs) await new Promise((r) => setTimeout(r, 500)); return test(); };

async function shots(browser, base) {
  fs.mkdirSync(path.join(out, 'after', 'measure'), { recursive: true });
  let settled = null;
  const lines = [];
  const { ctx, page, errors } = await open(browser, base, ['--looktest=rig-shots'], (t) => {
    if (t.startsWith('LOOKTEST')) lines.push(t);
    if (t.startsWith('LOOKTEST cam ')) settled = t.split(' ')[2];
  });
  for (let i = 0; i < SHOTS.length; i++) {
    if (!(await waitFor(() => settled === SHOTS[i], 300))) { errors.push(`timed out waiting for ${SHOTS[i]}`); break; }
    await page.waitForTimeout(1500);
    const name = SHOTS[i];
    const file = name === 'lum-knight' ? path.join(out, 'after', 'lum-knight.png')
      : name === 'lum-knight_empty' ? path.join(out, 'after', 'measure', 'lum-knight_empty.png')
        : path.join(out, `${String(i + 1).padStart(2, '0')}-${name}.png`);
    await page.screenshot({ path: file, timeout: 180000 });
    console.log(`shot ${file}`);
    await page.evaluate((n) => { window.__lt_next = n; }, i + 1);
  }
  await ctx.close();
  return errors;
}

async function perfRun(browser, base, kind, n) {
  let result = null;
  const { ctx, errors } = await open(browser, base, [`--looktest=${kind}=${n}`], (t) => { if (t.startsWith('LOOKTEST perf_result')) result = t; });
  await waitFor(() => result, 400);
  await ctx.close();
  if (!result) errors.push(`no perf_result for ${kind}=${n}`);
  return { result, errors };
}

server.listen(0, '127.0.0.1', async () => {
  const { chromium } = require('playwright');
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  let errors = [];
  if (perf) {
    const got = [];
    for (const n of perf) {
      for (const kind of ph ? ['rig-perf', 'ph-perf'] : ['rig-perf']) {
        const r = await perfRun(browser, base, kind, n);
        errors.push(...r.errors);
        if (r.result) { console.log(r.result); got.push(r.result); }
      }
    }
    fs.mkdirSync(out, { recursive: true });
    fs.appendFileSync(path.join(out, 'perf.txt'), got.join('\n') + '\n');
  } else {
    errors = await shots(browser, base);
  }
  await browser.close();
  server.close();
  if (errors.length) console.log('FAIL\n  ' + errors.join('\n  '));
  process.exit(errors.length ? 1 : 0);
});
