#!/usr/bin/env node
// Breadcrumb check: a tab killed without a clean exit is reported on the next launch,
// a normal reload is not. Also: a frozen engine, a death during boot, a hidden-tab
// discard, an old death (logged, no banner), and a second live tab (unreliable).
//
//   node tools/crumb_test.js [screenshot-dir]
//
// Serves the build, plays the tour bot in the land, waits for crumbs, crashes the
// renderer (no pagehide), reopens in the same browser context (same localStorage) and
// expects a "[crumb] died:" console line. Then reloads normally and expects none.
// Each later case primes or recreates its own crumb, and kills its pages (Page.crash, no pagehide) before the next.
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

const BLANK = '/_blank';

// opts.hang: never answer the engine download, so the page stays in its boot phase.
// opts.hidden: the page starts in a background tab.
async function openPage(ctx, base, viewport, extra = [], opts = {}) {
  const page = await ctx.newPage();
  const lines = [];
  const errors = [];
  page.on('console', (m) => {
    const t = m.text();
    lines.push(t);
    if (/SCRIPT ERROR|Parse Error/.test(t)) errors.push(t.slice(0, 300));
  });
  page.on('pageerror', (e) => errors.push(String(e).slice(0, 300)));
  if (opts.hang) await page.route('**/part2.wasm', () => {});
  if (opts.hidden) await page.addInitScript(() => { Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' }); });
  await page.setViewportSize(viewport);
  const q = new URLSearchParams({ relay: 'ws://127.0.0.1:1' });
  q.append('arg', '--autoplay=tour');
  for (const x of extra) q.append('arg', x);
  await page.goto(`${base}/index.html?${q}`);
  return { page, lines, errors };
}
const open = (ctx, base, viewport, extra = []) => openPage(ctx, base, viewport, extra);
const died = (p) => p.lines.find((l) => l.startsWith('[crumb] died:'));
const field = (line, k) => { const m = new RegExp(`${k}=(\\S+)`).exec(line || ''); return m ? m[1] : null; };

// Same-origin scratch page: set (or clear, with null) the crumb and the log, then leave.
async function prime(ctx, base, crumbObj, logArr) {
  const page = await ctx.newPage();
  await page.goto(base + BLANK);
  await page.evaluate(([c, l]) => {
    localStorage.removeItem('ashgrave_crumb');
    localStorage.removeItem('ashgrave_crumb_log');
    if (c) localStorage.setItem('ashgrave_crumb', JSON.stringify(c));
    if (l) localStorage.setItem('ashgrave_crumb_log', JSON.stringify(l));
  }, [crumbObj, logArr]);
  await page.close();
}

// Renderer crash: no pagehide, nothing written.
async function kill(ctx, page) {
  const cdp = await ctx.newCDPSession(page);
  let crashed = false;
  page.on('crash', () => { crashed = true; });
  cdp.send('Page.crash').catch(() => {});
  await waitFor(async () => crashed, 20);
  return crashed;
}

const getLog = (page) => page.evaluate(() => JSON.parse(localStorage.getItem('ashgrave_crumb_log') || '[]'));

(async () => {
  const { server, base } = await serve();
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({ args: GL });
  const ctx = await browser.newContext({ deviceScaleFactor: 1 });
  await ctx.route(base + BLANK, (r) => r.fulfill({ contentType: 'text/html', body: '<!doctype html><title>x</title>' }));
  const allErrors = [];
  try {
    // 1. First run: crumbs appear and show the land.
    const a = await open(ctx, base, { width: 844, height: 390 });
    allErrors.push(a.errors);
    // The very first crumb from the game has the heap figure already (item: heap reads 0 until a growth).
    const firstRun = await waitFor(async () => { const c = await crumb(a.page); return c && c.phase === 'run' ? c : null; }, 120);
    check(!!firstRun && firstRun.heap > 0, `first game crumb already has a heap figure (${firstRun && firstRun.heap})`);
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
      check(typeof second.run === 'string' && !second.shared && !second.stalled, 'crumb has a run id and no shared/stalled flag');
      console.log(`wasm heap bytes: ${second.heap}`);
    }
    check(!died(a), 'first run reports no death');

    // 2. Kill without pagehide: crash the renderer, keep the context.
    check(await kill(ctx, a.page), 'renderer crashed (no pagehide)');

    // 3. Relaunch: death reported, banner shown.
    // --crumbhold keeps the banner up (no auto-hide) so the slow headless run can be photographed.
    const b = await open(ctx, base, { width: 390, height: 844 }, ['--crumbhold']);
    allErrors.push(b.errors);
    await b.page.addStyleTag({ content: '#rotate{display:none !important}' });
    const d1 = await waitFor(async () => died(b), 120);
    check(!!d1, 'relaunch prints [crumb] died:');
    if (d1) {
      console.log(d1);
      const num = (k) => Number(field(d1, k));
      check(/mode=land/.test(d1), 'died line says mode=land');
      check(/place=\S+/.test(d1), 'died line has a place');
      check(num('heap_mb') > 0, 'died line has non-zero wasm heap');
      check(num('objects') > 0, 'died line has non-zero object count');
      check(/kind=died/.test(d1) && num('banner') === 1 && num('stalled') === 0 && num('shared') === 0, 'recent foreground death shows the banner');
    }
    await sleep(2500);
    // (The page covers a portrait canvas with a "turn your phone sideways" note; hidden above to see the banner itself.)
    await sleep(1500);
    await b.page.screenshot({ path: path.join(OUT, 'crumb-portrait.png') });
    await b.page.setViewportSize({ width: 844, height: 390 });
    await sleep(2500);
    await b.page.screenshot({ path: path.join(OUT, 'crumb-landscape.png') });
    const log = await getLog(b.page);
    check(log.length === 1 && log[0].kind === 'died', `death log has one entry (${log.length})`);

    // 4. Clean exit: wait until this run is writing crumbs, then reload normally.
    await waitFor(async () => { const c = await crumb(b.page); return c && c.live === true && c.mode !== 'boot' && c.phase === 'run'; }, 90);
    await b.page.reload();
    const c = { page: b.page, lines: [] };
    b.page.on('console', (m) => c.lines.push(m.text()));
    const rebooted = await waitFor(async () => { const k = await crumb(b.page); return k && k.live === true && k.phase === 'run' && k.t < 20; }, 120);
    await sleep(3000);
    check(!!rebooted, 'page came back after reload');
    check(!died(c), 'normal reload reports no death');
    check((await getLog(b.page)).length === 1, 'death log unchanged after a normal reload');

    // 5. The engine stops writing (heap exhausted: the engine aborts, the page lives), then the player reloads normally.
    await b.page.evaluate(() => { window.__ag.w = function () {}; });
    await sleep(20000);
    await b.page.reload();
    const s = { page: b.page, lines: [] };
    b.page.on('console', (m) => s.lines.push(m.text()));
    const d2 = await waitFor(async () => died(s), 120);
    check(!!d2, 'reload after a stalled engine still reports a death');
    if (d2) {
      console.log(d2);
      check(/kind=stalled/.test(d2) && field(d2, 'stalled') === '1' && field(d2, 'banner') === '1', 'stalled death has stalled=1 and shows the banner');
    }
    const log3 = await getLog(b.page);
    check(log3.length === 2 && log3[1].kind === 'stalled', 'stalled death logged');

    // 6. Another live tab overwrites our key: our crumbs are marked shared.
    await waitFor(async () => { const k = await crumb(b.page); return k && k.phase === 'run' && k.live; }, 120);
    await b.page.evaluate(() => localStorage.setItem('ashgrave_crumb', JSON.stringify({ run: 'someoneelse', live: true, ts: Date.now(), mode: 'land' })));
    const sharedCrumb = await waitFor(async () => { const k = await crumb(b.page); return k && k.shared === true ? k : null; }, 20);
    check(!!sharedCrumb, 'a fresh live crumb from another run id marks ours shared');
    check(await kill(ctx, b.page), 'shared page crashed');
    const e = await open(ctx, base, { width: 844, height: 390 });
    allErrors.push(e.errors);
    const d3 = await waitFor(async () => died(e), 120);
    check(!!d3, 'shared crumb is still logged on next boot');
    if (d3) {
      console.log(d3);
      check(field(d3, 'shared') === '1' && field(d3, 'banner') === '0', 'shared crumb: shared=1 and no banner');
    }
    check((await getLog(e.page)).some((x) => x.kind === 'shared'), 'shared crumb in the log');

    // 7. Hidden tab is a clean exit too.
    await waitFor(async () => { const k = await crumb(e.page); return k && k.phase === 'run' && k.live; }, 120);
    const hiddenFlag = await e.page.evaluate(() => {
      Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' });
      document.dispatchEvent(new Event('visibilitychange'));
      const k = JSON.parse(localStorage.getItem('ashgrave_crumb'));
      return [k.live, !!k.hid_at];
    });
    check(hiddenFlag[0] === false && hiddenFlag[1] === true, 'visibilitychange to hidden clears live and sets hid_at');
    await kill(ctx, e.page);

    // 8. Death during boot (engine download never finishes): reported as phase=boot.
    await prime(ctx, base, null, null);
    const h = await openPage(ctx, base, { width: 844, height: 390 }, [], { hang: true });
    const bootCrumb = await waitFor(async () => { const k = await crumb(h.page); return k && k.phase === 'boot' ? k : null; }, 20);
    check(!!bootCrumb && bootCrumb.live === true && bootCrumb.ts > 0, 'a boot crumb is written before the engine loads');
    await sleep(3000);
    await kill(ctx, h.page);
    const f = await open(ctx, base, { width: 844, height: 390 });
    allErrors.push(f.errors);
    const d4 = await waitFor(async () => died(f), 120);
    check(!!d4 && field(d4, 'phase') === 'boot' && field(d4, 'banner') === '1', `death during boot reported as phase=boot${d4 ? '' : ' (no line)'}`);
    if (d4) console.log(d4);
    await kill(ctx, f.page);

    // 9. A page that boots in a background tab and is discarded (no pagehide): a quiet note, never a death.
    await prime(ctx, base, null, null);
    const g = await openPage(ctx, base, { width: 844, height: 390 }, [], { hang: true, hidden: true });
    const hidCrumb = await waitFor(async () => { const k = await crumb(g.page); return k && k.phase === 'boot' ? k : null; }, 20);
    check(!!hidCrumb && hidCrumb.live === false && hidCrumb.hid_at > 0, 'a page that boots hidden starts with live=false and hid_at');
    await sleep(3000);
    await kill(ctx, g.page);
    const i = await open(ctx, base, { width: 844, height: 390 });
    allErrors.push(i.errors);
    const note = await waitFor(async () => i.lines.find((l) => l.startsWith('[crumb] note: reloaded after being hidden for')), 120);
    check(!!note, `hidden-then-gone reports a quiet note${note ? ': ' + note : ''}`);
    check(!died(i), 'hidden-then-gone is not reported as a death');
    check((await getLog(i.page)).some((x) => x.kind === 'hidden'), 'hidden note in the log with kind hidden');
    await kill(ctx, i.page);

    // 10. An old death (more than 10 minutes before this boot) is logged but shows no banner.
    await prime(ctx, base, { phase: 'run', live: true, ts: Date.now() - 11 * 60 * 1000, run: 'old', mode: 'land', place: 'Old', t: 600, heap: 100 << 20 }, null);
    const j = await open(ctx, base, { width: 844, height: 390 });
    allErrors.push(j.errors);
    const d5 = await waitFor(async () => died(j), 120);
    check(!!d5 && field(d5, 'banner') === '0' && Number(field(d5, 'age_s')) > 600, `old death: logged, no banner${d5 ? ' (' + field(d5, 'age_s') + ' s old)' : ''}`);
    check((await getLog(j.page)).some((x) => x.kind === 'died'), 'old death in the log');
    await kill(ctx, j.page);

    // 11. A visible tab answers a new tab's ping: both are marked shared.
    await prime(ctx, base, null, null);
    const other = await ctx.newPage();
    await other.goto(base + BLANK);
    await other.evaluate(() => { const bc = new BroadcastChannel('ashgrave_tabs'); bc.onmessage = (e) => { if (e.data === 'ping') bc.postMessage('pong'); }; window.__bc = bc; });
    const k2 = await openPage(ctx, base, { width: 844, height: 390 }, [], { hang: true });
    const pongd = await waitFor(async () => { const k = await crumb(k2.page); return k && k.shared === true ? k : null; }, 20);
    check(!!pongd, 'a live second tab answering the ping marks the crumb shared');
    await kill(ctx, k2.page);

    const errors = allErrors.flat();
    check(errors.length === 0, `no script errors${errors.length ? ': ' + errors[0] : ''}`);
  } catch (e) {
    check(false, 'test threw: ' + e);
  }
  await browser.close().catch(() => {});
  server.close();
  console.log(failures.length ? `FAILED (${failures.length})` : 'crumb test passed');
  process.exit(failures.length ? 1 : 0);
})();
