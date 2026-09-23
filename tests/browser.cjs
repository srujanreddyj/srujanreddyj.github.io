const assert = require('node:assert/strict');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const base = process.env.SITE_URL || 'http://127.0.0.1:4173';
(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext({ viewport: { width: 1440, height: 1100 } });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(base);
    await page.locator('.discovery-card').first().waitFor();
    assert.equal(await page.locator('.discovery-card').count(), 4);
    assert.equal(await page.locator('.selected-entry').count(), 3);
    assert.equal(await page.locator('.reader-footer').isVisible(), true);
    await page.screenshot({ path: '/private/tmp/site-home-desktop.png', fullPage: true });
    await page.getByRole('button', { name: 'Switch to dark theme' }).click();
    assert.equal(await page.locator('html').getAttribute('data-theme'), 'dark');
    await page.reload();
    assert.equal(await page.locator('html').getAttribute('data-theme'), 'dark');
    await page.screenshot({ path: '/private/tmp/site-home-dark.png', fullPage: true });
    await page.getByRole('button', { name: 'Switch to light theme' }).click();
    await page.goto(`${base}/writing/`);
    const total = await page.locator('[data-entry]').count();
    assert.ok(total > 0);
    await page.getByLabel('Search the library').fill('nemotron');
    assert.equal(await page.locator('[data-entry]:visible').count(), 2);
    await page.getByLabel('Format', { exact: true }).selectOption('guide');
    assert.equal(await page.locator('[data-entry]:visible').count(), 1);
    assert.ok(page.url().includes('type=guide'));
    await page.reload();
    assert.equal(await page.locator('[data-entry]:visible').count(), 1);
    await page.getByLabel('Search the library').fill('no-result-sentinel');
    assert.equal(await page.locator('[data-entry]:visible').count(), 0);
    assert.equal(await page.locator('[data-empty]').isVisible(), true);
    await page.getByRole('button', { name: 'Clear filters' }).click();
    await page.waitForFunction(() => !location.search);
    assert.equal(await page.locator('[data-entry]:visible').count(), total);
    await page.getByLabel('Topic', { exact: true }).selectOption('databases-querying');
    const filtered = await page.locator('[data-entry]:visible').count();
    assert.ok(filtered > 0 && filtered < total);
    const article = page.locator('[data-entry]:visible h3 a').first();
    await article.click();
    await page.goBack();
    assert.equal(await page.getByLabel('Topic', { exact: true }).inputValue(), 'databases-querying');
    assert.equal(await page.locator('[data-entry]:visible').count(), filtered);
    await page.screenshot({ path: '/private/tmp/site-writing-desktop.png', fullPage: true });
    for (const width of [320, 390, 768, 1440]) {
      await page.setViewportSize({ width, height: 844 });
      for (const path of ['/', '/writing/', '/categories/', '/topics/data-platforms/', '/guides/', '/case-studies/']) {
        await page.goto(base + path);
        await page.evaluate(() => document.fonts.ready);
        if (path === "/case-studies/") assert.equal(await page.locator("#case-index-title").textContent(), "The short version");
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1), false, `overflow at ${width}: ${path}`);
      }
    }
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(base);
    const menu = page.getByRole('button', { name: 'Menu', exact: true });
    assert.equal(await menu.getAttribute('aria-expanded'), 'false');
    await menu.click();
    assert.equal(await page.getByRole('navigation', { name: 'Main navigation' }).getByRole('link', { name: 'Topics', exact: true }).isVisible(), true);
    await menu.press('Escape');
    assert.equal(await menu.getAttribute('aria-expanded'), 'false');
    await page.screenshot({ path: '/private/tmp/site-home-mobile.png', fullPage: true });
    const nojs = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 390, height: 844 } });
    const plain = await nojs.newPage();
    await plain.goto(`${base}/topics/databases-querying/`);
    assert.equal(await plain.locator('[data-entry]').count(), filtered);
    assert.equal(await plain.getByRole('navigation', { name: 'Main navigation' }).getByRole('link', { name: 'Writing', exact: true }).isVisible(), true);
    assert.deepEqual(errors, []);
    console.log('Browser checks passed: responsive layouts, themes, filtering, URLs, history, empty states, menu, and no-JS topic browsing.');
    await nojs.close();
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
