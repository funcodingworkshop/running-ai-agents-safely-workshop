import { test, expect } from '@playwright/test';

test('div#test_1 shows the greeting', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('#test_1')).toHaveText('Hi Mike');
});
