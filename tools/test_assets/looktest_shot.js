#!/usr/bin/env node
// Load the build with --looktest args, print LOOKTEST console lines, screenshot once the stats line appears.
//   node tools/test_assets/looktest_shot.js out.png "--looktest=wide --looktest-seek=0.5" [WxH] [dsf] [maxSeconds]
// Needs: export NODE_PATH=/opt/npm-tools/node_modules:$NODE_PATH. Software WebGL: expect 2-4 fps.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = path.resolve(__dirname, '../..');
const [out, argStr = '--looktest', size = '844x390', dsf = '2', maxSecs = '240'] = process.argv.slice(2);
const [w, h] = size.split('x').map(Number);
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  const file = path.join(ROOT, path.normalize(decodeURIComponent(url.pathname)));
  if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) return res.writeHead(404).end();
  let body = fs.readFileSync(file);
  if (path.basename(file) === 'index.html') {
    body = body.toString().replace('"args":[]', `"args":${JSON.stringify(['--', ...argStr.split(/\s+/).filter(Boolean)])}`);
  }
  res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' }).end(body);
});

server.listen(0, '127.0.0.1', async () => {
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: Number(dsf) });
  const errors = [];
  let stats = false;
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    const t = m.text();
    if (/LOOKTEST|SCRIPT ERROR|Parse Error/.test(t)) console.log(`[${m.type()}]`, t.slice(0, 700));
    if (/LOOKTEST stats/.test(t)) stats = true;
    if ((m.type() === 'error' || /SCRIPT ERROR/.test(t)) && !t.startsWith('WebSocket') && !/Failed to load resource/.test(t)) errors.push(t);
  });
  await page.goto(`http://127.0.0.1:${server.address().port}/index.html?relay=ws://127.0.0.1:1`);
  const t0 = Date.now();
  while (!stats && Date.now() - t0 < Number(maxSecs) * 1000) await page.waitForTimeout(1000);
  await page.waitForTimeout(4000);
  await page.screenshot({ path: out, timeout: 180000 });
  console.log('PAGE', JSON.stringify(await page.evaluate(() => ({ css: [innerWidth, innerHeight], dpr: devicePixelRatio }))), 'stats', stats);
  await browser.close();
  server.close();
  for (const e of errors) console.log('ERROR', e.slice(0, 300));
  process.exit(errors.length || !stats ? 1 : 0);
});
