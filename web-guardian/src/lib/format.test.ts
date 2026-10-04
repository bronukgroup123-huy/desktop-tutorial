import { describe, it, expect } from "vitest";
import {
  formatDuration,
  formatRelativeSeconds,
  formatBattery,
  formatSignal,
  distanceKm,
  getStatusStyle,
} from "./format";

describe("formatDuration", () => {
  it("через N хв", () => {
    expect(formatDuration(45)).toBe("через 45 хв");
  });
  it("через N год", () => {
    expect(formatDuration(120)).toBe("через 2 год");
  });
  it("через N год M хв", () => {
    expect(formatDuration(135)).toBe("через 2 год 15 хв");
  });
  it("прострочено", () => {
    expect(formatDuration(-30)).toBe("прострочено 30 хв");
  });
});

describe("formatRelativeSeconds", () => {
  it("секунди", () => {
    expect(formatRelativeSeconds(30)).toBe("30 сек тому");
  });
  it("хвилини", () => {
    expect(formatRelativeSeconds(180)).toBe("3 хв тому");
  });
  it("години", () => {
    expect(formatRelativeSeconds(7200)).toBe("2 год тому");
  });
  it("null", () => {
    expect(formatRelativeSeconds(null)).toBe("—");
  });
});

describe("formatBattery", () => {
  it("число", () => {
    expect(formatBattery(85)).toBe("85%");
  });
  it("null", () => {
    expect(formatBattery(null)).toBe("—");
  });
});

describe("formatSignal", () => {
  it("strength=3", () => {
    expect(formatSignal(3)).toBe("▁▂▃");
  });
  it("null", () => {
    expect(formatSignal(null)).toBe("—");
  });
});

describe("distanceKm", () => {
  it("Київ — Львів ~ 470 км", () => {
    const d = distanceKm(
      { lat: 50.45, lng: 30.52 },
      { lat: 49.84, lng: 24.03 }
    );
    expect(d).toBeGreaterThan(450);
    expect(d).toBeLessThan(500);
  });
  it("одна точка = 0", () => {
    const d = distanceKm({ lat: 50, lng: 30 }, { lat: 50, lng: 30 });
    expect(d).toBe(0);
  });
});

describe("getStatusStyle", () => {
  it("sos — isUrgent=true", () => {
    expect(getStatusStyle("sos").isUrgent).toBe(true);
  });
  it("active — isUrgent=false", () => {
    expect(getStatusStyle("active").isUrgent).toBe(false);
  });
});
