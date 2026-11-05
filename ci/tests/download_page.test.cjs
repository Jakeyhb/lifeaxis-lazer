const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '../..');
const screenshotDirectory = path.join(root, 'build/download-preview/review');
const origin = 'https://updates.lifeaxis.fun';
const fixture = {
  versionCode: 9,
  versionName: '0.0.0-test',
  apkUrl: `${origin}/lazer/Lazer-0.0.0-test-9-universal.apk`,
  notes: '测试夹具：此处不是正式发布版本。\n新增应用内更新与安装前校验。',
  mandatory: false,
  sha256: 'a'.repeat(64),
  sizeBytes: 76543210,
  packageName: 'fun.lifeaxis.lazer',
  minSdk: 26,
  abis: ['armeabi-v7a', 'arm64-v8a'],
};
const assets = {
  'icon.png': 'assets/app_icon.png',
  'mascot.png': 'docs/images/mascot.png',
  'MiSans-Regular.ttf': 'assets/fonts/MiSans-Regular.ttf',
};
const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript',
  '.png': 'image/png', '.ttf': 'font/ttf' };

async function main() {
  fs.mkdirSync(screenshotDirectory, { recursive: true });
  const browser = await chromium.launch({ headless: true });
  try {
    for (const [label, viewport] of Object.entries({
      desktop: { width: 1440, height: 1000 }, mobile: { width: 390, height: 844 },
    })) {
      const context = await browser.newContext({ viewport, deviceScaleFactor: 1 });
      const page = await context.newPage();
      let mode = 'success';
      let manifest = { ...fixture };
      let requests = [];
      await page.route('**/*', async (route) => {
        const url = new URL(route.request().url());
        requests.push(url);
        assert.equal(url.origin, origin);
        assert.ok(url.pathname.startsWith('/lazer/'), 'must never read root version.json');
        const filename = url.pathname.slice('/lazer/'.length) || 'index.html';
        if (filename === 'version.json') {
          assert.deepEqual([...url.searchParams.keys()], ['t']);
          return route.fulfill({ status: mode === 'failure' ? 503 : 200,
            contentType: 'application/json', body: JSON.stringify(manifest) });
        }
        const file = path.join(root, assets[filename] || `release/site/${filename}`);
        assert.ok(fs.existsSync(file), `unexpected request: ${url}`);
        return route.fulfill({ contentType: types[path.extname(file)], body: fs.readFileSync(file) });
      });
      await page.goto(`${origin}/lazer/`);
      await page.waitForFunction(() => document.getElementById('apk-download').hasAttribute('href'));
      await page.evaluate(() => document.fonts.ready);
      assert.equal(await page.locator('#apk-download').getAttribute('href'), fixture.apkUrl);
      assert.match(await page.locator('#version').innerText(), /0\.0\.0-test/);
      assert.match(await page.locator('#requirements').innerText(), /Android 8\.0/);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
      await page.screenshot({ path: path.join(screenshotDirectory, `${label}.png`), fullPage: true, animations: 'disabled' });

      manifest = { ...fixture, notes: '<img src=x onerror="window.compromised=true">' };
      await page.reload();
      await page.waitForFunction(() => document.getElementById('apk-download').hasAttribute('href'));
      assert.equal(await page.locator('#notes').innerText(), manifest.notes);
      assert.equal(await page.locator('#notes img').count(), 0);
      assert.equal(await page.evaluate(() => window.compromised), undefined);

      manifest = { ...fixture, apkUrl: `${origin}/zaice/wrong.apk` };
      await page.reload();
      await page.waitForSelector('#retry:visible');
      assert.equal(await page.locator('#apk-download').getAttribute('href'), null);

      mode = 'failure';
      await page.reload();
      await page.waitForSelector('#retry:visible');
      assert.equal(await page.locator('#apk-download').getAttribute('aria-disabled'), 'true');
      if (label === 'mobile') {
        await page.screenshot({ path: path.join(screenshotDirectory, 'mobile-failure.png'), fullPage: true, animations: 'disabled' });
      }
      mode = 'success';
      manifest = { ...fixture };
      await page.locator('#retry').click();
      await page.waitForFunction(() => document.getElementById('apk-download').hasAttribute('href'));
      assert.ok(requests.filter((url) => url.pathname.endsWith('/version.json')).length >= 5);
      await context.close();
      console.log(`${label}: layout, relative manifest, safe text, trust boundary, failure and retry passed`);
    }
  } finally {
    await browser.close();
  }
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
