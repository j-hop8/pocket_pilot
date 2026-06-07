import { describe, expect, it } from "vitest";
import {
  foldMostRecentCategory,
  type HistoryRow,
  resolveInvoiceCategory,
  resolveItemCategory,
} from "./category_resolver";

describe("foldMostRecentCategory", () => {
  it("keeps the most recent category per normalized key", () => {
    const rows: HistoryRow[] = [
      { key: "Coffee", categoryId: 1, stamp: "2026-01-01|a" },
      { key: "coffee", categoryId: 2, stamp: "2026-06-01|a" }, // newer, wins
      { key: "coffee", categoryId: 3, stamp: "2026-03-01|a" },
    ];
    expect(foldMostRecentCategory(rows).get("coffee")).toBe(2);
  });

  it("breaks a same-date tie with created_at in the stamp", () => {
    const rows: HistoryRow[] = [
      { key: "tea", categoryId: 1, stamp: "2026-06-01|2026-06-01T08:00:00Z" },
      { key: "tea", categoryId: 2, stamp: "2026-06-01|2026-06-01T09:00:00Z" },
    ];
    expect(foldMostRecentCategory(rows).get("tea")).toBe(2);
  });

  it("skips null category, null key, and blank key", () => {
    const rows: HistoryRow[] = [
      { key: "book", categoryId: null, stamp: "2026-06-01|a" },
      { key: null, categoryId: 5, stamp: "2026-06-01|a" },
      { key: "   ", categoryId: 6, stamp: "2026-06-01|a" },
      { key: "book", categoryId: 7, stamp: "2026-05-01|a" },
    ];
    const map = foldMostRecentCategory(rows);
    expect(map.get("book")).toBe(7);
    expect(map.size).toBe(1);
  });
});

describe("resolveItemCategory priority", () => {
  const itemHist = new Map([["latte", 10]]);
  const merchantHist = new Map([["starbucks", 20]]);

  it("item history wins over merchant and keyword", () => {
    expect(resolveItemCategory("Latte", "Starbucks", itemHist, merchantHist, 30)).toBe(10);
  });

  it("merchant history wins when the item has no history", () => {
    expect(resolveItemCategory("Croissant", "Starbucks", itemHist, merchantHist, 30)).toBe(20);
  });

  it("keyword fallback when neither has history", () => {
    expect(resolveItemCategory("Croissant", "Unknown", itemHist, merchantHist, 30)).toBe(30);
  });

  it("returns null when the keyword fallback is null", () => {
    expect(resolveItemCategory("X", null, new Map(), new Map(), null)).toBeNull();
  });
});

describe("resolveInvoiceCategory priority", () => {
  const merchantHist = new Map([["starbucks", 20]]);

  it("merchant history wins over keyword", () => {
    expect(resolveInvoiceCategory("Starbucks", merchantHist, 30)).toBe(20);
  });

  it("keyword fallback when merchant has no history", () => {
    expect(resolveInvoiceCategory("Unknown", merchantHist, 30)).toBe(30);
  });
});
