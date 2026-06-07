// Entry point: one process hosting the HTTP API + queue worker + scheduler.
//
//   POST /sync/now  — Supabase-JWT-authed; marks the user "running", enqueues a
//                     sync job, returns 202 immediately (no long-held request).
//                     The Flutter app polls carrier_config for the outcome.
//   GET  /healthz   — liveness probe for Railway/Render.

import Fastify from "fastify";
import cors from "@fastify/cors";
import { config } from "./config";
import { bearerToken, userIdFromToken } from "./auth";
import { enqueueSync, getBoss, stopBoss } from "./queue";
import { startWorker } from "./worker";
import { startScheduler } from "./scheduler";
import { setStatus, ocr } from "./sync";

const app = Fastify({ logger: true });

// Auth is a Bearer JWT (no cookies), so reflecting any origin is safe and lets
// the Flutter web app (any dev port / deployed origin) call the API.
app.register(cors, { origin: true });

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

app.get("/healthz", async () => ({ ok: true }));

app.post("/sync/now", async (req, reply) => {
  const token = bearerToken(req);
  if (!token) return reply.code(401).send({ error: "unauthorized" });
  const userId = await userIdFromToken(token);
  if (!userId) return reply.code(401).send({ error: "unauthorized" });

  // Flip status now so the app sees "running" immediately, then enqueue.
  await setStatus(userId, "running", null);
  await enqueueSync(userId);
  return reply.code(202).send({ status: "queued" });
});

async function main(): Promise<void> {
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
