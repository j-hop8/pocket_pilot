// pg-boss job queue (backed by the Supabase Postgres). Replaces the Edge
// Function's sequential per-user loop: each sync is a durable job with retries +
// backoff, and the worker bounds concurrency. singletonKey=userId guarantees at
// most one queued/active sync per user (protects against double "Sync now" and
// overlapping scheduler ticks).

import PgBoss, { type Job } from "pg-boss";
import { config } from "./config";

export const SYNC_QUEUE = "carrier-sync";

export interface SyncJobData {
  userId: string;
}

export type SyncJob = Job<SyncJobData>;

let bossPromise: Promise<PgBoss> | null = null;

export function getBoss(): Promise<PgBoss> {
  if (!bossPromise) {
    bossPromise = (async () => {
      const boss = new PgBoss({ connectionString: config.dbUrl });
      boss.on("error", (e) => console.error("[pg-boss]", e));
      await boss.start();
      await boss.createQueue(SYNC_QUEUE);
      return boss;
    })();
  }
  return bossPromise;
}

export async function enqueueSync(userId: string): Promise<void> {
  const boss = await getBoss();
  await boss.send(
    SYNC_QUEUE,
    { userId },
    {
      singletonKey: userId,
      retryLimit: 2,
      retryDelay: 60,
      retryBackoff: true,
      expireInSeconds: config.syncJobExpireSeconds,
    },
  );
}

export async function stopBoss(): Promise<void> {
  if (!bossPromise) return;
  const boss = await bossPromise;
  await boss.stop();
  bossPromise = null;
}
