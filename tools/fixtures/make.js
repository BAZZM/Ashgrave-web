#!/usr/bin/env node
// Exports save fixtures from the OLD (pre-quest-data) build: seeds localStorage with a hand-made
// save at a point in one of the five original quests, lets the build load, migrate and save it,
// and writes what the build itself stored. Run once against Build 13; the files are committed.
//   NODE_PATH=/opt/npm-tools/node_modules node tools/fixtures/make.js
const http = require('http'), fs = require('fs'), path = require('path');
const { chromium } = require('playwright');
const ROOT = path.resolve(__dirname, '..', '..');
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };
const q = (step, count = 0, done = false) => ({ step, count, done });
const done = q(0, 0, true);
const base = { gold: 25, level: 5, skills_seeded: true, tutorial_done: true };
const FIX = {
  'old-forge-started': { ...base, mats: { copper_ore: 2 }, quests: { forge: q(0) } },
  'old-line-step1': { ...base, mats: { meal_trout: 1 }, quests: { forge: done, line: q(1) } },
  'old-poach-kills': { ...base, quests: { poach: q(0, 2) } },
  'old-poach-choose': { ...base, quests: { poach: q(1) } },
  'old-mire-hexer': { ...base, mats: { bogroot: 0 }, quests: { forge: done, mire: q(2) } },
  'old-oath-altar': { ...base, quests: { line: done, oath: q(1) } },
  'old-oath-choose': { ...base, flags: { poach: 'tally' }, quests: { poach: done, oath: q(2) } },
  'old-all-done': { ...base, gold: 900, relics: [1], best_floor: 2, unlocked: 2, flags: { poach: 'bribe', oath: 'end' },
    quests: { forge: done, line: done, poach: done, mire: done, oath: done } },
};
(async () => {
  const server = http.createServer((req, res) => {
    let rel = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (rel === '/') rel = '/index.html';
    const file = path.join(ROOT, path.normalize(rel));
    if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404).end(); return; }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base_url = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  for (const [name, seed] of Object.entries(FIX)) {
    const page = await browser.newPage({ viewport: { width: 320, height: 180 } });
    await page.addInitScript((s) => { if (!localStorage.getItem('ashgrave_save_v1')) localStorage.setItem('ashgrave_save_v1', JSON.stringify(s)); }, seed);
    await page.goto(base_url + '/index.html?relay=ws://127.0.0.1:9');
    let saved = null;
    for (let i = 0; i < 90 && !saved; i++) {
      await new Promise((r) => setTimeout(r, 1000));
      if (i === 25 || i === 45) await page.mouse.click(160, 100);
      const t = await page.evaluate(() => localStorage.getItem('ashgrave_save_v1'));
      const j = t && JSON.parse(t);
      if (j && j.stamp > 0) saved = j;
    }
    await page.close();
    if (!saved) { console.error('no save written for', name); continue; }
    fs.writeFileSync(path.join(__dirname, name + '.json'), JSON.stringify(saved));
    console.log(name, 'quests=' + JSON.stringify(saved.quests), 'flags=' + JSON.stringify(saved.flags));
  }
  await browser.close();
  server.close();
})();
