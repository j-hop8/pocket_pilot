import { expect, test } from "vitest";
import { computeSyncRange, monthDelta } from "./sync-range";

const opts = { overlapDays: 3, lookbackDays: 60 };

test("first sync (null) looks back lookbackDays from today", () => {
  const now = new Date("2026-06-16T03:00:00Z"); // 11:00 Taipei, same day
  const r = computeSyncRange(null, now, opts);
  expect(r.to).toEqual({ year: 2026, month: 6, day: 16 });
  expect(r.from).toEqual({ year: 2026, month: 4, day: 17 }); // 16 Jun − 60d
});

test("incremental sync anchors at last success minus overlap", () => {
  const now = new Date("2026-06-16T03:00:00Z");
  const last = new Date("2026-06-14T08:00:00Z"); // 14 Jun Taipei
  const r = computeSyncRange(last, now, opts);
  expect(r.from).toEqual({ year: 2026, month: 6, day: 11 }); // 14 − 3
  expect(r.to).toEqual({ year: 2026, month: 6, day: 16 });
});

test("uses the Asia/Taipei calendar day, not UTC", () => {
  // 20:00Z on Jun 15 is already 04:00 on Jun 16 in Taipei (UTC+8).
  const now = new Date("2026-06-15T20:00:00Z");
  const r = computeSyncRange(null, now, opts);
  expect(r.to).toEqual({ year: 2026, month: 6, day: 16 });
});

test("overlap can cross a month boundary", () => {
  const now = new Date("2026-06-16T03:00:00Z");
  const last = new Date("2026-06-02T08:00:00Z"); // 2 Jun
  const r = computeSyncRange(last, now, opts);
  expect(r.from).toEqual({ year: 2026, month: 5, day: 30 }); // 2 Jun − 3
});

test("monthDelta counts whole months across a year boundary", () => {
  expect(monthDelta({ year: 2025, month: 11, day: 5 }, { year: 2026, month: 2, day: 20 })).toBe(3);
  expect(monthDelta({ year: 2026, month: 6, day: 1 }, { year: 2026, month: 6, day: 28 })).toBe(0);
});
