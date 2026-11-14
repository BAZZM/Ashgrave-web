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
//
//   node tools/crumb_test.js --decode CODE   reads back the six-character code on the restart banner
//                                            (packed by Perf.crumb_code in game/scripts/perf.gd)
function decodeCrumb(code) {
  let v = 0;
  const norm = code.trim().toUpperCase().replace(/O/g, '0').replace(/[IL]/g, '1');
  for (const ch of norm) v = v * 32 + '0123456789ABCDEFGHJKMNPQRSTVWXYZ'.indexOf(ch);
  return { heap_mb: v & 511, vid_mb: (v >> 9) & 127, mode: ['boot', 'title', 'land', 'tower', 'duel'][(v >> 16) & 7] || '?',
    minutes: (v >> 19) & 63, dpr: ['other', 1, 2, 3][(v >> 25) & 3], nodes: `${((v >> 27) & 7) * 250}+` };
}
if (process.argv[2] === '--decode') { console.log(JSON.stringify(decodeCrumb(process.argv[3] || ''))); process.exit(0); }
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
  if (opts.query) for (const [k, v] of Object.entries(opts.query)) q.set(k, v);
  if (!opts.plain) q.append('arg', '--autoplay=tour');
  for (const x of extra) q.append('arg', x);
  await page.goto(`${base}/index.html?${q}`);
  return { page, lines, errors };
}
const open = (ctx, base, viewport, extra = [], opts = {}) => openPage(ctx, base, viewport, extra, opts);
const died = (p) => p.lines.find((l) => l.startsWith('[crumb] died:'));
const field = (line, k) => { const m = new RegExp(`${k}=(\\S+)`).exec(line || ''); return m ? m[1] : null; };

// Same-origin scratch page: set (or clear, with null) the crumb and the log, then leave.
async function prime(ctx, base, crumbObj, logArr, saveObj) {
  const page = await ctx.newPage();
  await page.goto(base + BLANK);
  await page.evaluate(([c, l, sv]) => {
    if (sv !== '__keep') { localStorage.removeItem('ashgrave_save_v1'); if (sv) localStorage.setItem('ashgrave_save_v1', JSON.stringify(sv)); }
    localStorage.removeItem('ashgrave_crumb');
    localStorage.removeItem('ashgrave_crumb_log');
    if (c) localStorage.setItem('ashgrave_crumb', JSON.stringify(c));
    if (l) localStorage.setItem('ashgrave_crumb_log', JSON.stringify(l));
  }, [crumbObj, logArr, saveObj === undefined ? '__keep' : saveObj]);
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
      check(second.pk > 0 && second.cw > 0 && second.ch > 0 && second.dpr > 0 && 'dm' in second && 'hc' in second && typeof second.gl === 'string' && second.md === 0,
        `crumb has peak heap, canvas size, dpr, device memory, cores, renderer, memory deaths (${second.pk} ${second.cw}x${second.ch} dpr ${second.dpr} dm ${second.dm} hc ${second.hc} gl ${second.gl})`);
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
      const code = field(d1, 'code');
      const dec = code ? decodeCrumb(code) : null;
      check(!!code && /^[0-9A-HJKMNP-TV-Z]{6}$/.test(code) && dec.mode === 'land' && dec.heap_mb === num('heap_mb'), `died line has a 6-character code that decodes to mode=land and the heap (${code} ${JSON.stringify(dec)})`);
      check(num('peak_mb') >= num('heap_mb') && /^\d+x\d+$/.test(field(d1, 'canvas')) && Number(field(d1, 'dpr')) > 0 && Number(field(d1, 'cores')) !== 0 && field(d1, 'mdeaths') === '0' && !!field(d1, 'gl'),
        'died line has peak heap, canvas size, dpr, cores, memory deaths and renderer');
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


    // ---- (these boots run the plain page, no bot: the bots replace the loaded save, and with it the level)
    // ---- Automatic safe mode (game/scripts/perf.gd, run.gd, quality.gd). A fresh browser context per part, so each has its own save.
    const savedSettings = (page) => page.evaluate(() => { try { return (JSON.parse(localStorage.getItem('ashgrave_save_v1') || 'null') || {}).settings || null; } catch (e) { return null; } });
    const runCrumb = (page, level) => waitFor(async () => { const k = await crumb(page); return k && k.phase === 'run' && k.live && 'q' in k && (!level || k.q === level) && (!level || k.t >= 0) ? k : null; }, 180);
    const autoLine = (p) => p.lines.find((l) => l.startsWith('[crumb] auto-safe: switched'));
    const noticeCount = (p) => p.lines.filter((l) => l.startsWith('[crumb] notice:')).length;
    const V = { width: 844, height: 390 };
    const qctx = await browser.newContext({ deviceScaleFactor: 1 });
    await qctx.route(base + BLANK, (r) => r.fulfill({ contentType: 'text/html', body: '<!doctype html><title>x</title>' }));
    const dieAfterRun = async (p) => { const k = await runCrumb(p.page); await sleep(500); await kill(qctx, p.page); return k; };

    // Q1. Boot 1 (fresh save): full, no death. Boot 2 reports one foreground death: still full. Boot 3 the second: safe, notice once.
    const q1 = await open(qctx, base, V, [], { plain: true }); allErrors.push(q1.errors);
    const kq1 = await dieAfterRun(q1);
    check(!!kq1 && kq1.q === 'full' && kq1.qa === 0 && kq1.qd === 0 && kq1.qn === 0, `crumb carries the level and counts on a fresh save (q=${kq1 && kq1.q} qa=${kq1 && kq1.qa} qd=${kq1 && kq1.qd} qn=${kq1 && kq1.qn})`);
    const q2 = await open(qctx, base, V, [], { plain: true }); allErrors.push(q2.errors);
    check(!!(await waitFor(async () => died(q2), 150)), 'quality: boot 2 reports the first death');
    const kq2 = await dieAfterRun(q2);
    check(!autoLine(q2) && !!kq2 && kq2.q === 'full' && kq2.qd === 1, `one memory death does not switch (q=${kq2 && kq2.q} qd=${kq2 && kq2.qd})`);
    const q3 = await open(qctx, base, V, [], { plain: true }); allErrors.push(q3.errors);
    check(!!(await waitFor(async () => died(q3), 150)), 'quality: boot 3 reports the second death');
    const kq3 = await runCrumb(q3.page, 'safe');
    check(!!autoLine(q3) && !!kq3 && kq3.q === 'safe' && kq3.qa === 1 && kq3.qn === 1, `the second death switches to safe on the third boot (q=${kq3 && kq3.q} qa=${kq3 && kq3.qa} qn=${kq3 && kq3.qn})`);
    const sv3q = await savedSettings(q3.page);
    check(!!sv3q && sv3q.quality === 'safe' && sv3q.q_auto === true, `the automatic switch is saved and marked automatic (${JSON.stringify(sv3q)})`);
    check(noticeCount(q3) === 1, `the notice is shown once (${noticeCount(q3)})`);
    await sleep(1500);
    await q3.page.screenshot({ path: path.join(OUT, 'quality-auto-notice.png') });
    await kill(qctx, q3.page);

    // Q2. Two more deaths in safe: nothing more happens except the crumb.
    const q4 = await open(qctx, base, V, [], { plain: true }); allErrors.push(q4.errors);
    check(!!(await waitFor(async () => died(q4), 150)) && field(died(q4), 'q') === 'safe' && field(died(q4), 'qa') === '1', 'the death line says the dead run was in safe, set automatically');
    check(noticeCount(q4) === 0, 'the notice is not shown again');
    await dieAfterRun(q4);
    const q5 = await open(qctx, base, V, [], { plain: true }); allErrors.push(q5.errors);
    await waitFor(async () => died(q5), 150);
    const kq5 = await runCrumb(q5.page, 'safe');
    const sv5q = await savedSettings(q5.page);
    check(!autoLine(q5) && !!kq5 && kq5.q === 'safe' && kq5.qd >= 2 && sv5q.q_auto_n === 1, `two more deaths in safe change nothing but the crumb (qd=${kq5 && kq5.qd}, auto switches ${sv5q && sv5q.q_auto_n})`);
    await kill(qctx, q5.page);

    // Q3. The player goes back to Full from the map screen (MAP, then QUALITY): it sticks across a reload.
    const q6 = await open(qctx, base, V, [], { plain: true }); allErrors.push(q6.errors);
    await q6.page.addStyleTag({ content: '#rotate{display:none !important}' });
    await waitFor(async () => { const k = await crumb(q6.page); return k && k.mode === 'title' ? k : null; }, 180);
    await sleep(2000);
    await q6.page.mouse.click(422, 250);
    await waitFor(async () => { const k = await crumb(q6.page); return k && k.mode === 'land' ? k : null; }, 120);
    await sleep(2000);
    await q6.page.keyboard.press('m');
    await sleep(3000);
    // The button: panel right edge minus 440 .. minus 210 in a 720-high game view that is 844x390 on the page.
    const gw = 720 * 844 / 390, kx = 844 / gw;
    await q6.page.screenshot({ path: path.join(OUT, 'quality-map-safe.png') });
    await q6.page.mouse.click((gw - 50 - 325) * kx, 66 * (390 / 720));
    await sleep(2500);
    await q6.page.screenshot({ path: path.join(OUT, 'quality-map-full.png') });
    const sv6q = await waitFor(async () => { const v = await savedSettings(q6.page); return v && v.quality === 'full' ? v : null; }, 20);
    check(!!sv6q && sv6q.q_auto === false, `QUALITY on the map screen switches to Full and saves it (${JSON.stringify(sv6q)})`);
    await q6.page.reload();
    const kq6 = await runCrumb(q6.page);
    check(!!kq6 && kq6.q === 'full' && kq6.qa === 0, `Full sticks across a reload (q=${kq6 && kq6.q})`);
    await kill(qctx, q6.page);

    // Q4. A further two deaths switch again (deaths before the player's choice no longer count).
    const q7 = await open(qctx, base, V, [], { plain: true }); allErrors.push(q7.errors);
    await waitFor(async () => died(q7), 150);
    const kq7 = await dieAfterRun(q7);
    check(!autoLine(q7) && !!kq7 && kq7.q === 'full', 'after going back to Full one death does not switch');
    const q8 = await open(qctx, base, V, [], { plain: true }); allErrors.push(q8.errors);
    await waitFor(async () => died(q8), 150);
    const kq8 = await runCrumb(q8.page, 'safe');
    const sv8q = await savedSettings(q8.page);
    check(!!autoLine(q8) && !!kq8 && kq8.q === 'safe' && sv8q.q_auto_n === 2, `two further deaths switch to safe again (auto switches ${sv8q && sv8q.q_auto_n})`);
    await kill(qctx, q8.page);
    await qctx.close();

    // Q5. Deaths that must not count: a shared tab, a hidden-then-gone page, an old death, and a first death hours earlier.
    const NOW = () => Date.now();
    const fresh = (extra) => Object.assign({ phase: 'run', live: true, ts: NOW() - 20000, run: 'x' + Math.random(), mode: 'land', place: 'Hearthvale', t: 300, heap: 90 << 20 }, extra);
    const prior = (ts) => ({ phase: 'run', live: true, ts, run: 'p', mode: 'land', t: 200, kind: 'died', age: 5 });
    const cases = [
      ['a shared-tab death', fresh({ shared: true }), [prior(NOW() - 120000)]],
      ['a background reload', { phase: 'run', live: false, hid_at: NOW() - 30000, ts: NOW() - 30000, run: 'h', mode: 'land' }, [prior(NOW() - 120000)]],
      ['a death older than the banner age limit', fresh({ ts: NOW() - 11 * 60 * 1000 }), [prior(NOW() - 12 * 60 * 1000)]],
      ['two deaths three hours apart', fresh({}), [prior(NOW() - 3 * 3600 * 1000)]],
    ];
    for (const [what, crumbObj, log] of cases) {
      await prime(ctx, base, crumbObj, log, null);
      const p = await open(ctx, base, V); allErrors.push(p.errors);
      await waitFor(async () => died(p) || p.lines.find((l) => l.startsWith('[crumb] note:')), 150);
      const k = await runCrumb(p.page);
      const sv = await savedSettings(p.page);
      check(!autoLine(p) && !!k && k.q === 'full' && !(sv && sv.quality === 'safe'), `${what} does not count (q=${k && k.q})`);
      await kill(ctx, p.page);
    }

    // Q6. ?quality=safe applies for the session and is not saved; ?quality=full beats a saved safe, also unsaved.
    await prime(ctx, base, null, null, null);
    const o1 = await open(ctx, base, V, [], { query: { quality: 'safe' } }); allErrors.push(o1.errors);
    const kq1o = await runCrumb(o1.page);
    await sleep(8000);
    const sv1o = await savedSettings(o1.page);
    check(!!kq1o && kq1o.q === 'safe' && kq1o.qa === 0 && !(sv1o && sv1o.quality === 'safe'), `?quality=safe applies without saving (q=${kq1o && kq1o.q}, saved ${JSON.stringify(sv1o)})`);
    await kill(ctx, o1.page);
    await prime(ctx, base, null, null, { version: 3, settings: { quality: 'safe', q_auto: false } });
    const o2 = await open(ctx, base, V, [], { query: { quality: 'full' } }); allErrors.push(o2.errors);
    const kq2o = await runCrumb(o2.page);
    await sleep(8000);
    const sv2o = await savedSettings(o2.page);
    check(!!kq2o && kq2o.q === 'full' && !!sv2o && sv2o.quality === 'safe', `?quality=full overrides a saved safe for the session only (q=${kq2o && kq2o.q}, saved ${sv2o && sv2o.quality})`);
    await kill(ctx, o2.page);
    // A save from before the settings existed loads as Full.
    await prime(ctx, base, null, null, { version: 3, gold: 7 });
    const o3 = await open(ctx, base, V); allErrors.push(o3.errors);
    const kq3o = await runCrumb(o3.page);
    check(!!kq3o && kq3o.q === 'full', `an old save without settings loads as full (q=${kq3o && kq3o.q})`);
    await kill(ctx, o3.page);

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
