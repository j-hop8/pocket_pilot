import { afterEach, expect, test, vi } from "vitest";
import { createGapThrottle } from "./portal-throttle";

afterEach(() => {
  vi.useRealTimers();
});

test("spaces successive acquisitions by gapMs", async () => {
  vi.useFakeTimers();
  vi.setSystemTime(0);

  const acquire = createGapThrottle(1000);
  const resolvedAt: number[] = [];
  const calls = [acquire(), acquire(), acquire()].map((p) =>
    p.then(() => resolvedAt.push(Date.now())),
  );

  await vi.advanceTimersByTimeAsync(2000);
  await Promise.all(calls);

  expect(resolvedAt).toEqual([0, 1000, 2000]);
});

test("gapMs=0 lets everything through immediately", async () => {
  vi.useFakeTimers();
  vi.setSystemTime(0);

  const acquire = createGapThrottle(0);
  await Promise.all([acquire(), acquire(), acquire()]);

  expect(Date.now()).toBe(0);
});
