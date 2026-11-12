#!/usr/bin/env node
// Load the build with game args, print ASSETTEST console lines, take a screenshot.
//   node tools/test_assets/shot.js out.png "--assettest=0.25" [WxH] [dsf] [seconds]
// Needs: export NODE_PATH=/opt/npm-tools/node_modules:$NODE_PATH (or tools/node_modules).
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = path.resolve(__dirname, '../..');
const [out, argStr = '--assettest', size = '844x390', dsf = '3', secs = '45'] = process.argv.slice(2);
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
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    const t = m.text();
    if (/ASSETTEST|SCRIPT ERROR|Parse Error|WebGL|GL_|texture|renderer/i.test(t) && !t.startsWith('WebSocket')) console.log(`[${m.type()}]`, t.slice(0, 300));
    if (m.type() === 'error' && !t.startsWith('WebSocket') && !/Failed to load resource/.test(t)) errors.push(t);
  });
  await page.goto(`http://127.0.0.1:${server.address().port}/index.html?relay=ws://127.0.0.1:1`);
  await page.waitForTimeout(Number(secs) * 1000);
  await page.screenshot({ path: out });
  const gl = await page.evaluate(() => {
    const c = document.querySelector('canvas');
    return { canvas: [c.width, c.height], css: [innerWidth, innerHeight], dpr: devicePixelRatio };
  });
  console.log('PAGE', JSON.stringify(gl));
  await browser.close();
  server.close();
  for (const e of errors) console.log('ERROR', e.slice(0, 300));
  process.exit(errors.length ? 1 : 0);
});
