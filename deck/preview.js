const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

async function main() {
  const dir = path.join(__dirname, 'slides');
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.html')).sort();
  const browser = await chromium.launch();
  // 720pt x 405pt => at 96dpi (1pt=1.333px) ~ 960x540
  const page = await browser.newPage({ viewport: { width: 960, height: 540 }, deviceScaleFactor: 2 });
  fs.mkdirSync(path.join(__dirname, 'previews'), { recursive: true });
  for (const f of files) {
    await page.goto('file://' + path.join(dir, f));
    const out = path.join(__dirname, 'previews', f.replace('.html', '.png'));
    await page.screenshot({ path: out });
    console.log('rendered', f);
  }
  await browser.close();
}
main().catch(e => { console.error(e); process.exit(1); });
