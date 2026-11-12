#!/usr/bin/env node
// Breadcrumb check: a tab killed without a clean exit is reported on the next launch,
// a normal reload is not.
//
//   node tools/crumb_test.js [screenshot-dir]
//
// Serves the build, plays the tour bot in the land, waits for crumbs, crashes the
// renderer (no pagehide), reopens in the same browser context (same localStorage) and
// expects a "[crumb] died:" console line. Then reloads normally and expects none.
// Screenshots of the banner go to the directory (default /tmp) at 390x844 and 844x390.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = path.resolve(__dirname, '..');
const OUT = process.argv[2] || '/tmp';
const GL = ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'];
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Like tools/check.js: each arg= query parameter becomes a game user arg in GODOT_CONFIG.
function serve() {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    let rel = decodeURIComponent(url.pathname);
    if (rel === '/') rel = '/index.html';
    const file = path.join(ROOT, path.normalize(rel));
    if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404).end(); return; }
    const type = TYPES[path.extname(file)] || 'application/octet-stream';
    if (path.basename(file) === 'index.html') {
      let html = fs.readFileSync(file, 'utf8');
      const args = url.searchParams.getAll('arg');
      if (args.length) html = html.replace('"args":[]', `"args":${JSON.stringify(['--', ...args])}`);
      res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' }).end(html);
      return;
    }
    res.writeHead(200, { 'Content-Type': type });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve({ server, base: `http://127.0.0.1:${server.address().port}` })));
}

const failures = [];
function check(ok, what) { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) failures.push(what); }

async function crumb(page) {
  try {
    const s = await page.evaluate(() => localStorage.getItem('ashgrave_crumb'));
    return s ? JSON.parse(s) : null;
  } catch (e) { return null; }
}

async function waitFor(fn, seconds) {
  const end = Date.now() + seconds * 1000;
  while (Date.now() < end) { const v = await fn(); if (v) return v; await sleep(500); }
  return null;
}

function open(ctx, base, viewport, extra = []) {
  return ctx.newPage().then(async (page) => {
    const lines = [];
    const errors = [];
    page.on('console', (m) => {
      const t = m.text();
      lines.push(t);
      if (/SCRIPT ERROR|Parse Error/.test(t)) errors.push(t.slice(0, 300));
    });
    page.on('pageerror', (e) => errors.push(String(e).slice(0, 300)));
    await page.setViewportSize(viewport);
    const q = new URLSearchParams({ relay: 'ws://127.0.0.1:1' });
    q.append('arg', '--autoplay=tour');
    for (const x of extra) q.append('arg', x);
    await page.goto(`${base}/index.html?${q}`);
    return { page, lines, errors };
  });
}

(async () => {
  const { server, base } = await serve();
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({ args: GL });
  const ctx = await browser.newContext({ deviceScaleFactor: 1 });
  try {
    // 1. First run: crumbs appear and show the land.
    const a = await open(ctx, base, { width: 844, height: 390 });
    const first = await waitFor(async () => { const c = await crumb(a.page); return c && c.mode === 'land' ? c : null; }, 120);
    check(!!first, 'crumb written with mode=land');
    const second = await waitFor(async () => { const c = await crumb(a.page); return c && first && c.ts > first.ts ? c : null; }, 40);
    check(!!second, 'a second crumb followed');
    if (second) {
      console.log('crumb:', JSON.stringify(second));
      check(second.live === true, 'crumb says live while running');
      check(second.heap > 0 && second.tex > 0 && second.oc > 0 && second.nc > 0, 'memory figures are non-zero (heap, textures, objects, nodes)');
      console.log(`MEMORY_STATIC reads ${second.ms} on web`);
      check(second.place && second.place.length > 0, `place name present (${second.place})`);
      console.log(`wasm heap bytes: ${second.heap}`);
    }
    check(!a.lines.some((l) => l.startsWith('[crumb] died:')), 'first run reports no death');

    // 2. Kill without pagehide: crash the renderer, keep the context.
    const cdp = await ctx.newCDPSession(a.page);
    let crashed = false;
    a.page.on('crash', () => { crashed = true; });
    cdp.send('Page.crash').catch(() => {}); // never answers: the renderer is gone
    await waitFor(async () => crashed, 20);
    check(crashed, 'renderer crashed (no pagehide)');
    // The dead page is left open: closing it fires nothing, but could hang.

    // 3. Relaunch: death reported, banner shown.
    // --crumbhold keeps the banner up (no auto-hide) so the slow headless run can be photographed.
    const b = await open(ctx, base, { width: 390, height: 844 }, ['--crumbhold']);
    await b.page.addStyleTag({ content: '#rotate{display:none !important}' });
    const died = await waitFor(async () => b.lines.find((l) => l.startsWith('[crumb] died:')), 120);
    check(!!died, 'relaunch prints [crumb] died:');
    if (died) {
      console.log(died);
      const num = (k) => Number((new RegExp(`${k}=(\\d+)`).exec(died) || [0, 0])[1]);
      check(/mode=land/.test(died), 'died line says mode=land');
      check(/place=\S+/.test(died), 'died line has a place');
      check(num('heap_mb') > 0, 'died line has non-zero wasm heap');
      check(num('objects') > 0, 'died line has non-zero object count');
    }
    await sleep(2500);
    // (The page covers a portrait canvas with a "turn your phone sideways" note; hidden above to see the banner itself.)
    await sleep(1500);
    await b.page.screenshot({ path: path.join(OUT, 'crumb-portrait.png') });
    await b.page.setViewportSize({ width: 844, height: 390 });
    await sleep(2500);
    await b.page.screenshot({ path: path.join(OUT, 'crumb-landscape.png') });
    const log = await b.page.evaluate(() => JSON.parse(localStorage.getItem('ashgrave_crumb_log') || '[]'));
    check(log.length === 1, `death log has one entry (${log.length})`);

    // 4. Clean exit: wait until this run is writing crumbs, then reload normally.
    await waitFor(async () => { const c = await crumb(b.page); return c && c.live === true && c.mode !== 'boot'; }, 90);
    await b.page.reload();
    const c = { page: b.page, lines: [] };
    b.page.on('console', (m) => c.lines.push(m.text()));
    const rebooted = await waitFor(async () => { const k = await crumb(b.page); return k && k.live === true && k.t < 20; }, 120);
    await sleep(3000);
    check(!!rebooted, 'page came back after reload');
    check(!c.lines.some((l) => l.startsWith('[crumb] died:')), 'normal reload reports no death');
    const log2 = await b.page.evaluate(() => JSON.parse(localStorage.getItem('ashgrave_crumb_log') || '[]'));
    check(log2.length === 1, 'death log unchanged after a normal reload');

    // 5. Hidden tab is a clean exit too.
    const hiddenFlag = await b.page.evaluate(() => {
      Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' });
      document.dispatchEvent(new Event('visibilitychange'));
      return JSON.parse(localStorage.getItem('ashgrave_crumb')).live;
    });
    check(hiddenFlag === false, 'visibilitychange to hidden clears live');
    const errors = [...a.errors, ...b.errors];
    check(errors.length === 0, `no script errors${errors.length ? ': ' + errors[0] : ''}`);
  } catch (e) {
    check(false, 'test threw: ' + e);
  }
  await browser.close().catch(() => {});
  server.close();
  console.log(failures.length ? `FAILED (${failures.length})` : 'crumb test passed');
  process.exit(failures.length ? 1 : 0);
})();
