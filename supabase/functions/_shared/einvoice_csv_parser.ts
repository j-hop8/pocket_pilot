// Pure-TS port of packages/pp_core/lib/src/einvoice_csv_parser.dart.
//
// Intentionally dependency-free (no Deno/npm imports) so it runs identically in
// the Edge Function (Deno) and the Node parity test. Keep in lockstep with the
// Dart original — the parity test (einvoice_csv_parser.test.ts) guards this.

export interface ParsedItem {
  name: string; // 消費明細_品名
  quantity: number; // 消費明細_數量
  unitPrice: number; // 消費明細_單價 (TWD dollars)
  amount: number; // 消費明細_金額 (TWD dollars)
}

export interface ParsedInvoice {
  invoiceNumber: string;
  date: string; // 'YYYY-MM-DD'
  merchantName: string | null; // 賣方名稱
  carrierName: string | null; // 載具自訂名稱
  sellerAddress: string | null; // 賣方地址
  items: ParsedItem[];
}

/// Invoice total in TWD dollars = sum of line amounts.
///
/// The CSV's 發票金額 column is unreliable — for multi-line invoices it mirrors
/// the per-line amount rather than the invoice total — so we always sum the line
/// items (discount lines are negative and net correctly).
export function invoiceTotalDollars(inv: ParsedInvoice): number {
  return inv.items.reduce((sum, i) => sum + i.amount, 0);
}

// 2 letters + 8 digits (digits may be masked with '*' for voided/donated ones).
const INVOICE_NO_RE = /^[A-Z]{2}[0-9*]{8}$/;
const DATE_RE = /^\d{8}$/;

/// Parses a MOF carrier detail CSV into invoices grouped by invoice number.
export function parseEinvoiceCsv(csv: string): ParsedInvoice[] {
  let text = csv;
  if (text.length > 0 && text.charCodeAt(0) === 0xfeff) {
    text = text.slice(1); // strip UTF-8 BOM
  }
  text = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n");

  const rows = parseCsvRows(text);
  if (rows.length === 0) return [];

  const col = columnIndex(rows);

  // Preserve first-seen order while grouping by invoice number.
  const order: string[] = [];
  const groups = new Map<string, ParsedInvoice>();

  for (const row of rows) {
    if (row.length <= col.item) continue;
    const no = cell(row, col.number);
    const dateStr = cell(row, col.date);
    if (!INVOICE_NO_RE.test(no) || !DATE_RE.test(dateStr)) {
      continue; // header, footnotes, or any misaligned row
    }

    let acc = groups.get(no);
    if (!acc) {
      acc = {
        invoiceNumber: no,
        date: parseDate(dateStr),
        merchantName: nullIfEmpty(cell(row, col.merchant)),
        carrierName: nullIfEmpty(cell(row, col.carrier)),
        sellerAddress: nullIfEmpty(cell(row, col.address)),
        items: [],
      };
      groups.set(no, acc);
      order.push(no);
    }

    const name = cell(row, col.item);
    if (name.length === 0) continue;
    acc.items.push({
      name,
      quantity: toNum(cell(row, col.qty), 1),
      unitPrice: toInt(cell(row, col.unitPrice)),
      amount: toInt(cell(row, col.amount)),
    });
  }

  const out: ParsedInvoice[] = [];
  for (const no of order) {
    const inv = groups.get(no)!;
    if (inv.items.length > 0) out.push(inv);
  }
  return out;
}

interface Columns {
  carrier: number;
  date: number;
  number: number;
  merchant: number;
  address: number;
  qty: number;
  unitPrice: number;
  amount: number;
  item: number;
}

function columnIndex(rows: string[][]): Columns {
  const byName = new Map<string, number>();
  for (const row of rows) {
    const trimmed = row.map((c) => c.trim());
    if (trimmed.includes("發票號碼") && trimmed.includes("消費明細_品名")) {
      trimmed.forEach((c, i) => byName.set(c, i));
      break;
    }
  }
  const idx = (name: string, fallback: number) =>
    byName.has(name) ? byName.get(name)! : fallback;
  return {
    carrier: idx("載具自訂名稱", 0),
    date: idx("發票日期", 1),
    number: idx("發票號碼", 2),
    merchant: idx("賣方名稱", 7),
    address: idx("賣方地址", 8),
    qty: idx("消費明細_數量", 10),
    unitPrice: idx("消費明細_單價", 11),
    amount: idx("消費明細_金額", 12),
    item: idx("消費明細_品名", 13),
  };
}

/// Minimal RFC4180-style CSV row splitter (handles quoted fields + escaped
/// quotes). Matches the `csv` package's behaviour for this export's shape.
function parseCsvRows(text: string): string[][] {
  const rows: string[][] = [];
  let field = "";
  let row: string[] = [];
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += ch;
      }
    } else if (ch === '"') {
      inQuotes = true;
    } else if (ch === ",") {
      row.push(field);
      field = "";
    } else if (ch === "\n") {
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else {
      field += ch;
    }
  }
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows;
}

function cell(row: string[], i: number): string {
  return i < row.length ? row[i].trim() : "";
}

function nullIfEmpty(s: string): string | null {
  return s.length === 0 ? null : s;
}

function parseDate(yyyymmdd: string): string {
  return `${yyyymmdd.slice(0, 4)}-${yyyymmdd.slice(4, 6)}-${yyyymmdd.slice(6, 8)}`;
}

function toInt(s: string): number {
  const t = s.trim();
  if (/^[+-]?\d+$/.test(t)) return parseInt(t, 10);
  const f = parseFloat(t);
  return Number.isNaN(f) ? 0 : Math.round(f);
}

function toNum(s: string, fallback: number): number {
  const t = s.trim();
  if (t === "") return fallback;
  const n = Number(t);
  return Number.isNaN(n) ? fallback : n;
}
