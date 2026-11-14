#!/usr/bin/env node
// Screenshots of the quest UI at 844x390, device scale 2: dialogue with a choice, the journal, the tracker
// during play and an inscription being read. Uses the game's `--questbot=shot-<name>` set-ups.
//   NODE_PATH=/opt/npm-tools/node_modules node tools/quest_shots.js OUTDIR [name ...]
const http = require('http'), fs = require('fs'), path = require('path');
const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..');
const OUT = process.argv[2] || '/tmp/quest-shots';
const names = process.argv.slice(3).length ? process.argv.slice(3) : ['dialogue', 'journal', 'tracker', 'inscription'];
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };
(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    let rel = decodeURIComponent(url.pathname);
    if (rel === '/') rel = '/index.html';
    const file = path.join(ROOT, path.normalize(rel));
    if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404).end(); return; }
    let body = fs.readFileSync(file);
    if (path.basename(file) === 'index.html') {
      const args = url.searchParams.getAll('arg');
      body = body.toString().replace('"args":[]', `"args":${JSON.stringify(['--', ...args])}`);
    }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' }).end(body);
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  for (const name of names) {
    const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
    const page = await browser.newPage({ viewport: { width: 844, height: 390 }, deviceScaleFactor: 2 });
    let ready = false;
    page.on('console', (m) => { if (m.text() === `SHOT ready ${name}`) ready = true; });
    await page.goto(`${base}/index.html?relay=ws://127.0.0.1:9&arg=--autoplay%3Dgather&arg=--questbot%3Dshot-${name}`);
    for (let i = 0; i < 240 && !ready; i++) await new Promise((r) => setTimeout(r, 1000));
    await new Promise((r) => setTimeout(r, 2500));
    await page.screenshot({ path: path.join(OUT, `${name}.png`) });
    console.log(ready ? 'shot' : 'NOT READY', name);
    await browser.close();
  }
  server.close();
})();
