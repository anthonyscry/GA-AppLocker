import { test, expect, chromium } from '@playwright/test';

/**
 * Example using CDP connection to existing Chrome instance.
 * Start Chrome with: google-chrome --remote-debugging-port=9222
 */
test('has title', async () => {
  const browser = await chromium.connectOverCDP('http://localhost:9222');
  const context = browser.contexts()[0] || await browser.newContext();
  const page = await context.newPage();

  await page.goto('https://playwright.dev/');
  await expect(page).toHaveTitle(/Playwright/);

  await page.close();
});

test('get started link', async () => {
  const browser = await chromium.connectOverCDP('http://localhost:9222');
  const context = browser.contexts()[0] || await browser.newContext();
  const page = await context.newPage();

  await page.goto('https://playwright.dev/');
  await page.getByRole('link', { name: 'Get started' }).click();
  await expect(page.getByRole('heading', { name: 'Installation' })).toBeVisible();

  await page.close();
});
