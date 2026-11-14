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
// console line), --viewport=WxH (default 320x180), --dpr=N (device pixel ratio, default 1), --timeout=SECONDS (probe length), --shots=DIR (probe).
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

const opts = { dpr: 1, jobs: 1, verbose: false, viewport: '320x180', timeout: 300, probe: null, list: false };
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
  else if (a.startsWith('--dpr=')) opts.dpr = Number(a.slice(6));
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
// Precise performance.memory and a gc() the soak bot calls before it reads the JS heap (no effect on play).
const MEMFLAGS = ['--enable-precise-memory-info', '--js-flags=--expose-gc'];
// Sound running as on a phone after its first tap. Without it the page's audio context stays suspended, no
// sound ever ends, and the engine keeps a copy of every sound played (a headless artifact, not the game's).
const AUDIO_ON = ['--autoplay-policy=no-user-gesture-required'];

class Client {
  constructor(label, view = null) {
    this.label = label;
    this.view = view || { width: VW, height: VH, dpr: opts.dpr };
    this.lines = [];
    this.errors = [];
    this.t0 = Date.now();
    this.seed = null;
    // Once this pattern is seen the bot is done and quits; errors from the engine
    // shutting down after that are not the build's.
    this.stopRe = null;
    this.done = false;
  }

  async start(base, gameArgs, relays) {
    this.browser = await chromium.launch({ args: [...GL, ...MEMFLAGS, ...(this.view.audio || process.env.SOAK_AUDIO ? AUDIO_ON : [])] });
    // newPage on a fresh browser is a fresh profile: no save, no localStorage.
    this.page = await this.browser.newPage({ viewport: { width: this.view.width, height: this.view.height }, deviceScaleFactor: this.view.dpr });
    this.page.on('pageerror', (e) => { if (!this.done) this.errors.push(String(e).slice(0, 400)); });
    this.page.on('crash', () => { if (!this.done) this.errors.push('page crashed'); });
    this.page.on('console', (m) => {
      let text = m.text();
      if (/^SOAK (cycle|phase)=/.test(text)) {
        const mem = chromeMemory();
        text = `${text} pss_renderer=${mem.renderer || 0} pss_gpu=${mem['gpu-process'] || 0}`;
      }
      this.lines.push(text);
      const wasDone = this.done;
      if (this.stopRe && this.stopRe.test(text)) this.done = true;
      if (opts.verbose && !/^Blocked call to navigator\.vibrate|^The AudioContext/.test(text)) console.log(`  [${this.label} ${((Date.now() - this.t0) / 1000).toFixed(0)}s] ${text.slice(0, /^SOAK/.test(text) ? 2000 : 200)}`);
      // Noise that is the browser's business: an unreachable relay, and vibration before a tap.
      if (wasDone) return;
      if (/^WebSocket connection to|^Blocked call to navigator\.vibrate/.test(text)) return;
      if (m.type() === 'error' || /SCRIPT ERROR|Parse Error/.test(text)) this.errors.push(text.slice(0, 400));
    });
    // A save (JSON text) put in localStorage before the game boots, for scenarios that start from a fixture.
    if (this.seed) await this.page.addInitScript((t) => { if (!localStorage.getItem('ashgrave_save_v1')) localStorage.setItem('ashgrave_save_v1', t); }, this.seed);
    const q = new URLSearchParams();
    if (relays.length) q.set('relay', relays.join(','));
    // ?quality=safe|full for this session (a client's own .quality, else AG_QUALITY for every client).
    const quality = this.quality || process.env.AG_QUALITY;
    if (quality) q.set('quality', quality);
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

// Proportional memory (Pss, bytes) of this harness's Chromium processes by type, read from /proc
// (Linux only; {} elsewhere). With software WebGL the GPU process holds what a phone keeps in video memory.
function chromeMemory() {
  const out = {};
  try {
    const kids = {};
    for (const d of fs.readdirSync('/proc')) {
      if (!/^\d+$/.test(d)) continue;
      try {
        const st = fs.readFileSync(`/proc/${d}/stat`, 'utf8');
        const ppid = Number(st.slice(st.lastIndexOf(')') + 2).split(' ')[1]);
        (kids[ppid] = kids[ppid] || []).push(Number(d));
      } catch (e) { /* gone */ }
    }
    const stack = [process.pid];
    while (stack.length) {
      const p = stack.pop();
      for (const k of kids[p] || []) {
        stack.push(k);
        try {
          const cmd = fs.readFileSync(`/proc/${k}/cmdline`, 'utf8');
          if (!/chrom/i.test(cmd)) continue;
          const m = /--type=([\w-]+)/.exec(cmd);
          const type = m ? m[1] : 'browser';
          const pss = /^Pss:\s+(\d+) kB/m.exec(fs.readFileSync(`/proc/${k}/smaps_rollup`, 'utf8'));
          if (pss) out[type] = (out[type] || 0) + Number(pss[1]) * 1024;
        } catch (e) { /* gone */ }
      }
    }
  } catch (e) { /* not Linux */ }
  return out;
}

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

const GAME_LINE = /^(LAND|WORLD|TOUR|RESULT|GATHER|PVP|ACT1|QSAVE)/;
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

// ---- 2b. tower walls (world_bot.gd): the tower opens directly (--shot-when=towermap
// with no --shot only routes the land to the tower) and the bot works in logic steps.

const towerDone = (lines) => lineOf(lines, /^TOWERBOT DONE /) || '';
const towerNum = (l, k) => { const m = new RegExp(`\\b${k}=(\\d+)`).exec(l); return m ? Number(m[1]) : NaN; };

scenario('tower-walls', 'wall bot: walls drawn where blocked, duels stand fighters on floor, stress walks never inside or stuck', (ctx) => solo(ctx, {
  args: ['--shot-when=towermap', '--towerbot=walls'], finish: /^TOWERBOT DONE /, seconds: 900,
  verify: (lines) => {
    const l = towerDone(lines);
    const bad = ['inside', 'stuck', 'clip', 'spawn_bad', 'wall_mismatch', 'duel_inside', 'duel_stuck', 'thin_cross',
      'real_duel_stuck', 'real_mismatch', 'frame_inside', 'frame_stuck', 'frame_unstuck'].filter((k) => towerNum(l, k) !== 0);
    if (bad.length) return `nonzero ${bad.join(', ')}: ${l}`;
    if (!/ real=ok\b/.test(l)) return `the real duel did not run: ${l}`;
    if (!lines.some((x) => /^TOWERBOT frames /.test(x))) return 'the per-frame pass did not run';
    if (lines.some((x) => /^UNSTUCK /.test(x))) return `the safety net fired during the sweep: ${lineOf(lines, /^UNSTUCK /)}`;
    return null;
  },
}));

scenario('tower-unstuck', 'hero put inside walls is freed within 1s (UNSTUCK line), and unstuck() steps back', (ctx) => solo(ctx, {
  args: ['--shot-when=towermap', '--towerbot=net'], finish: /^TOWERBOT DONE /, seconds: 300,
  verify: (lines) => {
    const l = towerDone(lines);
    if (towerNum(l, 'net_bad') !== 0 || !(towerNum(l, 'net_ok') >= 4) || !/ manual=ok\b/.test(l)) return `safety net failed: ${l}`;
    const n = lines.filter((x) => /^UNSTUCK tier=\d+ from=.* why=inside/.test(x)).length;
    return n >= 4 ? null : `expected 4 UNSTUCK lines, saw ${n}`;
  },
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
  num('  ... distance covered (u; the shore is found in 0.5 u steps, so up to 2.5)', '<= 2.5', 'dash_water', 'dist', 0.1, 2.5);
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

// ---- 4c. world agility on the real paths: `--autoplay=gather --agility-real`. Nothing is cleared;
// the hero is put in a tree, a rock, a house and the tower base, slid along a house wall, dashed at
// obstacles, run through a duel next to an obstacle, and the manual Unstuck is tried. Slices of
// 1/60, 1/30 and 1/20 s of game time (see overworld_bot.gd, "Real-path movement test").
function parseAgReal(lines) {
  const out = {};
  for (const l of lines) {
    const m = /^AGREAL (\w+) (.*)$/.exec(l);
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

scenario('agility-real', 'world movement on the real paths: stuck in obstacles, slide, dash at obstacles, duel stand points, i-frames, manual Unstuck', async (ctx) => {
  const relay = await ctx.newRelay();
  const c = await ctx.client('bot');
  c.stopRe = /^AGREAL (done|fail)/;
  await c.start(ctx.base, ['--autoplay=gather', '--agility-real'], [relay.url]);
  const r = await waitUntil([c], () => c.find(/^AGREAL (done|fail)/), 900);
  const notes = errorNotes([c]);
  if (r !== 'ok') { notes.push(`no AGREAL done within 900s (${r})`); return { ok: false, notes }; }
  if (c.find(/^AGREAL fail/)) return { ok: false, notes: [...notes, c.find(/^AGREAL fail/)] };
  const a = parseAgReal(c.lines);
  const rows = [];
  const row = (label, spec, got, good) => rows.push([label, spec, String(got), !!good]);
  const n = (v) => Number(v);
  for (const t of a.trap || []) {
    const tag = `${t.kind} at ${t.fps} fps`;
    if (t.missing) { row(`stuck in ${tag}`, 'case exists', 'missing', false); continue; }
    row(`stuck in ${tag}: starts blocked, free within 1 s, one UNSTUCK`, 'free, t <= 1.0, 1',
      `blocked=${t.start_blocked} free=${t.free} t=${t.t} unstuck=${t.unstuck}`,
      t.start_blocked === 'true' && t.free === 'true' && n(t.t) <= 1.0 && n(t.unstuck) === 1);
  }
  const unstuckLines = c.lines.filter((l) => /^UNSTUCK land from=/.test(l)).length;
  const expectLines = (a.trap || []).length + (a.duel || []).reduce((s2, d) => s2 + n(d.unstuck || 0), 0) + (a.manual || []).reduce((s2, d) => s2 + n(d.count || 0), 0) + 1;
  row('console UNSTUCK land lines (traps + duel + manual)', `${expectLines - 1} to ${expectLines + 1}`, unstuckLines, unstuckLines >= expectLines - 1 && unstuckLines <= expectLines + 1);
  for (const s2 of a.slide || []) {
    const min = n(s2.deg) === 45 ? 0.6 : 0.4;
    row(`slide along a house wall at ${s2.deg} deg, ${s2.fps} fps: share of open-ground speed`, `>= ${min}`, `${s2.ratio} (wall ${s2.wall}, open ${s2.open})`, n(s2.open) > 2 && n(s2.ratio) >= min);
  }
  row('slide rows present', '6', (a.slide || []).length, (a.slide || []).length === 6);
  for (const d of a.dash_obstacle || []) {
    const L = n(d.dist);
    const tag = `dash at an obstacle ${d.dist} u ahead, ${d.fps} fps`;
    if (d.missing) { row(tag, 'case exists', 'missing', false); continue; }
    const moved = n(d.moved);
    const spent = n(d.pips_before) - n(d.pips_after);
    const refund = L < 0.5;
    row(`${tag}: distance moved`, refund ? '< 0.5' : `${(L - 0.15).toFixed(2)} to ${L.toFixed(2)}`,
      d.moved, refund ? (moved >= 0 && moved < 0.5) : (moved >= L - 0.15 && moved <= L + 0.02));
    row(`${tag}: pip`, refund ? 'refunded' : 'spent (about 1 less regen)',
      `before ${d.pips_before} after ${d.pips_after}`, refund ? spent < 0.3 : (spent > 0.6 && spent < 1.1));
    row(`${tag}: not left inside it`, 'false', d.inside, d.inside === 'false');
  }
  const xp = (a.xp || [])[0] || {};
  const x = (k) => n(xp[k]);
  row('agility XP per second: walk / run / sprint on road / dash-spam (run is the cap, 1.7)', 'sprint, dash <= run <= 1.7',
    `${xp.walk} / ${xp.run} / ${xp.sprint_road} / ${xp.dash_spam}`,
    x('run') > 0 && x('run') <= 1.71 && x('walk') <= x('run') && x('sprint_road') <= x('run') + 0.01 && x('dash_spam') <= x('run') + 0.01 && x('dash_spam') < 0.05);
  for (const d of a.duel || []) {
    if (d.missing) { row(`duel next to a ${d.kind}`, 'case exists', 'missing', false); continue; }
    row(`duel next to a ${d.kind}: hero free afterwards`, 'false', d.hero_blocked, d.hero_blocked === 'false');
    row(`duel next to a ${d.kind}: saved position free`, 'false', d.saved_blocked, d.saved_blocked === 'false');
  }
  const won = (a.duel || []).filter((d) => d.at_start === 'false' && n(d.unstuck) === 1).length;
  row('duels that ended on a blocked stand point and were moved out', '>= 1', won, won >= 1);
  for (const d of a.iframes || []) {
    const at = n(d.duel_at);
    const dt = 1 / n(d.fps);
    row(`dash through a foe at ${d.fps} fps: no duel before 0.18 s, one right after`, `0.18 to ${(0.18 + dt + 0.005).toFixed(3)}`, d.duel_at, d.dash_ok === 'true' && at >= 0.18 - 1e-6 && at <= 0.18 + dt + 0.005);
  }
  const m = (a.manual || [])[0] || {};
  if (m.missing) row('manual Unstuck exists', 'yes', 'missing', false);
  else {
    row('manual Unstuck refused with a challenge pending', 'true', m.refuse_pvp, m.refuse_pvp === 'true');
    row('manual Unstuck refused right after a fight', 'true', m.refuse_fight, m.refuse_fight === 'true');
    row('manual Unstuck refused with a foe close', 'true', m.refuse_foe, m.refuse_foe === 'true');
    row('manual Unstuck moves the hero (u), to a free spot', '>= 2', `${m.moved} free=${m.free}`, m.first_ok === 'true' && n(m.moved) >= 2 && m.free === 'true');
    row('manual Unstuck on cooldown at 0.5 s and 9.5 s', 'refused', `${m.second_ok} / ${m.at_9_5}`, m.second_ok === 'false' && m.at_9_5 === 'false');
    row('manual Unstuck allowed again at 10.1 s and moves (u)', '>= 2', `${m.at_10_1} ${m.moved_again} free=${m.free_again}`, m.at_10_1 === 'true' && n(m.moved_again) >= 2 && m.free_again === 'true');
  }
  const kinds = Object.keys(relay.counts);
  row('relay message kinds seen', 'none', kinds.length ? kinds.join(',') : 'none', kinds.length === 0);
  let ok = true;
  for (const [label, spec, got, good] of rows) {
    if (!good) ok = false;
    notes.push(`${good ? 'ok ' : 'BAD'} ${label}: ${got}  (want ${spec})`);
  }
  return { ok: ok && c.errors.length === 0, notes };
}, true);

// ---- 4d. memory soak (soak_bot.gd): `--soak` plays the real journey in cycles (roam five biomes with
// sprint and dash, wild duels won and lost, gathering, every HUD screen, fast travel, the tower: tier 1,
// a pack duel on tier 2, a death on tier 3) for at least 5 cycles and 12 minutes of game time, and prints
// one SOAK cycle line of memory readings per cycle at the same spot (idle at the hearth). Cycle 1 is the
// warm-up; growth is measured from cycle 2 to the last. Thresholds are in docs/PERF_BUDGET.md.
const SOAK_LIMITS = {
  // per cycle, after the warm-up
  heap: 2 * 1048576, nc: 25, orphan: 0, tex: 256 * 1024, oc: 150, res: 2,
  // JS heap after gc, and the Chromium renderer process (Pss; includes the JS heap and compiled wasm)
  // (with sound running, a playback copy of a sound may be alive at a reading: single readings jump by ~5-18 MB)
  js: 10 * 1048576, pss_renderer: 20 * 1048576,
  // absolute ceilings over the whole run (wasm heap; Godot video memory at the check's 320x180 viewport)
  peakHeap: 128 * 1048576, peakVid: 30 * 1048576,
  // the title on an iPhone-shaped page (844x390 CSS pixels at devicePixelRatio 3): Godot video memory
  phoneVid: 48 * 1048576,
};
function parseSoak(lines) {
  const rows = [];
  for (const l of lines) {
    const m = /^SOAK (cycle|phase)=(\S+)(?: cycle=(\d+))? (.*)$/.exec(l);
    if (!m) continue;
    const kv = { kind: m[1], name: m[2] };
    for (const part of m[4].split(' ')) {
      const e = part.indexOf('=');
      if (e > 0) kv[part.slice(0, e)] = isNaN(Number(part.slice(e + 1))) ? part.slice(e + 1) : Number(part.slice(e + 1));
    }
    kv.cycle = m[1] === 'cycle' ? Number(m[2]) : Number(m[3]);
    rows.push(kv);
  }
  return rows;
}
function soakVerdict(lines) {
  const rows = parseSoak(lines);
  const cyc = rows.filter((r) => r.kind === 'cycle');
  const notes = [];
  const mb = (b) => (b / 1048576).toFixed(1);
  notes.push('cycle  game_s  heap_MB  js_MB  rend_MB  gpu_MB  objects  nodes  orphans  resources  tex_MB  buf_MB  vid_MB  draws  prims  meshkit  results');
  for (const r of cyc) notes.push(`${String(r.cycle).padStart(5)}  ${String(r.gt).padStart(6)}  ${mb(r.heap).padStart(7)}  ${mb(r.js).padStart(5)}  ${mb(r.pss_renderer || 0).padStart(7)}  ${mb(r.pss_gpu || 0).padStart(6)}  ${String(r.oc).padStart(7)}  ${String(r.nc).padStart(5)}  ${String(r.orphan).padStart(7)}  ${String(r.res).padStart(9)}  ${mb(r.tex).padStart(6)}  ${mb(r.buf).padStart(6)}  ${mb(r.vid).padStart(6)}  ${String(r.dc).padStart(5)}  ${String(r.prim).padStart(6)}  ${String(r.meshkit).padStart(7)}  ${r.results || ''}`);
  for (const ph of ['title', 'land', 'screens', 'tower', 'duel']) {
    const p = rows.filter((r) => r.kind === 'phase' && r.name === ph);
    if (p.length) notes.push(`phase ${ph.padEnd(7)} heap ${p.map((r) => mb(r.heap)).join(' ')} | nodes ${p.map((r) => r.nc).join(' ')} | tex ${p.map((r) => mb(r.tex)).join(' ')} | vid ${p.map((r) => mb(r.vid)).join(' ')} | draws ${p.map((r) => r.dc).join(' ')}`);
  }
  const grows = lines.filter((l) => /^SOAKGROW /.test(l));
  notes.push(`heap grew ${grows.length} time(s): ${grows.map((l) => l.slice(9)).join('; ')}`);
  const bad = [];
  if (cyc.length < 5) bad.push(`only ${cyc.length} cycle lines (want 5)`);
  const last = cyc[cyc.length - 1];
  if (last && last.gt < 720) bad.push(`only ${last.gt} s of game time (want 720)`);
  if (cyc.length >= 3) {
    const a = cyc[1];
    const n = cyc.length - 2;
    for (const k of ['heap', 'js', 'pss_renderer', 'nc', 'orphan', 'tex', 'oc', 'res']) {
      if (!(k in a) || !(k in last)) continue;
      const per = (last[k] - a[k]) / n;
      const ok = per <= SOAK_LIMITS[k];
      const bytes = ['heap', 'tex', 'js', 'pss_renderer'].includes(k);
      notes.push(`${ok ? 'ok ' : 'BAD'} growth per cycle ${k}: ${bytes ? mb(per) + ' MB' : per.toFixed(1)} (limit ${bytes ? mb(SOAK_LIMITS[k]) + ' MB' : SOAK_LIMITS[k]})`);
      if (!ok) bad.push(`${k} grows ${per.toFixed(0)} per cycle`);
    }
  }
  const peakHeap = Math.max(...rows.map((r) => r.peak || 0));
  const peakVid = Math.max(...rows.map((r) => r.vid || 0));
  notes.push(`${peakHeap <= SOAK_LIMITS.peakHeap ? 'ok ' : 'BAD'} peak wasm heap ${mb(peakHeap)} MB (ceiling ${mb(SOAK_LIMITS.peakHeap)})`);
  notes.push(`${peakVid <= SOAK_LIMITS.peakVid ? 'ok ' : 'BAD'} peak video memory ${mb(peakVid)} MB (ceiling ${mb(SOAK_LIMITS.peakVid)})`);
  if (peakHeap > SOAK_LIMITS.peakHeap) bad.push('heap over ceiling');
  if (peakVid > SOAK_LIMITS.peakVid) bad.push('video memory over ceiling');
  return { bad, notes };
}

scenario('perf-soak', 'memory soak: 5+ cycles of the real journey; growth per cycle and peaks under the limits in docs/PERF_BUDGET.md', async (ctx) => {
  const relay = await ctx.newRelay();
  // First the title on a phone-shaped page at devicePixelRatio 3: the canvas and full-size buffers.
  const ph = await ctx.client('phone', { width: 844, height: 390, dpr: 3, audio: true });
  ph.stopRe = /^SOAK done/;
  await ph.start(ctx.base, ['--soak=title'], [relay.url]);
  await waitUntil([ph], () => ph.find(/^SOAK done/), 300);
  const phRow = parseSoak(ph.lines).find((r) => r.name === 'title');
  const phoneNotes = errorNotes([ph]);
  let phoneOk = !!phRow && ph.errors.length === 0;
  if (phRow) {
    phoneOk = phoneOk && phRow.vid <= SOAK_LIMITS.phoneVid;
    phoneNotes.push(`${phRow.vid <= SOAK_LIMITS.phoneVid ? 'ok ' : 'BAD'} phone title (844x390 at dpr 3): video ${(phRow.vid / 1048576).toFixed(1)} MB (ceiling ${(SOAK_LIMITS.phoneVid / 1048576).toFixed(0)}), textures ${(phRow.tex / 1048576).toFixed(1)} MB, buffers ${(phRow.buf / 1048576).toFixed(1)} MB, heap ${(phRow.heap / 1048576).toFixed(1)} MB, renderer ${((phRow.pss_renderer || 0) / 1048576).toFixed(0)} MB, gpu process ${((phRow.pss_gpu || 0) / 1048576).toFixed(0)} MB`);
  } else phoneNotes.push('FAIL: no title reading from the phone-shaped page');
  await ph.close();
  const c = await ctx.client('bot', { width: VW, height: VH, dpr: opts.dpr, audio: true });
  c.stopRe = /^SOAK (done|fail)/;
  await c.start(ctx.base, ['--soak'], [relay.url]);
  const r = await waitUntil([c], () => c.find(/^SOAK (done|fail)/), 3600);
  const notes = errorNotes([c]);
  if (r !== 'ok') notes.push(`no SOAK done within 3600s (${r})`);
  if (c.find(/^SOAK fail/)) notes.push(c.find(/^SOAK fail/));
  const v = soakVerdict(c.lines);
  if (process.env.SOAK_LOG) fs.writeFileSync(process.env.SOAK_LOG, c.lines.join('\n'));
  return { ok: phoneOk && r === 'ok' && !c.find(/^SOAK fail/) && v.bad.length === 0 && c.errors.length === 0, notes: [...phoneNotes, ...notes, ...v.notes, ...v.bad.map((b) => `FAIL: ${b}`)] };
}, true);

// ---- 4c. quality levels (game/scripts/quality.gd)

// Plays the land, a tower duel and a standalone duel (and, in safe, the tower itself) at each level with --perflog, which
// prints the levers read back from the engine (q, scale3d, shadowed lights, sky radiance) next to draw calls and
// memory. Safe must run clean with the levers in force; full is the reference for the side-by-side table.
const QUALITY_RUNS = [
  ['land', ['--autoplay=gather'], /^GATHER /, 150],
  ['tower duel', ['--autoplay=x', '--kind=guardian', '--floor=1'], /^RESULT /, 200],
  ['duel', ['--autoplay=x', '--wild=thrall'], /^RESULT /, 150],
  ['tower', ['--autoplay=tour'], /^WORLD tier=2 /, 300],
];
function perfRows(lines) {
  const rows = [];
  for (const l of lines) {
    if (!l.startsWith('PERFLOG ')) continue;
    const kv = {};
    for (const part of l.slice(8).split(' ')) {
      const e = part.indexOf('=');
      if (e > 0) kv[part.slice(0, e)] = isNaN(Number(part.slice(e + 1))) ? part.slice(e + 1) : Number(part.slice(e + 1));
    }
    if ('q' in kv) rows.push(kv);
  }
  return rows;
}
scenario('quality', 'safe mode: land, tower duel, duel and tower play clean with the levers in force; full and safe side by side', async (ctx) => {
  const notes = [];
  let ok = true;
  const table = {};
  for (const level of ['safe', 'full']) {
    for (const [what, args, finish, secs] of QUALITY_RUNS) {
      if (level === 'full' && what === 'tower') continue;
      const relay = await ctx.newRelay();
      const c = await ctx.client(`${level} ${what}`);
      c.quality = level;
      c.stopRe = finish;
      await c.start(ctx.base, [...args, '--perflog'], [relay.url]);
      const r = await waitUntil([c], () => c.find(finish), secs);
      notes.push(...errorNotes([c]));
      if (r !== 'ok') { ok = false; notes.push(`FAIL: ${level} ${what}: no ${finish} within ${secs}s (${r})`); }
      const rows = perfRows(c.lines).filter((x) => x.draw > 0);
      const rest = rows.slice(Math.min(2, rows.length - 1));
      if (!rest.length) { ok = false; notes.push(`FAIL: ${level} ${what}: no PERFLOG lines`); await c.close(); continue; }
      const wrong = rest.filter((x) => x.q !== level || x.textures !== (level === 'full' ? 1 : 0) || x.models !== (level === 'full' ? 1 : 0));
      const scene = rest.filter((x) => x.dirlights > 0);
      const want = level === 'safe' ? 0.75 : 1.0;
      const badScale = rest.filter((x) => Math.abs(x.scale3d - want) > 0.011);
      const badShadow = scene.filter((x) => (level === 'safe' ? x.shadowed !== 0 : x.shadowed < 1));
      const badRad = scene.filter((x) => String(x.radiance).split(',').some((v) => Number(v) !== (level === 'safe' ? 1 : 3)));
      const problems = [];
      if (wrong.length) problems.push(`level or gates wrong in ${wrong.length} lines (${wrong[0].q})`);
      if (badScale.length) problems.push(`3D scale ${badScale[0].scale3d}, wanted ${want}`);
      if (!scene.length) problems.push('no directional light seen');
      if (badShadow.length) problems.push(`shadowed lights ${badShadow[0].shadowed} at ${level}`);
      if (badRad.length) problems.push(`sky radiance ${badRad[0].radiance} at ${level}`);
      if (problems.length) { ok = false; notes.push(`FAIL: ${level} ${what}: ${problems.join('; ')}`); }
      const mean = (k) => rest.reduce((a, x) => a + x[k], 0) / rest.length;
      const mx = (k) => Math.max(...rest.map((x) => x[k]));
      table[`${what}|${level}`] = { draw: mean('draw'), prim: mean('prim'), tex: mx('tex'), vid: mx('vid'), heap: mx('heap'), n: rest.length, scale: rest[0].scale3d, shadowed: mx('shadowed'), radiance: rest[0].radiance };
      await c.close();
    }
  }
  const mb = (b) => (b / 1048576).toFixed(1);
  notes.push('phase        level  draws   prims   tex_MB  vid_MB  heap_MB  scale3d  shadowed  radiance  samples');
  for (const [key, t] of Object.entries(table).sort()) {
    const [what, level] = key.split('|');
    notes.push(`${what.padEnd(12)} ${level.padEnd(5)}  ${t.draw.toFixed(0).padStart(5)}  ${t.prim.toFixed(0).padStart(6)}  ${mb(t.tex).padStart(6)}  ${mb(t.vid).padStart(6)}  ${mb(t.heap).padStart(7)}  ${t.scale.toFixed(2).padStart(7)}  ${String(t.shadowed).padStart(8)}  ${String(t.radiance).padStart(8)}  ${t.n}`);
  }
  return { ok, notes };
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

// ---- 3b. Act 1 quest bot (docs/story/ACT1.md) and old-save compatibility

// Plays Act 1 from a fresh save through the real talk, kill, find and win hooks (game/scripts/overworld_bot.gd,
// world_bot.gd). Two runs, so that every choice is taken once: --pick=0 then --pick=1.
scenario('act1', 'quest bot plays Act 1 start to finish: every quest started and completed in order, text fits its boxes', async (ctx) => {
  const notes = [];
  let ok = true;
  for (const pick of [0, 1]) {
    const res = await solo(ctx, {
      args: ['--autoplay=gather', '--questbot=act1', `--pick=${pick}`], finish: /^ACT1 (DONE|FAILED)/, seconds: 1500,
      verify: (lines) => {
        const bad = lines.filter((l) => /^ACT1 FAIL /.test(l));
        if (bad.length) return bad.slice(0, 3).join(' | ');
        if (!lines.some((l) => /^ACT1 DONE quests=12\/12 /.test(l))) return 'did not finish 12 of 12 Act 1 quests';
        const started = lines.filter((l) => /^QUEST start /.test(l)).length;
        const done = lines.filter((l) => /^QUEST done /.test(l)).length;
        if (started !== 12 || done !== 12) return `quest log: ${started} started, ${done} done`;
        const order = lines.filter((l) => /^QUEST done /.test(l)).map((l) => l.split(' ')[2]);
        if (order.indexOf('a1_hand') < order.indexOf('oath') || order.indexOf('a1_hand') < order.indexOf('a1_thirty_first')) return 'a1_hand completed before its requirements';
        if (order.indexOf('a1_stair') < order.indexOf('a1_hand')) return 'a1_stair completed before a1_hand';
        if (order.indexOf('a1_bone') < order.indexOf('forge')) return 'a1_bone completed before forge';
        return null;
      },
    });
    ok = ok && res.ok;
    notes.push(`pick ${pick}: ${res.ok ? 'ok' : 'FAILED'}`);
    notes.push(...res.notes);
    if (!res.ok) break;
  }
  return { ok, notes };
}, true);

// Loads saves exported from Build 13 at several points in the five old quests and checks that each quest is at
// the same step with the same text, and that the open ones can still be finished.
scenario('quest-save', 'saves made on the previous build keep their quest progress step for step', async (ctx) => {
  const dir = path.join(ROOT, 'tools', 'fixtures');
  const texts = JSON.parse(fs.readFileSync(path.join(dir, 'old_step_texts.json'), 'utf8'));
  const notes = [];
  let ok = true;
  for (const f of fs.readdirSync(dir).filter((n) => /^old-.*\.json$/.test(n)).sort()) {
    const raw = fs.readFileSync(path.join(dir, f), 'utf8');
    const save = JSON.parse(raw);
    const relay = await ctx.newRelay();
    const c = await ctx.client('save');
    c.seed = raw;
    c.stopRe = /^QSAVE END/;
    await c.start(ctx.base, ['--questbot=save'], [relay.url]);
    const r = await waitUntil([c], () => c.find(/^QSAVE END/), 150);
    const problems = [...errorNotes([c])];
    if (r !== 'ok') problems.push(`no QSAVE END (${r})`);
    else {
      for (const id of ['forge', 'line', 'poach', 'mire', 'oath']) {
        const want = save.quests[id];
        const got = c.lines.find((l) => l.startsWith(`QSAVE state ${id} `));
        if (!want) { if (!/ none$/.test(got || '')) problems.push(`${id}: expected no entry, got ${got}`); continue; }
        const m = (got || '').match(/step=(\d+) count=(\d+) done=(\w+) text=(.*)$/);
        if (!m) { problems.push(`${id}: no state line`); continue; }
        if (Number(m[1]) !== want.step || Number(m[2]) !== want.count || (m[3] === 'true') !== want.done) problems.push(`${id}: saved step ${want.step}/${want.count}/${want.done}, loaded ${m[1]}/${m[2]}/${m[3]}`);
        const wantText = want.done ? 'Complete' : texts[id][want.step];
        if (m[4] !== wantText) problems.push(`${id}: step text changed: ${m[4].slice(0, 50)}`);
        if (!want.done && !c.lines.some((l) => l.startsWith(`QSAVE finished ${id} done=true`))) problems.push(`${id}: could not be finished from step ${want.step}`);
      }
      const gl = c.lines.find((l) => l.startsWith('QSAVE gold='));
      if (!gl || !gl.startsWith(`QSAVE gold=${save.gold} `)) problems.push(`gold changed: ${gl}`);
      if (c.lines.some((l) => /^QSAVE state \w+ none/.test(l)) === false && false) problems.push('x');
    }
    await c.close();
    notes.push(`${f}: ${problems.length ? 'FAILED' : 'ok'}`);
    for (const p of problems) { notes.push(`  ${p}`); ok = false; }
  }
  return { ok, notes };
});

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
    client: async (label, view) => { const c = new Client(label, view); clients.push(c); return c; },
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
