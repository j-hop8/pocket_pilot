import { expect, test } from "vitest";
import { syncThrottleDecision } from "./sync-throttle";

const COOLDOWN = 60_000; // 60s
const RUNNING_TTL = 600_000; // 10min
const NOW = 1_000_000_000_000;

test("allows when the user has never synced", () => {
  const d = syncThrottleDecision({ status: null, attemptAtMs: null }, NOW, COOLDOWN, RUNNING_TTL);
  expect(d.allowed).toBe(true);
});

test("denies while a sync is still running within the TTL", () => {
  const d = syncThrottleDecision(
    { status: "running", attemptAtMs: NOW - 5_000 },
    NOW,
    COOLDOWN,
    RUNNING_TTL,
  );
  expect(d).toMatchObject({ allowed: false, reason: "a sync is already running" });
  if (!d.allowed) expect(d.retryAfterSec).toBeGreaterThan(0);
});

test("allows a stale 'running' past the TTL (crashed job)", () => {
  const d = syncThrottleDecision(
    { status: "running", attemptAtMs: NOW - RUNNING_TTL - 1 },
    NOW,
    COOLDOWN,
    RUNNING_TTL,
  );
  expect(d.allowed).toBe(true);
});

test("denies a finished sync that was too recent (within cooldown)", () => {
  const d = syncThrottleDecision(
    { status: "ok", attemptAtMs: NOW - 10_000 },
    NOW,
    COOLDOWN,
    RUNNING_TTL,
  );
  expect(d).toMatchObject({ allowed: false, reason: "synced too recently" });
  if (!d.allowed) expect(d.retryAfterSec).toBe(50); // 60s - 10s
});

test("allows once the cooldown has elapsed", () => {
  const d = syncThrottleDecision(
    { status: "error", attemptAtMs: NOW - COOLDOWN - 1 },
    NOW,
    COOLDOWN,
    RUNNING_TTL,
  );
  expect(d.allowed).toBe(true);
});
