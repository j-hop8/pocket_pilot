// Full sync for one user: status running → read phone + Vault password → scrape
// the 消費明細 CSV → ingest → status ok/error. Direct port of the Edge Function's
// syncUser/setStatus, now using the self-hosted scraper + Tesseract OCR.

import { admin } from "./supabase";
import { config } from "./config";
import { ingestCsv, type SyncResult } from "./lib/ingest";
import { downloadCarrierCsv } from "./scrape";
import { TesseractOcr } from "./ocr/tesseract";
import type { OcrService } from "./ocr";

// One OCR engine shared across all syncs (the Tesseract worker is reused).
export const ocr: OcrService = new TesseractOcr();

export async function runSync(userId: string): Promise<SyncResult> {
  await setStatus(userId, "running", null);
  try {
    const { data: cfg, error } = await admin
      .from("carrier_config")
      .select("phone")
      .eq("user_id", userId)
      .single();
    if (error) throw error;
    const phone = (cfg?.phone as string | null) ?? "";

    const { data: password, error: secErr } = await admin.rpc("get_carrier_secret", {
      p_user_id: userId,
    });
    if (secErr) throw secErr;
    if (!phone || !password) {
      throw new Error("carrier credentials are not set");
    }

    const csv = await downloadCarrierCsv(
      { phone, password: password as string },
      {
        ocr,
        headless: config.headless,
        proxyUrl: config.proxyUrl,
        log: (m) => console.log(`[sync ${short(userId)}] ${m}`),
      },
    );
    const result = await ingestCsv(admin, userId, csv);

    const now = new Date().toISOString();
    await admin
      .from("carrier_config")
      .update({
        last_synced_at: now,
        last_sync_count: result.inserted,
        last_sync_status: "ok",
        last_sync_error: null,
        last_sync_attempt_at: now,
        updated_at: now,
      })
      .eq("user_id", userId);

    return result;
  } catch (e) {
    await setStatus(userId, "error", (e as Error).message);
    throw e;
  }
}

export async function setStatus(
  userId: string,
  status: "running" | "ok" | "error",
  error: string | null,
): Promise<void> {
  const now = new Date().toISOString();
  await admin
    .from("carrier_config")
    .update({
      last_sync_status: status,
      last_sync_error: error,
      last_sync_attempt_at: now,
      updated_at: now,
    })
    .eq("user_id", userId);
}

function short(userId: string): string {
  return userId.slice(0, 8);
}
