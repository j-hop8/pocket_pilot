-- Carrier sync is now driven by the dedicated backend's own scheduler
-- (server/src/scheduler.ts), which scans carrier_config for due users and feeds
-- a job queue. Unschedule the old hourly pg_cron job so the two don't both fire.
--
-- The Vault credential RPCs (set_carrier_credentials / get_carrier_secret) and
-- the per-user sync-settings columns are unchanged — the backend reads them with
-- the service role. We only remove the cron trigger.
--
-- Idempotent + safe when pg_cron or the job are absent (local db reset).

DO $$
BEGIN
  IF to_regnamespace('cron') IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'carrier-sync-hourly') THEN
      PERFORM cron.unschedule('carrier-sync-hourly');
      RAISE NOTICE 'Unscheduled carrier-sync-hourly (now handled by the backend).';
    ELSE
      RAISE NOTICE 'carrier-sync-hourly not scheduled; nothing to drop.';
    END IF;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'drop_carrier_cron skipped: %', SQLERRM;
END $$;
