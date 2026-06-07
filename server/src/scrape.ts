// Drives a self-hosted Chromium (Playwright + stealth) to log into the MOF
// e-invoice portal and download the 消費明細 CSV. Replaces the old Browserless
// `/function` string-Puppeteer approach — we now own the browser, so this uses
// the real Playwright Page API and Playwright's native download handling.
//
// CAPTCHA solving is delegated to an OcrService (Tesseract.js today). See
// README risk #1 (Cloudflare) and #3 (unconfirmed export selectors).

import { chromium } from "playwright-extra";
import StealthPlugin from "puppeteer-extra-plugin-stealth";
import type { Page } from "playwright";
import { promises as fs } from "fs";
import * as path from "path";
import type { OcrService } from "./ocr";

// Register the stealth evasions once (patches navigator.webdriver, headless
// markers, WebGL/permissions, etc.) to help clear Cloudflare Turnstile.
chromium.use(StealthPlugin() as never);

export interface PortalCredentials {
  phone: string;
  password: string;
}

export interface ScrapeOptions {
  ocr: OcrService;
  /// false (default in the container, under Xvfb) gives the best Turnstile pass
  /// rate. true for local headless runs without a display.
  headless?: boolean;
  /// Optional residential/TW proxy, used only if Cloudflare blocks the host IP.
  proxyUrl?: string;
  log?: (msg: string) => void;
  /// When set, screenshots + CAPTCHA samples + a failure DOM dump are written
  /// here (used by the spike to de-risk; off in production).
  debugDir?: string;
}

const LOGIN_URL = "https://www.einvoice.nat.gov.tw/accounts/login";
const SEARCH_URL =
  "https://www.einvoice.nat.gov.tw/portal/btc/mobile/btc502w/search";
const PHONE_SEL =
  '#mobile_phone, input[name="mobile_phone"], input[type="tel"]';
const CAPTCHA_IMG_SEL = "span.code_num img";
const CAPTCHA_LEN = 5;
const USER_AGENT =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

export async function downloadCarrierCsv(
  creds: PortalCredentials,
  opts: ScrapeOptions,
): Promise<string> {
  const log = opts.log ?? (() => {});
  const browser = await chromium.launch({
    headless: opts.headless ?? true,
    args: [
      "--no-sandbox",
      "--disable-dev-shm-usage",
      "--disable-blink-features=AutomationControlled",
    ],
  });
  try {
    const context = await browser.newContext({
      locale: "zh-TW",
      timezoneId: "Asia/Taipei",
      viewport: { width: 1280, height: 900 },
      userAgent: USER_AGENT,
      acceptDownloads: true,
      proxy: opts.proxyUrl ? { server: opts.proxyUrl } : undefined,
    });
    // tsx/esbuild compiles this file with `keepNames`, which wraps functions in
    // a `__name(...)` helper. Playwright stringifies the functions we pass to
    // page.evaluate/waitForFunction and runs them in the browser, where `__name`
    // doesn't exist → "ReferenceError: __name is not defined". Define a no-op in
    // every document (passed as a string so esbuild can't re-wrap it).
    await context.addInitScript(
      "globalThis.__name = globalThis.__name || ((fn) => fn);",
    );
    const page = await context.newPage();
    await login(page, creds, opts.ocr, log, opts.debugDir);
    return await downloadDetailCsv(page, log);
  } finally {
    await browser.close();
  }
}

// ── Login ────────────────────────────────────────────────────────────────────

async function login(
  page: Page,
  creds: PortalCredentials,
  ocr: OcrService,
  log: (msg: string) => void,
  debugDir?: string,
): Promise<void> {
  // Two independent budgets: cheap CAPTCHA re-solves (wrong-length reads cost
  // nothing but a refresh) vs. actual login submissions.
  const MAX_LOGIN_SUBMITS = 4;
  const MAX_CAPTCHA_SOLVES = 8;
  const RETRY_DELAY_MS = 2000;
  let submits = 0;
  let solves = 0;
  let lastReason = "(no attempt made)";

  await gotoLogin(page);

  while (submits < MAX_LOGIN_SUBMITS && solves < MAX_CAPTCHA_SOLVES) {
    // Wait for the real CAPTCHA to replace the 1×1 placeholder GIF.
    if (!(await waitForRealCaptcha(page))) {
      solves++;
      lastReason = `solve ${solves}: real CAPTCHA image never loaded (still placeholder)`;
      log(lastReason);
      await reloadLogin(page, RETRY_DELAY_MS);
      continue;
    }

    const captchaBuf = await page.locator(CAPTCHA_IMG_SEL).first().screenshot();
    if (debugDir) await saveBytes(debugDir, `captcha-${solves + 1}.png`, captchaBuf);
    const answer = await ocr.solveCaptcha(captchaBuf);
    solves++;

    // The CAPTCHA is exactly 5 digits — a wrong-length read is a known-bad OCR
    // result, so refresh and re-solve without burning a login submission.
    if (answer.length !== CAPTCHA_LEN) {
      lastReason = `solve ${solves} read "${answer}" (${answer.length} digits, expected ${CAPTCHA_LEN})`;
      log(lastReason);
      await reloadLogin(page, RETRY_DELAY_MS);
      continue;
    }

    await fillAndSubmit(page, creds, answer);
    submits++;

    // Success signal: the page leaves /accounts/login.
    const left = await page
      .waitForFunction(() => !location.href.includes("/accounts/login"), undefined, {
        timeout: 12000,
        polling: 300,
      })
      .then(() => true)
      .catch(() => false);
    if (left) {
      log(`logged in (submit ${submits}, ${solves} CAPTCHA solves)`);
      return;
    }

    lastReason = `submit ${submits} guessed "${answer}" → ${await readPortalError(page)}`;
    log(lastReason);
    await reloadLogin(page, RETRY_DELAY_MS);
  }

  if (debugDir) await dumpPage(page, debugDir, "login-failed");
  throw new Error(
    `Login failed (${submits} submits / ${solves} CAPTCHA solves). Last: ${lastReason}`,
  );
}

async function gotoLogin(page: Page): Promise<void> {
  await page.goto(LOGIN_URL, { waitUntil: "domcontentloaded", timeout: 30000 });
  // Survive Cloudflare → login redirects by waiting for the real form.
  await page.waitForSelector(PHONE_SEL, { timeout: 30000 });
}

async function reloadLogin(page: Page, delayMs: number): Promise<void> {
  // Wait first so we don't hammer the gov portal (avoids rate-limit / bot flags).
  await page.waitForTimeout(delayMs);
  await gotoLogin(page);
}

async function waitForRealCaptcha(page: Page): Promise<boolean> {
  const ready = () =>
    page
      .waitForFunction(
        (sel) => {
          const img = document.querySelector(sel) as HTMLImageElement | null;
          return !!(img && img.complete && img.naturalWidth > 1);
        },
        CAPTCHA_IMG_SEL,
        { timeout: 8000, polling: 200 },
      )
      .then(() => true)
      .catch(() => false);

  if (await ready()) return true;

  // Nudge via the portal's 更新圖形驗證碼 (refresh CAPTCHA) button, then re-wait.
  await page.evaluate(() => {
    const btn = Array.from(document.querySelectorAll("button")).find((b) =>
      (b.textContent || "").includes("更新圖形驗證碼"),
    );
    if (btn) (btn as HTMLButtonElement).click();
  });
  return ready();
}

async function fillAndSubmit(
  page: Page,
  creds: PortalCredentials,
  captcha: string,
): Promise<void> {
  // Playwright's fill dispatches proper input/change events, so Vue/React
  // bindings register the value (no native-setter hack needed).
  await page.locator(PHONE_SEL).first().fill(creds.phone);
  await page.locator("#password").first().fill(creds.password);
  await page.locator("#captcha").first().fill(captcha);
  await page
    .locator('button[type="submit"], input[type="submit"]')
    .first()
    .click();
}

async function readPortalError(page: Page): Promise<string> {
  return page.evaluate(() => {
    const sels = [
      ".error",
      ".alert",
      ".help-block",
      ".invalid-feedback",
      '[class*="error"]',
      '[class*="msg"]',
      '[role="alert"]',
    ];
    for (const s of sels) {
      for (const el of Array.from(document.querySelectorAll(s))) {
        const t = (el.textContent || "").trim();
        if (t) return t.slice(0, 120);
      }
    }
    return "no error shown (likely CAPTCHA misread)";
  });
}

// ── 消費明細 export ──────────────────────────────────────────────────────────

async function downloadDetailCsv(
  page: Page,
  log: (msg: string) => void,
): Promise<string> {
  // Run the query with the pre-filled (current-month) date range. The date field
  // is a readonly vue-datepicker; current month is good enough for a recurring
  // sync and dedupe makes overlapping ranges safe.
  await page.goto(SEARCH_URL, { waitUntil: "networkidle", timeout: 30000 });
  await page.waitForSelector("#dp-input-searchInvoiceDate", { timeout: 20000 });

  const searched = await page.evaluate(() => {
    const btn = document.querySelector(
      'button[title="查詢"], button[aria-label="查詢"]',
    ) as HTMLButtonElement | null;
    if (!btn) return false;
    btn.click();
    return true;
  });
  if (!searched) throw new Error("Search (查詢) button not found on search page");

  await page
    .waitForFunction(
      () =>
        location.href.includes("/detail") ||
        !!document.querySelector('label[for="invoiceDetailAll"], #invoiceDetailAll'),
      undefined,
      { timeout: 30000, polling: 300 },
    )
    .catch(() => {});
  await page.waitForSelector("#invoiceDetailAll, label[for=\"invoiceDetailAll\"]", {
    timeout: 20000,
  });

  await maximizePageSize(page);
  await installCsvHooks(page);

  const pageCsvs: string[] = [];
  const MAX_PAGES = 50; // safety cap

  for (let pageNum = 1; pageNum <= MAX_PAGES; pageNum++) {
    await page.waitForSelector("#invoiceDetailAll, label[for=\"invoiceDetailAll\"]", {
      timeout: 20000,
    });

    const dataRows = await countDataRows(page);
    if (dataRows === 0) break; // paged past the last row → done

    await selectAllRows(page);
    if (!(await waitDownloadEnabled(page))) {
      throw new Error(
        `下載CSV檔 stayed disabled on page ${pageNum} (rows=${dataRows})`,
      );
    }

    const csv = await clickDownloadAndCapture(page);
    if (!csv) throw new Error(`CSV download produced no data on page ${pageNum}`);
    pageCsvs.push(csv);
    log(`captured CSV page ${pageNum} (${dataRows} rows)`);

    if (!(await goNextPage(page))) break;
  }

  if (!pageCsvs.length) throw new Error("No CSV pages were downloaded");
  return concatCsvPages(pageCsvs);
}

async function maximizePageSize(page: Page): Promise<void> {
  // Find a pagination <select> of page sizes (e.g. 10/20/50/100) and pick the
  // largest, so there are fewer pages to iterate. No-op if none exists.
  const chosen = await page.evaluate(() => {
    const setNative = (el: HTMLSelectElement, val: string) => {
      const setter = Object.getOwnPropertyDescriptor(
        window.HTMLSelectElement.prototype,
        "value",
      )!.set!;
      setter.call(el, val);
      el.dispatchEvent(new Event("input", { bubbles: true }));
      el.dispatchEvent(new Event("change", { bubbles: true }));
    };
    for (const sel of Array.from(document.querySelectorAll("select"))) {
      const opts = Array.from(sel.options);
      const nums = opts
        .map((o) => parseInt((o.value || o.textContent || "").replace(/[^0-9]/g, ""), 10))
        .filter((n) => !isNaN(n));
      if (nums.length >= 2 && nums.some((n) => n >= 50) && nums.every((n) => n > 0 && n <= 2000)) {
        const max = Math.max(...nums);
        const opt = opts.find(
          (o) => parseInt((o.value || o.textContent || "").replace(/[^0-9]/g, ""), 10) === max,
        );
        if (opt) {
          setNative(sel, opt.value);
          return max;
        }
      }
    }
    return 0;
  });
  if (chosen) {
    await page.waitForTimeout(2000);
    await page.waitForSelector("#invoiceDetailAll, label[for=\"invoiceDetailAll\"]", {
      timeout: 20000,
    });
  }
}

async function countDataRows(page: Page): Promise<number> {
  return page.evaluate(() => {
    const rows = Array.from(document.querySelectorAll("tbody tr"));
    return rows.filter((r) => {
      const t = (r.textContent || "").trim();
      if (!t) return false;
      if (/查無|無資料|no data/i.test(t)) return false;
      return !!r.querySelector('input[type="checkbox"], td');
    }).length;
  });
}

async function selectAllRows(page: Page): Promise<void> {
  // After pagination the header checkbox can stay visually checked while the new
  // rows are unselected (leaving the download button disabled) — toggle off→on.
  await page.evaluate(() => {
    const cb = document.querySelector("#invoiceDetailAll") as HTMLInputElement | null;
    const lbl = document.querySelector('label[for="invoiceDetailAll"]') as HTMLLabelElement | null;
    const clickIt = () => {
      if (cb) cb.click();
      else if (lbl) lbl.click();
    };
    if (cb && cb.checked) clickIt(); // clear stale state
    clickIt(); // (re)check → selects current page rows
  });
}

async function waitDownloadEnabled(page: Page): Promise<boolean> {
  return page
    .waitForFunction(
      () => {
        const b = document.querySelector('button[title="下載CSV檔"]') as HTMLButtonElement | null;
        return !!(b && !b.disabled);
      },
      undefined,
      { timeout: 10000, polling: 200 },
    )
    .then(() => true)
    .catch(() => false);
}

/// Click 下載CSV檔 and return the CSV text. Primary path: Playwright's native
/// download event (works for real downloads AND client-side blob downloads).
/// Fallback: the fetch/XHR/createObjectURL capture hooks (installCsvHooks).
async function clickDownloadAndCapture(page: Page): Promise<string | null> {
  await page.evaluate(() => {
    (window as unknown as { __csvCaptured?: string[] }).__csvCaptured = [];
  });

  const downloadPromise = page
    .waitForEvent("download", { timeout: 15000 })
    .catch(() => null);
  await page.evaluate(() => {
    const b = document.querySelector('button[title="下載CSV檔"]') as HTMLButtonElement | null;
    if (b && !b.disabled) b.click();
  });

  const download = await downloadPromise;
  if (download) {
    const p = await download.path();
    if (p) return fs.readFile(p, "utf8");
  }

  // Fallback to whatever the page-side hooks captured.
  const captured = await page
    .waitForFunction(
      () => {
        const arr = (window as unknown as { __csvCaptured?: string[] }).__csvCaptured;
        return arr && arr.length ? arr[arr.length - 1] : false;
      },
      undefined,
      { timeout: 8000, polling: 300 },
    )
    .then((h) => h.jsonValue() as Promise<string>)
    .catch(() => null);
  return captured ?? null;
}

async function goNextPage(page: Page): Promise<boolean> {
  const hasNext = await page.evaluate(() => {
    const a = document.querySelector('a[title="下一頁"]') as HTMLAnchorElement | null;
    if (!a) return false;
    const li = a.closest("li");
    if (li && li.classList.contains("disabled")) return false;
    if (a.getAttribute("aria-disabled") === "true") return false;
    if (a.classList.contains("disabled")) return false;
    return true;
  });
  if (!hasNext) return false;

  // Snapshot the current table so we can tell a real page change from a no-op.
  // The portal leaves 下一頁 visually enabled even on the last page, so a click
  // that doesn't actually advance must be treated as "no more pages" — otherwise
  // we re-download the final page until the MAX_PAGES cap (the infinite loop).
  const beforeMarker = await page.evaluate(tableMarker);
  await page.evaluate(() => {
    const a = document.querySelector('a[title="下一頁"]') as HTMLAnchorElement | null;
    if (a) a.click();
  });
  // Return whether the table actually changed. If it never does, this was the
  // last page → stop paginating instead of looping on stale data.
  return page
    .waitForFunction(
      (prev) => {
        const rows = Array.from(document.querySelectorAll("tbody tr"));
        const marker =
          rows.length +
          "#" +
          rows.map((r) => (r.textContent || "").trim().slice(0, 40)).join("|").slice(0, 300);
        return marker !== prev;
      },
      beforeMarker,
      { timeout: 12000, polling: 300 },
    )
    .then(() => true)
    .catch(() => false);
}

// A fingerprint of the current detail table (row count + per-row text snippets)
// used to detect whether a 下一頁 click actually advanced the page.
function tableMarker(): string {
  const rows = Array.from(document.querySelectorAll("tbody tr"));
  return (
    rows.length +
    "#" +
    rows.map((r) => (r.textContent || "").trim().slice(0, 40)).join("|").slice(0, 300)
  );
}

async function installCsvHooks(page: Page): Promise<void> {
  await page.evaluate(() => {
    const w = window as unknown as {
      __csvHookInstalled?: boolean;
      __csvCaptured?: string[];
    };
    if (w.__csvHookInstalled) return;
    w.__csvHookInstalled = true;
    w.__csvCaptured = [];
    const push = (t: unknown) => {
      if (t && typeof t === "string") w.__csvCaptured!.push(t);
    };

    const origCreate = URL.createObjectURL;
    URL.createObjectURL = function (obj: Blob | MediaSource): string {
      try {
        if (obj instanceof Blob) obj.text().then(push).catch(() => {});
      } catch {
        /* ignore */
      }
      return origCreate.call(URL, obj);
    };

    const origFetch = window.fetch;
    window.fetch = async function (...args: Parameters<typeof fetch>) {
      const res = await origFetch.apply(window, args);
      try {
        const a0 = args[0] as unknown;
        const url =
          (typeof a0 === "string" ? a0 : (a0 as { url?: string })?.url) || "";
        const ct = res.headers.get("content-type") || "";
        if (ct.includes("csv") || /csv|download|export/i.test(url)) {
          res.clone().text().then(push).catch(() => {});
        }
      } catch {
        /* ignore */
      }
      return res;
    };

    const OrigXHR = window.XMLHttpRequest;
    function HookedXHR(this: unknown) {
      const xhr = new OrigXHR();
      xhr.addEventListener("load", function () {
        try {
          const ct = xhr.getResponseHeader("content-type") || "";
          if (ct.includes("csv") || /csv|download|export/i.test(xhr.responseURL || "")) {
            if (typeof xhr.responseText === "string") push(xhr.responseText);
          }
        } catch {
          /* ignore */
        }
      });
      return xhr;
    }
    (HookedXHR as unknown as { prototype: unknown }).prototype = OrigXHR.prototype;
    window.XMLHttpRequest = HookedXHR as unknown as typeof XMLHttpRequest;
  });
}

/// Concatenate page CSVs: keep page 1 whole; drop a repeated header line from
/// later pages when it matches page 1's first line.
function concatCsvPages(pages: string[]): string {
  const firstLine = pages[0].split(/\r?\n/)[0];
  let combined = pages[0].replace(/\s+$/, "");
  for (let i = 1; i < pages.length; i++) {
    const lines = pages[i].split(/\r?\n/);
    if (lines.length && lines[0].trim() === firstLine.trim()) lines.shift();
    const body = lines.join("\n").replace(/\s+$/, "");
    if (body) combined += "\n" + body;
  }
  return combined;
}

// ── Debug artifacts (spike only) ─────────────────────────────────────────────

async function saveBytes(dir: string, name: string, bytes: Buffer): Promise<void> {
  await fs.mkdir(dir, { recursive: true });
  await fs.writeFile(path.join(dir, name), bytes);
}

async function dumpPage(page: Page, dir: string, prefix: string): Promise<void> {
  try {
    await fs.mkdir(dir, { recursive: true });
    await page.screenshot({ path: path.join(dir, `${prefix}.png`), fullPage: true });
    await fs.writeFile(path.join(dir, `${prefix}.html`), await page.content());
  } catch {
    /* best-effort */
  }
}
