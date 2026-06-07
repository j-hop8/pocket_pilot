// Drives a remote browser via Browserless's /function REST endpoint.
// Uses Deno's native fetch — no playwright-core / Node.js TCP dependency.
//
// All automation (login, CAPTCHA solving, CSV download) runs on the Browserless
// server. CAPTCHA is solved inside the remote function by calling Gemini directly,
// so there are no round-trips back to the Edge Function.
//
// BROWSER_WS_ENDPOINT format: wss://production-sfo.browserless.io?token=XXX
// We derive the REST URL: https://production-sfo.browserless.io/function?token=XXX

export interface PortalCredentials {
  phone: string;
  password: string;
}

export async function downloadCarrierCsv(
  creds: PortalCredentials,
): Promise<string> {
  const wsEndpoint = Deno.env.get("BROWSER_WS_ENDPOINT");
  if (!wsEndpoint) throw new Error("BROWSER_WS_ENDPOINT is not set");

  const googleAiKey = Deno.env.get("GOOGLE_AI_API_KEY");
  if (!googleAiKey) throw new Error("GOOGLE_AI_API_KEY is not set");

  // Derive REST URL from the WS endpoint
  const u = new URL(wsEndpoint.replace(/^wss?:\/\//, "https://"));
  u.pathname = "/function";
  u.searchParams.set("stealth", "true"); // bypass Cloudflare Turnstile bot detection
  // Raise the per-function execution cap to the plan max (60000 = the ceiling Browserless
  // accepts here). The whole remote run — login + multi-page CSV download — must fit in this,
  // so we maximize page size below to keep the page count (and total time) down.
  u.searchParams.set("timeout", "60000");

  // Browserless v2 /function: send JSON body { code, context } instead of
  // JavaScript body + ?context= URL param (which v2 ignores).
  const res = await fetch(u.toString(), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      code: BROWSER_CODE,
      context: { phone: creds.phone, password: creds.password, googleAiKey },
    }),
  });

  const bodyText = await res.text();
  console.log(`Browserless response status=${res.status} body=${bodyText.slice(0, 800)}`);

  if (!res.ok) {
    throw new Error(`Browserless call failed (${res.status}): ${bodyText}`);
  }

  let result: { csv?: string; error?: string };
  try {
    result = JSON.parse(bodyText);
  } catch {
    throw new Error(`Browserless returned non-JSON (${res.status}): ${bodyText.slice(0, 200)}`);
  }
  if (result.error) throw new Error(`carrier scrape failed: ${result.error}`);
  if (!result.csv) throw new Error(`carrier scrape returned no CSV data. Raw: ${bodyText.slice(0, 200)}`);
  return result.csv;
}

// Browser automation code executed on the Browserless server (Puppeteer/Node.js).
// Kept as a string so the Edge Function itself has zero Node.js dependencies.
// NOTE: Browserless /function uses Puppeteer — Playwright APIs (fill, locator,
// waitForEvent, :has-text selectors) do not exist here.
// Browserless /function ignores returned Response objects and returns {} for them.
// Use throw for all errors (propagates as 400) and return a plain object for success.
const BROWSER_CODE = `
export default async ({ page, context: { phone, password, googleAiKey } }) => {

  // 1) Log in — use domcontentloaded then waitForSelector so we survive
  // Cloudflare stealth redirects before the actual login form appears.
  await page.goto('https://www.einvoice.nat.gov.tw/accounts/login', {
    waitUntil: 'domcontentloaded', timeout: 30000
  });

  // Wait for the actual login form to appear (handles Cloudflare → login redirects)
  const PHONE_SEL = '#mobile_phone, input[name="mobile_phone"], input[type="tel"]';
  await page.waitForSelector(PHONE_SEL, { timeout: 30000 });

  const phoneSelector = await page.evaluate((sel) => {
    const el = document.querySelector(sel);
    if (!el) return null;
    if (el.id) return '#' + el.id;
    if (el.name) return 'input[name="' + el.name + '"]';
    return sel.split(',')[0].trim();
  }, PHONE_SEL);

  if (!phoneSelector) throw new Error('Phone selector resolved to null after waitForSelector');

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  // The portal initially renders a 1x1 transparent placeholder GIF in span.code_num img,
  // then swaps in the real CAPTCHA asynchronously. Wait for the real image (naturalWidth
  // > 1) before reading it; nudge it with the refresh button if it doesn't auto-load.
  const waitForRealCaptcha = async () => {
    const ready = await page.waitForFunction(() => {
      const img = document.querySelector('span.code_num img');
      return !!(img && img.complete && img.naturalWidth > 1);
    }, { timeout: 8000, polling: 200 }).then(() => true).catch(() => false);
    if (ready) return true;

    // Force a refresh via the portal's 更新圖形驗證碼 button, then wait again.
    await page.evaluate(() => {
      const btn = Array.from(document.querySelectorAll('button'))
        .find((b) => (b.textContent || '').includes('更新圖形驗證碼'));
      if (btn) btn.click();
    });
    return page.waitForFunction(() => {
      const img = document.querySelector('span.code_num img');
      return !!(img && img.complete && img.naturalWidth > 1);
    }, { timeout: 8000, polling: 200 }).then(() => true).catch(() => false);
  };

  // Reload the login page and wait for the form — used to get a fresh CAPTCHA between
  // attempts. Waits first so we don't hammer the portal (avoids rate-limiting / bot flags).
  const reloadLogin = async () => {
    await sleep(RETRY_DELAY_MS);
    await page.goto('https://www.einvoice.nat.gov.tw/accounts/login', {
      waitUntil: 'domcontentloaded', timeout: 30000
    });
    await page.waitForSelector(PHONE_SEL, { timeout: 30000 });
  };

  // 2) Solve CAPTCHA + log in, with a small number of retries. The portal's numeric
  // CAPTCHA is noisy, so the occasional OCR misread is expected — but keep attempts low
  // and spaced out to stay gentle on the gov portal.
  const MAX_ATTEMPTS = 3;
  const RETRY_DELAY_MS = 2000; // wait between attempts to avoid hammering the portal
  const CAPTCHA_LEN = 5; // portal CAPTCHA is exactly 5 digits
  let loggedIn = false;
  let lastReason = '';

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    // 2a) Wait for the real CAPTCHA to replace the 1x1 placeholder GIF, then grab it.
    if (!(await waitForRealCaptcha())) {
      lastReason = 'attempt ' + attempt + ': real CAPTCHA image never loaded (still placeholder)';
      if (attempt < MAX_ATTEMPTS) { await reloadLogin(); continue; }
      break;
    }

    const captcha = await page.evaluate(async () => {
      const img = document.querySelector('span.code_num img')
               ?? document.querySelector('label[for="captcha"] ~ * img')
               ?? (() => {
                   const input = document.querySelector('#captcha');
                   const container = input?.closest('form') ?? input?.parentElement;
                   return container?.querySelector('img');
                 })();
      if (!img) return null;
      const mimeFromSrc = (s) => {
        const m = s.match(/^data:([^;,]+)[;,]/);
        return m ? m[1] : 'image/png';
      };
      if (img.src.startsWith('data:')) {
        const comma = img.src.indexOf(',');
        return comma !== -1 ? { b64: img.src.slice(comma + 1), mime: mimeFromSrc(img.src) } : null;
      }
      const res = await fetch(img.src, { credentials: 'include' });
      const ct = res.headers.get('content-type') || 'image/png';
      const buf = await res.arrayBuffer();
      const bytes = new Uint8Array(buf);
      let binary = '';
      for (let i = 0; i < bytes.byteLength; i++) binary += String.fromCharCode(bytes[i]);
      return { b64: btoa(binary), mime: ct };
    });
    if (!captcha || !captcha.b64) throw new Error('CAPTCHA image not found on login page');
    const captchaBase64 = captcha.b64;

    // 2b) Solve via Gemini (full 2.5-flash for better OCR; thinking disabled so it
    // emits digits directly instead of burning the output budget on reasoning).
    const geminiRes = await fetch(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=' + googleAiKey,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [{ parts: [
            { inlineData: { mimeType: captcha.mime, data: captchaBase64 } },
            { text: 'This is a CAPTCHA image containing exactly 5 digits. Read all 5 digits carefully, left to right, and output ONLY those 5 digits with no spaces, letters, or explanation.' }
          ]}],
          generationConfig: { thinkingConfig: { thinkingBudget: 0 }, temperature: 0 }
        })
      }
    );
    const geminiJson = await geminiRes.json();
    const captchaAnswer = (geminiJson?.candidates?.[0]?.content?.parts?.[0]?.text ?? '')
      .trim().replace(/\\D/g, '');
    if (!captchaAnswer) {
      lastReason = 'Gemini returned no answer: ' + JSON.stringify(geminiJson).slice(0, 160);
      if (attempt < MAX_ATTEMPTS) { await reloadLogin(); continue; }
      break;
    }

    // The CAPTCHA is exactly 5 digits. A wrong-length read is a known-bad OCR result —
    // don't waste a login attempt on it, just refresh and re-solve.
    if (captchaAnswer.length !== CAPTCHA_LEN) {
      lastReason = 'attempt ' + attempt + ' read "' + captchaAnswer + '" (' +
        captchaAnswer.length + ' digits, expected ' + CAPTCHA_LEN + ')';
      if (attempt < MAX_ATTEMPTS) { await reloadLogin(); continue; }
      break;
    }

    // 2c) Fill all three fields + submit in one atomic evaluate (avoids stale handles
    // if the page mutates mid-sequence). Uses the native value setter so framework
    // bindings (React/Vue) register the change.
    const fillErr = await page.evaluate((pSel, p, pwd, c) => {
      const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
      const setVal = (sel, val) => {
        const el = document.querySelector(sel);
        if (!el) return 'Element not found: ' + sel;
        setter.call(el, val);
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return null;
      };
      const e = setVal(pSel, p) || setVal('#password', pwd) || setVal('#captcha', c);
      if (e) return e;
      const btn = document.querySelector('button[type="submit"], input[type="submit"]');
      if (!btn) return 'Submit button not found';
      btn.click();
      return null;
    }, phoneSelector, phone, password, captchaAnswer);
    if (fillErr) throw new Error('Form fill failed: ' + fillErr);

    // 2d) Success signal: the page leaves /accounts/login. Wait for that explicitly
    // (works for both full-page redirects and SPA route changes).
    const left = await page
      .waitForFunction(() => !location.href.includes('/accounts/login'),
        { timeout: 12000, polling: 300 })
      .then(() => true).catch(() => false);

    if (left) { loggedIn = true; break; }

    // Still on the login page — record any error the portal surfaced, then retry.
    lastReason = await page.evaluate(() => {
      const sels = ['.error', '.alert', '.help-block', '.invalid-feedback',
        '[class*="error"]', '[class*="msg"]', '[role="alert"]'];
      for (const s of sels) {
        for (const el of document.querySelectorAll(s)) {
          const t = (el.textContent || '').trim();
          if (t) return t.slice(0, 120);
        }
      }
      return 'no error shown (likely CAPTCHA misread)';
    });
    lastReason = 'attempt ' + attempt + ' guessed "' + captchaAnswer + '" → ' + lastReason;
    if (attempt < MAX_ATTEMPTS) await reloadLogin();
  }

  if (!loggedIn) {
    // Dump the real DOM so a structural problem can't masquerade as a CAPTCHA miss.
    const dbg = await page.evaluate(() => {
      const form = document.querySelector('form');
      return {
        url: location.href,
        title: document.title,
        inputs: Array.from(document.querySelectorAll('input')).map(i =>
          // Never log password/credential values; just note whether they're filled.
          '#' + i.id + ' name=' + i.name + ' type=' + i.type + ' ' +
          (i.type === 'password' ? 'filled=' + (i.value ? 'yes' : 'no')
                                 : 'val=' + (i.value || '').slice(0, 8))),
        buttons: Array.from(document.querySelectorAll('button, input[type=submit]')).map(b =>
          b.tagName + ':' + (b.type || '') + ':' + (b.textContent || b.value || '').trim().slice(0, 20)),
        formHtml: form ? form.outerHTML.slice(0, 400) : '(no form element)',
      };
    });
    throw new Error('Login failed after ' + MAX_ATTEMPTS + ' attempts. Last: ' + lastReason +
      ' | DOM: ' + JSON.stringify(dbg));
  }

  // 3) Run the 消費明細 query, then select-all + download CSV on each result page.
  //    search → 查詢 → redirect to /detail → (全選 → 下載CSV檔 → 下一頁)*

  // 3a) Go to the search page and run the query with the pre-filled date range.
  // The date field (#dp-input-searchInvoiceDate) is a readonly vue-datepicker that
  // defaults to the current month — good enough for a recurring sync, and it can't be
  // set reliably by writing to the readonly input, so we use the default range.
  await page.goto('https://www.einvoice.nat.gov.tw/portal/btc/mobile/btc502w/search', {
    waitUntil: 'networkidle2', timeout: 30000
  });
  await page.waitForSelector('#dp-input-searchInvoiceDate', { timeout: 20000 });

  const searchClicked = await page.evaluate(() => {
    const btn = document.querySelector('button[title="查詢"], button[aria-label="查詢"]');
    if (!btn) return false;
    btn.click();
    return true;
  });
  if (!searchClicked) throw new Error('Search (查詢) button not found on search page');

  // 3b) Wait for the detail page / results table to appear.
  await page.waitForFunction(
    () => location.href.includes('/detail') ||
          !!document.querySelector('label[for="invoiceDetailAll"], #invoiceDetailAll'),
    { timeout: 30000, polling: 300 }
  ).catch(() => {});
  await page.waitForSelector('#invoiceDetailAll, label[for="invoiceDetailAll"]', { timeout: 20000 });

  // 3b-2) Maximize page size so there are fewer pages to iterate (avoids the Browserless
  // timeout on large result sets). Heuristic: find a pagination <select> whose options
  // are page sizes (e.g. 10/20/50/100) and pick the largest. No-op if none exists.
  const pageSize = await page.evaluate(() => {
    const setNative = (el, val) => {
      const setter = Object.getOwnPropertyDescriptor(window.HTMLSelectElement.prototype, 'value').set;
      setter.call(el, val);
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    };
    for (const sel of Array.from(document.querySelectorAll('select'))) {
      const opts = Array.from(sel.options);
      const nums = opts.map((o) => parseInt((o.value || o.textContent || '').replace(/[^0-9]/g, ''), 10))
        .filter((n) => !isNaN(n));
      // Looks like a page-size control: ≥2 numeric options, offers a large one, all sane.
      if (nums.length >= 2 && nums.some((n) => n >= 50) && nums.every((n) => n > 0 && n <= 2000)) {
        const max = Math.max(...nums);
        const chosen = opts.find((o) =>
          parseInt((o.value || o.textContent || '').replace(/[^0-9]/g, ''), 10) === max);
        if (chosen) { setNative(sel, chosen.value); return max; }
      }
    }
    return 0;
  });
  if (pageSize) {
    // Let the table reload with the larger page size before we start downloading.
    await sleep(2000);
    await page.waitForSelector('#invoiceDetailAll, label[for="invoiceDetailAll"]', { timeout: 20000 });
  }

  // 3c) Install download hooks: the 下載CSV檔 button may generate a client-side Blob or
  // fetch CSV from the server. Capture both, plus XHR, into window.__csvCaptured.
  await page.evaluate(() => {
    if (window.__csvHookInstalled) return;
    window.__csvHookInstalled = true;
    window.__csvCaptured = [];
    const push = (t) => { if (t && typeof t === 'string') window.__csvCaptured.push(t); };

    const origCreate = URL.createObjectURL;
    URL.createObjectURL = function (obj) {
      try { if (obj instanceof Blob) obj.text().then(push).catch(() => {}); } catch (e) {}
      return origCreate.call(this, obj);
    };

    const origFetch = window.fetch;
    window.fetch = async function (...args) {
      const res = await origFetch.apply(this, args);
      try {
        const url = (typeof args[0] === 'string' ? args[0] : (args[0] && args[0].url)) || '';
        const ct = res.headers.get('content-type') || '';
        if (ct.includes('csv') || /csv|download|export/i.test(url)) {
          res.clone().text().then(push).catch(() => {});
        }
      } catch (e) {}
      return res;
    };

    const OrigXHR = window.XMLHttpRequest;
    function HookedXHR() {
      const xhr = new OrigXHR();
      xhr.addEventListener('load', function () {
        try {
          const ct = (xhr.getResponseHeader('content-type') || '');
          if (ct.includes('csv') || /csv|download|export/i.test(xhr.responseURL || '')) {
            if (typeof xhr.responseText === 'string') push(xhr.responseText);
          }
        } catch (e) {}
      });
      return xhr;
    }
    HookedXHR.prototype = OrigXHR.prototype;
    window.XMLHttpRequest = HookedXHR;
  });

  // 3d) Loop pages: select-all → download → capture → next page.
  const pageCsvs = [];
  const MAX_PAGES = 50; // safety cap

  for (let pageNum = 1; pageNum <= MAX_PAGES; pageNum++) {
    await page.waitForSelector('#invoiceDetailAll, label[for="invoiceDetailAll"]', { timeout: 20000 });

    // Count real data rows on this page (a "no data" placeholder row doesn't count).
    const rowInfo = await page.evaluate(() => {
      const rows = Array.from(document.querySelectorAll('tbody tr'));
      const dataRows = rows.filter((r) => {
        const t = (r.textContent || '').trim();
        if (!t) return false;
        if (/查無|無資料|no data/i.test(t)) return false;
        return !!r.querySelector('input[type="checkbox"], td');
      });
      return { total: rows.length, data: dataRows.length };
    });
    if (rowInfo.data === 0) break; // paged past the last row of results → done

    // Force a CLEAN select-all on the current rows. After pagination the header
    // checkbox can stay visually checked while the new rows are unselected, leaving
    // the download button disabled — so if it's already checked, toggle off then on.
    await page.evaluate(() => {
      const cb = document.querySelector('#invoiceDetailAll');
      const lbl = document.querySelector('label[for="invoiceDetailAll"]');
      const clickIt = () => { if (cb) cb.click(); else if (lbl) lbl.click(); };
      if (cb && cb.checked) clickIt();   // uncheck stale state
      clickIt();                          // (re)check → selects current page rows
    });

    // Wait for the 下載CSV檔 button to become enabled (it's disabled until selection)
    const enabled = await page.waitForFunction(() => {
      const b = document.querySelector('button[title="下載CSV檔"]');
      return b && !b.disabled;
    }, { timeout: 10000, polling: 200 }).then(() => true).catch(() => false);

    if (!enabled) {
      // Not enabled despite having data rows → genuinely stuck; report state.
      const st = await page.evaluate(() => {
        const b = document.querySelector('button[title="下載CSV檔"]');
        const cb = document.querySelector('#invoiceDetailAll');
        return { btn: b ? ('disabled=' + b.disabled) : 'missing',
                 selectAll: cb ? ('checked=' + cb.checked) : 'missing' };
      });
      throw new Error('下載CSV檔 stayed disabled on page ' + pageNum +
        ' (rows=' + rowInfo.data + ', ' + JSON.stringify(st) + ')');
    }

    // Clear prior captures, click download, wait for new capture
    await page.evaluate(() => { window.__csvCaptured = []; });
    const clicked = await page.evaluate(() => {
      const b = document.querySelector('button[title="下載CSV檔"]');
      if (!b || b.disabled) return false;
      b.click();
      return true;
    });
    if (!clicked) throw new Error('下載CSV檔 button missing/disabled on page ' + pageNum);

    const csv = await page.waitForFunction(
      () => (window.__csvCaptured && window.__csvCaptured.length)
        ? window.__csvCaptured[window.__csvCaptured.length - 1] : false,
      { timeout: 20000, polling: 300 }
    ).then((h) => h.jsonValue()).catch(() => null);

    if (!csv) throw new Error('CSV download produced no data on page ' + pageNum);
    pageCsvs.push(csv);

    // Is there a usable 下一頁 (next page) link?
    const hasNext = await page.evaluate(() => {
      const a = document.querySelector('a[title="下一頁"]');
      if (!a) return false;
      const li = a.closest('li');
      if (li && li.classList.contains('disabled')) return false;
      if (a.getAttribute('aria-disabled') === 'true') return false;
      if (a.classList.contains('disabled')) return false;
      return true;
    });
    if (!hasNext) break;

    // Capture a marker of the current first row so we can detect the table refreshing
    const beforeMarker = await page.evaluate(() => {
      const row = document.querySelector('tbody tr');
      return row ? row.textContent.trim().slice(0, 60) : '';
    });
    await page.evaluate(() => {
      const a = document.querySelector('a[title="下一頁"]');
      if (a) a.click();
    });
    // Wait for the table to actually change (or just settle) before the next iteration
    await page.waitForFunction((prev) => {
      const row = document.querySelector('tbody tr');
      return row ? row.textContent.trim().slice(0, 60) !== prev : true;
    }, { timeout: 15000, polling: 300 }, beforeMarker).catch(() => {});
  }

  if (!pageCsvs.length) throw new Error('No CSV pages were downloaded');

  // 3e) Concatenate pages. Keep the first page whole; for later pages, drop a repeated
  // header line if it matches page 1's first line.
  const firstLine = pageCsvs[0].split(/\\r?\\n/)[0];
  let combined = pageCsvs[0].replace(/\\s+$/, '');
  for (let i = 1; i < pageCsvs.length; i++) {
    const lines = pageCsvs[i].split(/\\r?\\n/);
    if (lines.length && lines[0].trim() === firstLine.trim()) lines.shift();
    const body = lines.join('\\n').replace(/\\s+$/, '');
    if (body) combined += '\\n' + body;
  }

  // Return plain object — Browserless JSON-encodes this as the response body
  return { csv: combined };
};
`;
