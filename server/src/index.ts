// Entry point: one process hosting the HTTP API + queue worker + scheduler.
//
//   POST /sync/now  — Supabase-JWT-authed; marks the user "running", enqueues a
//                     sync job, returns 202 immediately (no long-held request).
//                     The Flutter app polls carrier_config for the outcome.
//   GET  /healthz   — liveness probe for Railway/Render.

import Fastify from "fastify";
import cors from "@fastify/cors";
import rateLimit from "@fastify/rate-limit";
import { config } from "./config";
import { admin } from "./supabase";
import { bearerToken, userIdFromToken } from "./auth";
import { syncThrottleDecision } from "./lib/sync-throttle";
import { enqueueSync, getBoss, stopBoss } from "./queue";
import { startWorker } from "./worker";
import { startScheduler } from "./scheduler";
import { setStatus, ocr } from "./sync";

// trustProxy: 'loopback' so req.ip (and the rate limiter) sees the real client
// IP from the nginx hop on 127.0.0.1 — but ONLY that hop is trusted. With the
// previous `true`, any client could spoof `X-Forwarded-For` and rotate req.ip to
// evade the per-IP rate limit; trusting only loopback (nginx) closes that. nginx
// also overwrites X-Forwarded-For with $remote_addr (see deploy/nginx), so a
// client-supplied header is discarded before it ever reaches Fastify.
const app = Fastify({ logger: true, trustProxy: "loopback" });

// ORDER MATTERS: @fastify/rate-limit attaches to each route via an `onRoute`
// hook, so it must finish registering *before* the routes are declared (unlike
// @fastify/cors, whose global onRequest hook applies regardless). Hence the
// awaits here rather than a top-level, lazily-loaded `app.register(...)`.
async function buildServer(): Promise<void> {
  // Auth is a Bearer JWT (no cookies), so reflecting any origin is safe and lets
  // the Flutter web app (any dev port / deployed origin) call the API.
  await app.register(cors, { origin: true });

  // Blanket per-IP request ceiling. The per-user cooldown on /sync/now (below)
  // is the meaningful guard; this just bounds raw request volume. /healthz opts
  // out so liveness probes are never throttled.
  await app.register(rateLimit, {
    max: config.httpRateMax,
    timeWindow: config.httpRateWindowMs,
  });

  // /sync/now carries no JSON body (the user is derived from the Bearer token).
  // Some clients still send `Content-Type: application/json` with an empty body,
  // which trips Fastify's default parser (FST_ERR_CTP_EMPTY_JSON_BODY → 400)
  // before the route handler runs. Treat an empty body as {} so the endpoint is
  // reachable regardless of how the client frames the request.
  app.addContentTypeParser(
    "application/json",
    { parseAs: "string" },
    (_req, body, done) => {
      const text = (body as string) ?? "";
      if (text.trim() === "") return done(null, {});
      try {
        done(null, JSON.parse(text));
      } catch (err) {
        (err as Error & { statusCode?: number }).statusCode = 400;
        done(err as Error, undefined);
      }
    },
  );

  app.get("/healthz", { config: { rateLimit: false } }, async () => ({ ok: true }));

  app.post("/sync/now", async (req, reply) => {
    const token = bearerToken(req);
    if (!token) return reply.code(401).send({ error: "unauthorized" });
    const userId = await userIdFromToken(token);
    if (!userId) return reply.code(401).send({ error: "unauthorized" });

    // Per-user cooldown: don't let a tap-happy client re-log into the gov portal.
    const { data: cfg } = await admin
      .from("carrier_config")
      .select("last_sync_status, last_sync_attempt_at")
      .eq("user_id", userId)
      .maybeSingle();
    const attemptAt = cfg?.last_sync_attempt_at as string | null | undefined;
    const decision = syncThrottleDecision(
      {
        status: (cfg?.last_sync_status as string | null) ?? null,
        attemptAtMs: attemptAt ? new Date(attemptAt).getTime() : null,
      },
      Date.now(),
      config.syncCooldownSeconds * 1000,
      config.syncJobExpireSeconds * 1000,
    );
    if (!decision.allowed) {
      return reply
        .code(429)
        .header("retry-after", String(decision.retryAfterSec))
        .send({ error: decision.reason, retryAfter: decision.retryAfterSec });
    }

    // Flip status now so the app sees "running" immediately, then enqueue.
    await setStatus(userId, "running", null);
    await enqueueSync(userId);
    return reply.code(202).send({ status: "queued" });
  });
}

async function main(): Promise<void> {
  await buildServer();
  await getBoss();
  await startWorker();
  startScheduler();
  await app.listen({ port: config.port, host: "0.0.0.0" });
}

async function shutdown(signal: string): Promise<void> {
  app.log.info(`received ${signal}, shutting down`);
  await app.close().catch(() => {});
  await stopBoss().catch(() => {});
  await ocr.dispose().catch(() => {});
  process.exit(0);
}
process.on("SIGTERM", () => void shutdown("SIGTERM"));
process.on("SIGINT", () => void shutdown("SIGINT"));

main().catch((e) => {
  app.log.error(e);
  process.exit(1);
});
