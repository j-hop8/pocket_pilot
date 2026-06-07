// Open-source OCR via Tesseract.js (runs in-process, no Python/sidecar), with
// `sharp` preprocessing. One shared worker is reused across calls; access is
// serialized so per-call parameter changes (CAPTCHA whitelist vs. document mode)
// don't race. See README risk #2 for the CAPTCHA accuracy strategy.

import { createWorker, PSM, OEM, type Worker } from "tesseract.js";
import sharp from "sharp";
import type { OcrService } from "./index";

export class TesseractOcr implements OcrService {
  private workerPromise: Promise<Worker> | null = null;
  private chain: Promise<unknown> = Promise.resolve();

  private getWorker(): Promise<Worker> {
    if (!this.workerPromise) {
      // Silent logger; LSTM engine only (best for the numeric CAPTCHA).
      this.workerPromise = createWorker("eng", OEM.LSTM_ONLY, {
        logger: () => {},
      });
    }
    return this.workerPromise;
  }

  /// Serialize recognitions so setParameters from concurrent callers can't bleed.
  private run<T>(fn: () => Promise<T>): Promise<T> {
    const next = this.chain.then(fn, fn);
    this.chain = next.catch(() => {});
    return next;
  }

  async solveCaptcha(image: Buffer): Promise<string> {
    const pre = await preprocessCaptcha(image);
    const text = await this.run(async () => {
      const worker = await this.getWorker();
      await worker.setParameters({
        tessedit_char_whitelist: "0123456789",
        tessedit_pageseg_mode: PSM.SINGLE_LINE,
      });
      const { data } = await worker.recognize(pre);
      return data.text;
    });
    return text.replace(/\D/g, "");
  }

  async extractText(image: Buffer): Promise<string> {
    const pre = await preprocessDocument(image);
    const text = await this.run(async () => {
      const worker = await this.getWorker();
      await worker.setParameters({
        tessedit_char_whitelist: "",
        tessedit_pageseg_mode: PSM.AUTO,
      });
      const { data } = await worker.recognize(pre);
      return data.text;
    });
    return text.trim();
  }

  async dispose(): Promise<void> {
    if (!this.workerPromise) return;
    const worker = await this.workerPromise;
    this.workerPromise = null;
    await worker.terminate();
  }
}

/// CAPTCHA preprocessing: isolate dark glyphs on a light field so Tesseract can
/// read them. grayscale → upscale → stretch contrast → denoise → binarize.
/// Tune these (especially the threshold) against real samples during the spike.
export async function preprocessCaptcha(image: Buffer): Promise<Buffer> {
  return sharp(image)
    .grayscale()
    .resize({ width: 600 }) // upscale the small CAPTCHA
    .normalize() // stretch contrast to full range
    .median(1) // kill speckle noise
    .threshold(140) // binarize
    .png()
    .toBuffer();
}

/// Lighter preprocessing for documents/receipts (Phase 2) — keep detail, just
/// normalize contrast.
async function preprocessDocument(image: Buffer): Promise<Buffer> {
  return sharp(image).grayscale().normalize().png().toBuffer();
}
