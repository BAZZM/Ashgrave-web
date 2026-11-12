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

// ---- 4b. world agility (docs/COMBAT_RULES.md section 6, acceptance in section 9)

// `--autoplay=gather --agility`: the hero moves by the real movement code on a cleared lane,
// fed a scripted stick; the game prints AGILITY lines measured in game time (see
// overworld_bot.gd). Each check below quotes the spec number beside the measured one.
function parseAgility(lines) {
  const out = {};
  for (const l of lines) {
    const m = /^AGILITY (\w+) (.*)$/.exec(l);
    if (!m) continue;
    const kv = {};
    for (const part of m[2].split(' ')) {
      const e = part.indexOf('=');
      if (e > 0) kv[part.slice(0, e)] = part.slice(e + 1);
    }
    (out[m[1]] = out[m[1]] || []).push(kv);
  }
  return out;
}

scenario('agility', 'world movement: run, sprint, turns, dash and its limits match COMBAT_RULES section 6', async (ctx) => {
  const relay = await ctx.newRelay();
  const c = await ctx.client('bot');
  c.stopRe = /^AGILITY (done|fail)/;
  await c.start(ctx.base, ['--autoplay=gather', '--agility'], [relay.url]);
  const r = await waitUntil([c], () => c.find(/^AGILITY (done|fail)/), 420);
  const notes = errorNotes([c]);
  if (r !== 'ok') { notes.push(`no AGILITY done within 420s (${r})`); return { ok: false, notes }; }
  if (c.find(/^AGILITY fail/)) return { ok: false, notes: [...notes, c.find(/^AGILITY fail/)] };
  const a = parseAgility(c.lines);
  const g = (name, key = null, i = 0) => {
    const row = a[name] && a[name][i];
    if (!row) return NaN;
    return key === null ? row : (row[key] === undefined ? NaN : (isNaN(Number(row[key])) ? row[key] : Number(row[key])));
  };
  const rows = [];
  // [label, spec, measured, ok]
  const num = (label, spec, name, key, lo, hi, i = 0) => {
    const v = g(name, key, i);
    rows.push([label, spec, Number.isFinite(v) ? v.toFixed(3) : 'missing', Number.isFinite(v) && v >= lo && v <= hi]);
  };
  const flag = (label, spec, name, key, want) => {
    const v = g(name, key);
    rows.push([label, spec, String(v), String(v) === String(want)]);
  };
  num('sprint: 100 u at full stick, flat off-road (s)', '<= 9.0', 'sprint', 't100', 0, 9.0);
  num('run speed reached by (s)', '0.25', 'sprint', 'run_t', 0.15, 0.35);
  num('sprint starts after (s)', '1.0', 'sprint', 'sprint_t', 0.95, 1.15);
  num('sprint top speed reached by (s)', '1.0 + 0.4', 'sprint', 'top_t', 1.3, 1.6);
  num('sprint top speed (u/s)', '12.5', 'sprint', 'top', 12.4, 12.6);
  num('stopping from sprint: time (s)', '12.5/60 = 0.21', 'stop', 'time', 0.15, 0.3);
  num('walk at stick 0.7 (u/s)', '0.7 x 5.5 = 3.85', 'walk', 'speed', 3.75, 3.95);
  num('camera look-ahead at sprint (u)', 'max 2.5', 'sprint', 'look_max', 2.3, 2.5001);
  num('camera look-ahead at walk 0.7 (u)', '3.85 x 0.25 = 0.96', 'walk', 'look_max', 0.8, 1.1);
  num('camera FOV at sprint (deg)', '66', 'sprint', 'fov_max', 65.5, 66.1);
  num('turn 90 deg at run (s)', '90/540 = 0.167', 'turn_run', 't_yaw', 0.12, 0.21);
  num('turn 90 deg at walk (s)', '90/720 = 0.125', 'turn_walk', 't_yaw', 0.09, 0.17);
  num('turn 60 deg at sprint (s)', '60/300 = 0.2', 'turn_sprint60', 't_yaw', 0.15, 0.26);
  flag('sprint kept through a 60 deg turn', 'kept', 'turn_sprint60', 'sprint_after', true);
  flag('sprint lost on a 120 deg turn', 'lost', 'turn_sprint120', 'sprint_after', false);
  num('  ... how fast it is lost (s)', '< 0.25', 'turn_sprint120', 't_lost', 0, 0.1);
  flag('sprint lost when stick drops to 0.7', 'lost', 'sprint_slow', 'sprint_after', false);
  flag('sprint lost when blocked', 'lost', 'sprint_block', 'sprint_after', false);
  num('  ... speed after hitting the wall (u/s)', '~0', 'sprint_block', 'speed_after', 0, 0.5);
  num('dash distance (u)', '4.5 +/- 0.3', 'dash', 'dist', 4.2, 4.8);
  num('dash duration (s)', '<= 0.25', 'dash', 'dur', 0.18, 0.25);
  const pb = g('dash', 'pips_before'), pa = g('dash', 'pips_after'), du = g('dash', 'dur');
  const cost = pb - (pa - 0.6 * du);
  rows.push(['dash cost (pips; refill over the dash removed)', '1', Number.isFinite(cost) ? cost.toFixed(3) : 'missing', Math.abs(cost - 1) < 0.05]);
  flag('dash tries at 0 .1 .3 .4 .8 1.2 1.6 1.85 s (T accepted)', 'TFFTTFFT (lockout 0.35, 3 pips)', 'dash', 'tries', 'TFFTTFFT');
  num('i-frames: last sampled on at (s)', '< 0.18', 'dash', 'iframe_last', 0.14, 0.1801);
  num('i-frames: first sampled off at (s)', '>= 0.18', 'dash', 'iframe_off', 0.18, 0.22);
  num('camera FOV peak in a dash (deg)', '70', 'dash', 'fov_max', 69.5, 70.1);
  for (let i = 0; i < 4; i++) num(`dash ${i + 1} distance (u)`, '4.5 +/- 0.3', 'dash_each', 'dist', 4.2, 4.8, i);
  flag('dash into a wall 2 u ahead stops', 'stops', 'dash_wall', 'stopped', true);
  num('  ... distance covered (u)', '< 2.0', 'dash_wall', 'dist', 0.1, 2.0);
  flag('  ... hero not left inside it', 'false', 'dash_wall', 'hero_blocked', false);
  flag('dash toward water 2 u ahead stops', 'stops', 'dash_water', 'stopped', true);
  num('  ... distance covered (u)', '< 2.0', 'dash_water', 'dist', 0.1, 2.0);
  flag('  ... hero not left in water', 'false', 'dash_water', 'in_water', false);
  num('road run (u/s)', '11.4', 'road', 'run', 11.3, 11.5);
  num('road sprint (u/s)', '15.0', 'road', 'sprint', 14.8, 15.3);
  const kinds = Object.keys(relay.counts);
  rows.push(['relay message kinds seen', 'none new (none)', kinds.length ? kinds.join(',') : 'none', kinds.length === 0]);
  let ok = true;
  for (const [label, spec, got, good] of rows) {
    if (!good) ok = false;
    notes.push(`${good ? 'ok ' : 'BAD'} ${label}: ${got}  (spec ${spec})`);
  }
  return { ok: ok && c.errors.length === 0, notes };
}, true);

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
