// Behaviour of the Supabase fetch wrapper: it retries the keep-alive "fetch
// failed" socket death (and transient 5xx) on a fresh connection, but never
// retries a 4xx data error. Run with: `npm test`.

import { afterEach, expect, test, vi } from "vitest";
import { describeError, makeResilientFetch } from "./resilient-fetch";

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

// Fast + deterministic: no backoff sleeps, generous per-attempt timeout.
const opts = { retries: 2, baseDelayMs: 0, timeoutMs: 5000 } as const;

test("retries a thrown network error, then returns the successful response", async () => {
  const fetchMock = vi
    .fn()
    .mockRejectedValueOnce(new TypeError("fetch failed"))
    .mockResolvedValueOnce(new Response("ok", { status: 200 }));
  vi.stubGlobal("fetch", fetchMock);

  const res = await makeResilientFetch(opts)("https://example.test");

  expect(res.status).toBe(200);
  expect(fetchMock).toHaveBeenCalledTimes(2);
});

test("gives up after the retry budget on a persistent network error", async () => {
  const fetchMock = vi.fn().mockRejectedValue(new TypeError("fetch failed"));
  vi.stubGlobal("fetch", fetchMock);

  await expect(makeResilientFetch(opts)("https://example.test")).rejects.toThrow(
    "fetch failed",
  );
  expect(fetchMock).toHaveBeenCalledTimes(3); // first attempt + 2 retries
});

test("retries a transient 503, then returns the recovered response", async () => {
  const fetchMock = vi
    .fn()
    .mockResolvedValueOnce(new Response("busy", { status: 503 }))
    .mockResolvedValueOnce(new Response("ok", { status: 200 }));
  vi.stubGlobal("fetch", fetchMock);

  const res = await makeResilientFetch(opts)("https://example.test");

  expect(res.status).toBe(200);
  expect(fetchMock).toHaveBeenCalledTimes(2);
});

test("does NOT retry a 4xx data error", async () => {
  const fetchMock = vi
    .fn()
    .mockResolvedValue(new Response("bad request", { status: 400 }));
  vi.stubGlobal("fetch", fetchMock);

  const res = await makeResilientFetch(opts)("https://example.test");

  expect(res.status).toBe(400);
  expect(fetchMock).toHaveBeenCalledTimes(1);
});

test("describeError surfaces the undici cause + code", () => {
  const cause = Object.assign(new Error("other side closed"), {
    code: "UND_ERR_SOCKET",
  });
  const e = new TypeError("fetch failed", { cause });

  expect(describeError(e)).toBe("fetch failed (UND_ERR_SOCKET: other side closed)");
});
