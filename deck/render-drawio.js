const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', 'docs', 'diagrams', 'drawio');
const OUT = path.join(__dirname, '..', 'docs', 'diagrams', 'hi');

const FILES = [
  '1-end-to-end-architecture.drawio',
  '2-grounding-chain.drawio',
  '3-runtime-sequence.drawio',
  '4-consulting-reuse.drawio',
];

async function main() {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch(process.platform === 'darwin' ? { channel: 'chrome' } : {});
  const page = await browser.newPage({ viewport: { width: 1400, height: 900 }, deviceScaleFactor: 3 });

  for (const f of FILES) {
    const xml = fs.readFileSync(path.join(SRC, f), 'utf8');
    const cfg = { xml, nav: false, resize: true, border: 24, 'toolbar-nohide': false };
    const dataAttr = JSON.stringify(cfg).replace(/&/g, '&amp;').replace(/'/g, '&#39;').replace(/"/g, '&quot;');
    const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><style>html,body{margin:0;padding:0;background:#ffffff;}</style></head><body><div class="mxgraph" style="background:#ffffff;" data-mxgraph="${dataAttr}"></div></body></html>`;
    await page.setContent(html, { waitUntil: 'domcontentloaded' });
    await page.addScriptTag({ url: 'https://viewer.diagrams.net/js/viewer-static.min.js' });
    await page.waitForSelector('.mxgraph svg', { timeout: 20000 });
    await page.waitForTimeout(500);
    const el = await page.$('.mxgraph');
    const out = path.join(OUT, f.replace('.drawio', '.png'));
    await el.screenshot({ path: out });
    console.log('rendered', out);
  }
  await browser.close();
}
main().catch(e => { console.error('ERR', e.message); process.exit(1); });
