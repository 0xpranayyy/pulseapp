const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({
    viewport: { width: 1290, height: 940 },
    deviceScaleFactor: 2,
  });

  await page.goto('file://' + process.cwd() + '/screens.html');

  // Wait for the bundled Allo faces and the remote market artwork.
  await page.evaluate(() => document.fonts.ready);
  await page.waitForLoadState('networkidle').catch(() => {});
  await page.waitForTimeout(1500);

  await page.screenshot({ path: 'pulse-screens.png', fullPage: true });

  const phones = await page.locator('.phone').all();
  for (let i = 0; i < phones.length; i++) {
    await phones[i].screenshot({ path: 'screen-' + (i + 1) + '.png' });
  }

  console.log('captured ' + phones.length + ' screens');
  await browser.close();
})();
