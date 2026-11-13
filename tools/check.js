#!/usr/bin/env node
// Run the game's built-in bots as pass/fail scenarios in headless Chromium.
//
//   node tools/check.js                 run every scenario
//   node tools/check.js load pvp        run only the scenarios whose names start with these
//   node tools/check.js --list          list the scenarios
//   node tools/check.js --probe "--autoplay=x --wild=thrall"
//                                       run one client with those game args and print its console
//
// Options: --jobs=N (scenarios run at once, default 1), --verbose (print every game
// console line), --viewport=WxH (default 320x180), --timeout=SECONDS (probe length), --shots=DIR (probe).
//
// Needs Playwright with Chromium (as smoke.js) and, for the relay,
// `npm install` in tools/ (aedes and ws). Uses software WebGL, so the game runs
// at a few frames a second; the full run takes 8-9 minutes (--jobs=2 or 3
// is only a little faster: the machine is CPU-bound).
//
// Every client is its own browser with an empty profile (so an empty save), and
// every client is pointed at a local MQTT relay, never the public ones, so a
// check cannot put bots into the live shared world.
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');

let chromium;
let Aedes;
let WebSocketServer;
let createWebSocketStream;
try {
  ({ chromium } = require('playwright'));
} catch (e) {
  console.error('check.js needs Playwright with Chromium (npm i -g playwright && npx playwright install chromium).');
  process.exit(2);
}
// aedes is an ES module, so it is loaded with import() (works on any recent Node).
async function loadRelayPackages() {
  try {
    ({ Aedes } = await import('aedes'));
    ({ WebSocketServer, createWebSocketStream } = require('ws'));
  } catch (e) {
    console.error('check.js needs the relay packages: run `npm install` in tools/ first.');
    process.exit(2);
  }
}

const opts = { jobs: 1, verbose: false, viewport: '320x180', timeout: 300, probe: null, list: false };
const names = [];
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (a === '--verbose') opts.verbose = true;
  else if (a === '--list') opts.list = true;
  else if (a === '--probe') opts.probe = process.argv[++i] || '';
  else if (a.startsWith('--jobs=')) opts.jobs = Math.max(1, Number(a.slice(7)));
  else if (a.startsWith('--shots=')) opts.shots = a.slice(8);
  else if (a.startsWith('--viewport=')) opts.viewport = a.slice(11);
  else if (a.startsWith('--timeout=')) opts.timeout = Number(a.slice(10));
  else if (a.startsWith('-')) { console.error(`unknown option ${a}`); process.exit(2); }
  else names.push(a);
}
const [VW, VH] = opts.viewport.split('x').map(Number);

// ---------------------------------------------------------------- servers

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };

// Serves the repo root. Each `arg=` query parameter on index.html becomes one
// game user arg, written into GODOT_CONFIG by this server (not by the browser,
// so the page stays on a plain local origin and may reach a local relay).
function startStatic() {
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
          res.writeHead(500).end('index.html no longer has "args":[] in GODOT_CONFIG; update tools/check.js');
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
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve({
    url: `http://127.0.0.1:${server.address().port}`,
    close: () => server.close(),
  })));
}

// An MQTT broker over WebSocket that counts the direct messages ("k" values) passing through.
async function startRelay() {
  const broker = await Aedes.createBroker();
  const counts = {};
  broker.on('publish', (packet, client) => {
    if (!client || !packet.topic.includes('/c/')) return;
    try {
      const k = JSON.parse(packet.payload.toString()).k;
      counts[k] = (counts[k] || 0) + 1;
    } catch (e) { /* not a game message */ }
  });
  const server = http.createServer();
  const wss = new WebSocketServer({ server, handleProtocols: (p) => (p.has('mqtt') ? 'mqtt' : false) });
  wss.on('connection', (ws) => broker.handle(createWebSocketStream(ws)));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  return {
    url: `ws://127.0.0.1:${server.address().port}`,
    counts,
    close: async () => {
      for (const c of wss.clients) c.terminate();
      wss.close();
      server.close();
      await new Promise((r) => broker.close(r));
    },
  };
}

// ---------------------------------------------------------------- clients

const GL = ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'];

class Client {
  constructor(label) {
    this.label = label;
    this.lines = [];
    this.errors = [];
    this.t0 = Date.now();
    // Once this pattern is seen the bot is done and quits; errors from the engine
    // shutting down after that are not the build's.
    this.stopRe = null;
    this.done = false;
  }

  async start(base, gameArgs, relays) {
    this.browser = await chromium.launch({ args: GL });
    // newPage on a fresh browser is a fresh profile: no save, no localStorage.
    this.page = await this.browser.newPage({ viewport: { width: VW, height: VH }, deviceScaleFactor: 1 });
    this.page.on('pageerror', (e) => { if (!this.done) this.errors.push(String(e).slice(0, 400)); });
    this.page.on('crash', () => { if (!this.done) this.errors.push('page crashed'); });
    this.page.on('console', (m) => {
      const text = m.text();
      this.lines.push(text);
      const wasDone = this.done;
      if (this.stopRe && this.stopRe.test(text)) this.done = true;
      if (opts.verbose && !/^Blocked call to navigator\.vibrate|^The AudioContext/.test(text)) console.log(`  [${this.label} ${((Date.now() - this.t0) / 1000).toFixed(0)}s] ${text.slice(0, 200)}`);
      // Noise that is the browser's business: an unreachable relay, and vibration before a tap.
      if (wasDone) return;
      if (/^WebSocket connection to|^Blocked call to navigator\.vibrate/.test(text)) return;
      if (m.type() === 'error' || /SCRIPT ERROR|Parse Error/.test(text)) this.errors.push(text.slice(0, 400));
    });
    const q = new URLSearchParams();
    if (relays.length) q.set('relay', relays.join(','));
    for (const a of gameArgs) q.append('arg', a);
    this.t0 = Date.now();
    await this.page.goto(`${base}/index.html?${q}`);
  }

  find(re) { return this.lines.find((l) => re.test(l)); }

  async close() {
    if (!this.browser) return;
    await this.browser.close().catch(() => {});
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Resolves 'ok' when done() is true, 'error' as soon as any client reports a
// script error, or 'timeout'.
async function waitUntil(clients, done, seconds) {
  const end = Date.now() + seconds * 1000;
  while (Date.now() < end) {
    if (clients.some((c) => c.errors.length)) return 'error';
    if (done()) return 'ok';
    await sleep(250);
  }
  return done() ? 'ok' : 'timeout';
}

// ---------------------------------------------------------------- scenarios

// Each scenario: run(ctx) returns {ok, notes[]}. ctx has base (page server),
// newRelay(), and client(label).
const scenarios = [];
function scenario(name, describe, run, slow = false) { scenarios.push({ name, describe, run, slow }); }

function errorNotes(clients) {
  const notes = [];
  for (const c of clients) for (const e of c.errors.slice(0, 3)) notes.push(`${c.label}: script error: ${e}`);
  return notes;
}

// Run one client with the given game args until a line matching `finish`
// appears (or `fail` does, or time runs out). `verify(lines)` may return a
// string describing what is wrong with what it printed.
async function solo(ctx, { args, finish, fail, seconds, verify }) {
  const relay = await ctx.newRelay();
  const c = await ctx.client('bot');
  c.stopRe = finish;
  await c.start(ctx.base, args, [relay.url]);
  const r = await waitUntil([c], () => c.find(finish) || (fail && c.find(fail)), seconds);
  const notes = errorNotes([c]);
  let ok = r === 'ok';
  if (r === 'timeout') notes.push(`no line matching ${finish} within ${seconds}s`);
  if (ok && fail && c.find(fail)) { ok = false; notes.push(`saw: ${c.find(fail)}`); }
  if (ok) {
    const problem = verify && verify(c.lines);
    if (problem) { ok = false; notes.push(problem); }
  }
  notes.push(...c.lines.filter((l) => GAME_LINE.test(l)).slice(-3).map((l) => `saw: ${l.slice(0, 150)}`));
  return { ok, notes };
}

const GAME_LINE = /^(LAND|WORLD|TOUR|RESULT|GATHER|PVP)/;
const lineOf = (lines, re) => lines.find((l) => re.test(l));

// ---- 1. load

scenario('load', 'title screen loads and the world builds (bot idles in it), no script errors', async (ctx) => {
  const relay = await ctx.newRelay();
  const notes = [];
  // Plain page, as a player gets it: boot, tap past the title, picture must not be blank.
  const plain = await ctx.client('plain');
  await plain.start(ctx.base, [], [relay.url]);
  await sleep(16000);
  for (let i = 0; i < 2; i++) {
    await plain.page.mouse.click(VW / 2, VH * 0.6);
    await sleep(3000);
  }
  const shot = await plain.page.screenshot();
  notes.push(...errorNotes([plain]));
  if (plain.errors.length === 0 && shot.length < 3000) notes.push(`screen looks blank (${shot.length} byte screenshot)`);
  await plain.close();
  if (notes.length) return { ok: false, notes };
  // Same page, but the pvp_a bot: the world builds without a title and says so.
  return solo(ctx, { args: ['--autoplay=pvp_a'], finish: /^LAND /, seconds: 60 });
});

// ---- 2. solo duels

const expectResult = (re) => (lines) => {
  const l = lineOf(lines, /^RESULT /);
  return re.test(l) ? null : `expected ${re}, got: ${l}`;
};

scenario('duel-win', 'a bot beats a Field Thrall in a standalone duel', (ctx) => solo(ctx, {
  args: ['--autoplay=x', '--wild=thrall'], finish: /^RESULT /, seconds: 120,
  verify: expectResult(/^RESULT win Field Thrall .* foes=1$/),
}));

scenario('duel-loss', 'an idle bot loses a standalone duel', (ctx) => solo(ctx, {
  args: ['--autoplay=idle', '--wild=thrall'], finish: /^RESULT /, seconds: 120,
  verify: expectResult(/^RESULT lose Field Thrall .* foes=0$/),
}));

scenario('duel-gear', 'a bot with bow, spell and skills beats a bandit', (ctx) => solo(ctx, {
  args: ['--autoplay=x', '--wild=bandit', '--equip=hunters_bow,ember_bolt', '--skills=20'], finish: /^RESULT /, seconds: 150,
  verify: expectResult(/^RESULT win Greywood Bandit /),
}));

scenario('duel-pack', 'a duel against several foes at once runs to a result', (ctx) => solo(ctx, {
  args: ['--autoplay=x', '--wild=thrall', '--pack=2', '--skills=20'], finish: /^RESULT /, seconds: 180,
}));

scenario('duel-tower', 'a tower guardian duel (floor 1) runs to a result', (ctx) => solo(ctx, {
  args: ['--autoplay=x', '--kind=guardian', '--floor=1'], finish: /^RESULT /, seconds: 180,
  verify: expectResult(/^RESULT \w+ The Cinder Warden /),
}));

// ---- 3. world tour

// On the road north the bot is sometimes caught by a strong foe and loses,
// depending on frame timing; it happens with unchanged code. That says nothing
// about the build, so only that outcome is retried. A script error, a timeout
// or a wrong result still fails on the first attempt.
const TOUR_ATTEMPTS = 3;
scenario('tour', 'tour bot walks to the tower, wins tier 1 and enters tier 2', async (ctx) => {
  const earlier = [];
  for (let attempt = 1; ; attempt++) {
    const res = await solo(ctx, {
      args: ['--autoplay=tour'], finish: /^WORLD tier=2 /, fail: /^TOUR hero fell/, seconds: 240,
      verify: (lines) => {
        if (!lines.some((l) => /^LAND /.test(l)) || !lines.some((l) => /^WORLD tier=1 /.test(l))) return 'did not pass through the land and tier 1';
        const wins = lines.filter((l) => /^RESULT win /.test(l)).length;
        return wins >= 2 ? null : `only ${wins} duel win(s) before tier 2`;
      },
    });
    const fell = !res.ok && res.notes.some((n) => /^saw: TOUR hero fell/.test(n)) && !res.notes.some((n) => /script error/.test(n));
    if (!fell || attempt === TOUR_ATTEMPTS) return { ok: res.ok, notes: [...earlier, ...res.notes] };
    earlier.push(`attempt ${attempt}: the bot lost a fight on the road; retrying`);
  }
}, true);

// ---- 4. gather

scenario('gather', 'gather bot mines, crafts and takes the task', (ctx) => solo(ctx, {
  args: ['--autoplay=gather'], finish: /^GATHER /, seconds: 120,
  verify: (lines) => {
    const l = lineOf(lines, /^GATHER /);
    if (/mats=\{\s*\}/.test(l)) return `nothing gathered: ${l}`;
    if (!/mats=\{[^}]*: [1-9]/.test(l)) return `no material count above zero: ${l}`;
    if (!/made=\["/.test(l)) return `nothing made: ${l}`;
    if (!/task=\w+/.test(l)) return `no task taken: ${l}`;
    return null;
  },
}));

// ---- 5 and 6. two players

// Two clients, one browser each, on `relayCount` shared local relays. Passes
// when both print "PVP done" and every relay saw exactly one challenge, one
// accept, one dead and as many res as atk.
async function pvp(ctx, relayCount) {
  const relays = [];
  for (let i = 0; i < relayCount; i++) relays.push(await ctx.newRelay());
  const urls = relays.map((r) => r.url);
  const a = await ctx.client('A');
  const b = await ctx.client('B');
  a.stopRe = /^PVP done/;
  b.stopRe = /^PVP done/;
  await Promise.all([a.start(ctx.base, ['--autoplay=pvp_a'], urls), b.start(ctx.base, ['--autoplay=pvp_b'], urls)]);
  const r = await waitUntil([a, b], () => a.find(/^PVP done/) && b.find(/^PVP done/), 420);
  await sleep(1500);
  const notes = errorNotes([a, b]);
  let ok = r === 'ok';
  if (r === 'timeout') notes.push(`PVP done missing: A ${a.find(/^PVP done/) ? 'done' : 'not done'}, B ${b.find(/^PVP done/) ? 'done' : 'not done'}`);
  if (ok) {
    const wa = /won=(true|false)/.exec(a.find(/^PVP done/))[1];
    const wb = /won=(true|false)/.exec(b.find(/^PVP done/))[1];
    if (wa === wb) { ok = false; notes.push(`both players report won=${wa}`); }
  }
  relays.forEach((relay, i) => {
    const k = relay.counts;
    const n = (x) => k[x] || 0;
    const tag = relays.length > 1 ? `relay ${i + 1}: ` : '';
    notes.push(`${tag}saw ${JSON.stringify(k)}`);
    const wrong = [];
    if (n('atk') < 1) wrong.push('no atk');
    if (n('res') !== n('atk')) wrong.push(`res ${n('res')} != atk ${n('atk')}`);
    for (const x of ['challenge', 'accept', 'dead']) if (n(x) !== 1) wrong.push(`${x} x${n(x)}, wanted 1`);
    if (wrong.length) { ok = false; notes.push(`${tag}${wrong.join('; ')}`); }
  });
  return { ok, notes };
}

scenario('pvp', 'two players duel through one relay', (ctx) => pvp(ctx, 1), true);
scenario('pvp-2relay', 'two players duel through the same two relays, duplicates dropped', (ctx) => pvp(ctx, 2), true);

// ---- 7. RigVisual contract (docs/RIG_PLAN.md R1; debug scene, the game itself does not use it yet)

// The look test runs the check on its own 240 Hz clock (not frames), so the timings below do not
// depend on how slowly software WebGL draws.
scenario('rig-contract', 'RigVisual: every contract action lands its key pose on time, windups distinct, unknown actions ignored, reparent and tweens safe', async (ctx) => {
  let seen = [];
  const res = await solo(ctx, {
    args: ['--looktest=rig-check'], finish: /^LOOKTEST rig-check ok=/, seconds: 180,
    verify: (lines) => {
      seen = lines;
      const rc = lines.filter((l) => /^RIGCHECK /.test(l));
      const actions = rc.filter((l) => /^RIGCHECK action /.test(l));
      const bad = actions.filter((l) => !/ ok$/.test(l));
      if (actions.length < 34) return `only ${actions.length} action lines (want 32 sequence actions + reparent + tween)`;
      if (bad.length) return `late or missed key poses: ${bad.slice(0, 3).join(' | ')}`;
      const fails = rc.filter((l) => /^RIGCHECK FAIL/.test(l));
      if (fails.length) return fails.slice(0, 3).join(' | ');
      for (const want of [/^RIGCHECK windup_distinct /, /^RIGCHECK clash_point /, /^RIGCHECK unknown_action ignored=true/, /^RIGCHECK meshkit_blade /, /^RIGCHECK done ok=true/]) {
        if (!lineOf(lines, want)) return `missing ${want}`;
      }
      const wd = /min_hand_pair=([\d.]+)/.exec(lineOf(lines, /^RIGCHECK windup_distinct /));
      if (!wd || Number(wd[1]) < 0.25) return `windup hand positions too close: ${lineOf(lines, /^RIGCHECK windup_distinct /)}`;
      const cp = /max_distance=([\d.]+)/.exec(lineOf(lines, /^RIGCHECK clash_point /));
      if (!cp || Number(cp[1]) > 0.3) return `clash point off: ${lineOf(lines, /^RIGCHECK clash_point /)}`;
      return null;
    },
  });
  // The figures the plan asked for, so a pass also shows them.
  const shown = [];
  for (const re of [/^LOOKTEST rig-check /, /^RIGCHECK windup_pose /, /^RIGCHECK windup_distinct /, /^RIGCHECK meshkit_blade /, /^RIGCHECK done /]) shown.push(...seen.filter((l) => re.test(l)));
  return { ok: res.ok, notes: [...res.notes, ...shown.map((l) => `saw: ${l.slice(0, 150)}`)] };
});

// ---------------------------------------------------------------- main

// One scenario's own context: its own clients and relays, closed when it ends.
function makeContext(base) {
  const relays = [];
  const clients = [];
  const ctx = {
    base,
    newRelay: async () => { const r = await startRelay(); relays.push(r); return r; },
    client: async (label) => { const c = new Client(label); clients.push(c); return c; },
  };
  const cleanup = async () => {
    for (const c of clients.splice(0)) await c.close();
    for (const r of relays.splice(0)) await r.close().catch(() => {});
  };
  return { ctx, cleanup };
}

async function main() {
  await loadRelayPackages();
  const page = await startStatic();
  const live = new Set();
  process.on('SIGINT', async () => {
    for (const cleanup of live) await cleanup();
    process.exit(130);
  });
  let failed = 0;
  try {
    if (opts.probe !== null) {
      opts.verbose = true;
      const { ctx, cleanup } = makeContext(page.url);
      live.add(cleanup);
      const relay = await ctx.newRelay();
      const c = await ctx.client('probe');
      await c.start(page.url, opts.probe.split(/\s+/).filter(Boolean), [relay.url]);
      const end = Date.now() + opts.timeout * 1000;
      for (let n = 0; Date.now() < end; n++) {
        await sleep(20000);
        if (opts.shots) await c.page.screenshot({ path: path.join(opts.shots, `probe-${String(n).padStart(2, '0')}.png`) }).catch(() => {});
      }
      console.log('relay counts', relay.counts, 'errors', c.errors);
      await cleanup();
      return;
    }
    const unknown = names.filter((n) => !scenarios.some((s) => s.name.startsWith(n)));
    if (unknown.length) { console.error(`no scenario matches ${unknown.join(', ')}; try --list`); failed = 2; return; }
    let chosen = names.length ? scenarios.filter((s) => names.some((n) => s.name.startsWith(n))) : scenarios;
    // With several jobs, start the slow ones first so they overlap the quick ones.
    if (opts.jobs > 1) chosen = [...chosen.filter((s) => s.slow), ...chosen.filter((s) => !s.slow)];
    const t0 = Date.now();
    const results = [];
    let next = 0;
    const worker = async () => {
      while (next < chosen.length) {
        const s = chosen[next++];
        const t = Date.now();
        const { ctx, cleanup } = makeContext(page.url);
        live.add(cleanup);
        let res;
        try { res = await s.run(ctx); } catch (e) { res = { ok: false, notes: [`harness error: ${e.stack || e}`] }; }
        await cleanup();
        live.delete(cleanup);
        const secs = ((Date.now() - t) / 1000).toFixed(0);
        // Printed as each one finishes, so the output is whole lines per scenario.
        console.log([`${res.ok ? 'PASS' : 'FAIL'}  ${s.name.padEnd(11)} ${secs.padStart(4)}s  ${s.describe}`, ...res.notes.map((n) => `        ${n}`)].join('\n'));
        results.push(res);
      }
    };
    await Promise.all(Array.from({ length: Math.min(opts.jobs, chosen.length) }, worker));
    failed = results.filter((r) => !r.ok).length;
    console.log(`${failed ? 'FAILED' : 'ok'}: ${chosen.length - failed}/${chosen.length} passed in ${((Date.now() - t0) / 1000).toFixed(0)}s`);
  } finally {
    page.close();
  }
  process.exitCode = failed ? 1 : 0;
}

if (require.main === module) {
  if (opts.list) { for (const s of scenarios) console.log(`${s.name.padEnd(11)} ${s.describe}`); process.exit(0); }
  main().then(() => process.exit(process.exitCode || 0), (e) => { console.error(e); process.exit(1); });
}
