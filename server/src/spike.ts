// Throwaway spike to de-risk the three hard problems BEFORE building/deploying:
//   1. Does stealth Playwright clear Cloudflare Turnstile from this host/IP?
//   2. Does Tesseract solve the portal CAPTCHA acceptably?
//   3. Are the post-login 消費明細 export selectors correct?
//
// Runs the real scrape against a test account and writes artifacts to ./.spike
// (CAPTCHA samples per attempt, and on failure a screenshot + DOM dump). Does NOT
// touch Supabase, so it only needs PHONE/PASSWORD.
//
// Usage (best Turnstile pass rate is headful with a display):
//   PHONE=09xxxxxxxx PASSWORD=secret HEADLESS=false npm run spike

import { promises as fs } from "fs";
import * as path from "path";
import { downloadCarrierCsv } from "./scrape";
import { TesseractOcr } from "./ocr/tesseract";

async function main(): Promise<void> {
  const phone = process.env.PHONE;
  const password = process.env.PASSWORD;
  if (!phone || !password) {
    console.error("Set PHONE and PASSWORD env vars.");
    process.exit(1);
  }

  const ocr = new TesseractOcr();
  const debugDir = path.resolve(".spike");
  await fs.mkdir(debugDir, { recursive: true });

  try {
    const csv = await downloadCarrierCsv(
      { phone, password },
      {
        ocr,
        headless: process.env.HEADLESS !== "false",
        proxyUrl: process.env.PROXY_URL || undefined,
        debugDir,
        log: (m) => console.log("•", m),
      },
    );
    const out = path.join(debugDir, "detail.csv");
    await fs.writeFile(out, csv, "utf8");
    const lines = csv.split(/\r?\n/).length;
    console.log(`\n✅ Downloaded CSV (${csv.length} bytes, ${lines} lines) → ${out}`);
  } catch (e) {
    console.error("\n❌ Spike failed:", (e as Error).message);
    console.error(`   Inspect ${debugDir} for CAPTCHA samples + screenshots/DOM dump.`);
    process.exitCode = 1;
  } finally {
    await ocr.dispose();
  }
}

void main();
