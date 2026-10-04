import { test, expect } from "@playwright/test";

const BASE_URL = process.env.E2E_BASE_URL ?? "http://localhost:3000";

test.describe("Guardian page", () => {
  test.skip(
    !process.env.E2E_GUARDIAN_TOKEN,
    "E2E_GUARDIAN_TOKEN не встановлено"
  );

  test("відкриває карту і показує статус", async ({ page }) => {
    await page.goto(`${BASE_URL}/s/${process.env.E2E_GUARDIAN_TOKEN}`);

    await expect(page.locator("header")).toBeVisible();
    await expect(page.locator(".maplibregl-map")).toBeVisible();
    await expect(page.getByLabel("Прокласти маршрут")).toBeVisible();
    await expect(page.getByLabel("Завантажити GPX")).toBeVisible();
  });

  test("невалідний токен → помилка", async ({ page }) => {
    await page.goto(`${BASE_URL}/s/invalid.token.here`);
    await expect(page.getByText("Посилання недійсне")).toBeVisible();
  });
});
