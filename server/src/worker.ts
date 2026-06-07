// Pulls sync jobs off the queue and runs them, up to SYNC_CONCURRENCY in
// parallel (each opens its own browser). Throwing lets pg-boss apply its retry
// policy; runSync has already recorded the error on carrier_config.

import { getBoss, SYNC_QUEUE, type SyncJob } from "./queue";
import { runSync } from "./sync";
import { config } from "./config";

export async function startWorker(): Promise<void> {
  const boss = await getBoss();
  await boss.work(
    SYNC_QUEUE,
    { batchSize: config.syncConcurrency },
    async (jobs: SyncJob[]) => {
      await Promise.all(
        jobs.map(async (job) => {
          const userId = job.data.userId;
          const result = await runSync(userId);
          console.log(
            `[worker] ok user=${userId.slice(0, 8)} inserted=${result.inserted} skipped=${result.skipped}`,
          );
        }),
      );
    },
  );
  console.log(
    `[worker] listening on "${SYNC_QUEUE}" (concurrency=${config.syncConcurrency})`,
  );
}
