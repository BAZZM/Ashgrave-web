#!/usr/bin/env node
// Load the built game in headless Chromium and fail on script errors.
//
//   node tools/smoke.js [screenshot.png] [query-string]
//
// e.g. node tools/smoke.js /tmp/shot.png "relay=ws://127.0.0.1:9001"
// Needs Playwright with Chromium. Uses software WebGL, so expect 2-4 fps.
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = path.resolve(__dirname, '..');
const shot = process.argv[2] || path.join(os.tmpdir(), 'ashgrave-smoke.png');
const query = process.argv[3] || '';
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };

const server = http.createServer((req, res) => {
  const file = path.join(ROOT, path.normalize(decodeURIComponent(req.url.split('?')[0])));
  if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404).end();
    return;
  }
  res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});

server.listen(0, '127.0.0.1', async () => {
  const errors = [];
  const browser = await chromium.launch({
    args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
  });
  const page = await browser.newPage({ viewport: { width: 960, height: 540 }, deviceScaleFactor: 1 });
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    const text = m.text();
    // A relay that cannot be reached is the network's business, not the build's.
    if (text.startsWith('WebSocket connection to')) return;
    if (m.type() === 'error' || /SCRIPT ERROR|Parse Error/.test(text)) errors.push(text);
  });
  await page.goto(`http://127.0.0.1:${server.address().port}/index.html?${query}`);
  await page.waitForTimeout(20000);
  // Tap past the title screen.
  for (let i = 0; i < 2; i++) {
    await page.mouse.click(480, 300);
    await page.waitForTimeout(3000);
  }
  await page.screenshot({ path: shot });
  await browser.close();
  server.close();
  for (const e of errors) console.log('ERROR', e.slice(0, 400));
  console.log(errors.length ? `FAILED with ${errors.length} error(s)` : `ok, screenshot at ${shot}`);
  process.exit(errors.length ? 1 : 0);
});
