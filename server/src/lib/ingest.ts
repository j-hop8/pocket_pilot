// Server-side ingestion: mirrors lib/features/carrier_sync/carrier_sync_service.dart
// (importCsv) — parse → auto-categorize → dedupe → insert → record sync — but
// runs with the service-role client and an explicit user_id.

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  invoiceTotalDollars,
  parseEinvoiceCsv,
  type ParsedInvoice,
} from "./einvoice_csv_parser";
import { categorizeKey } from "./categorizer";
import { dollarsToCents } from "./money";

export interface SyncResult {
  inserted: number;
  skipped: number;
  items: number;
  from: string | null;
  to: string | null;
}

/// Ingests [csv] for [userId]. Invoices already present (by invoice number) are
/// skipped, so re-running the same export is a no-op.
export async function ingestCsv(
  admin: SupabaseClient,
  userId: string,
  csv: string,
): Promise<SyncResult> {
  const parsed = parseEinvoiceCsv(csv);
  if (parsed.length === 0) {
    return { inserted: 0, skipped: 0, items: 0, from: null, to: null };
  }

  const { data: cats, error: catErr } = await admin
    .from("categories")
    .select("id, key");
  if (catErr) throw catErr;
  const catIdByKey = new Map<string, number>();
  for (const c of cats ?? []) catIdByKey.set(c.key as string, c.id as number);
  const fallback = catIdByKey.get("other") ?? null;

  const numbers = parsed.map((p) => p.invoiceNumber);
  const { data: existingRows, error: dedupErr } = await admin
    .from("invoices")
    .select("invoice_number")
    .eq("user_id", userId)
    .in("invoice_number", numbers);
  if (dedupErr) throw dedupErr;
  const existing = new Set(
    (existingRows ?? []).map((r) => r.invoice_number as string),
  );

  let inserted = 0;
  let itemCount = 0;
  let from: string | null = null;
  let to: string | null = null; // dates are 'YYYY-MM-DD' → lexicographic order is chronological

  for (const p of parsed) {
    if (from === null || p.date < from) from = p.date;
    if (to === null || p.date > to) to = p.date;
    if (existing.has(p.invoiceNumber)) continue;

    const categoryId = resolveCategory(p, catIdByKey, fallback);
    const rawPayload: Record<string, unknown> = {};
    if (p.carrierName) rawPayload.carrier_name = p.carrierName;
    if (p.sellerAddress) rawPayload.seller_address = p.sellerAddress;

    const { data: invRow, error: invErr } = await admin
      .from("invoices")
      .insert({
        invoice_number: p.invoiceNumber,
        invoice_date: p.date,
        merchant_name: p.merchantName,
        total_amount: dollarsToCents(invoiceTotalDollars(p)),
        currency: "TWD",
        category_id: categoryId,
        source: "carrier",
        raw_payload: rawPayload,
        user_id: userId,
      })
      .select("id")
      .single();
    if (invErr) throw invErr;
    const invoiceId = invRow.id as string;

    if (p.items.length > 0) {
      const itemRows = p.items.map((it, i) => ({
        invoice_id: invoiceId,
        name: it.name,
        quantity: it.quantity,
        unit_price: dollarsToCents(it.unitPrice),
        amount: dollarsToCents(it.amount),
        category_id: categoryId,
        sort_order: i,
        user_id: userId,
      }));
      const { error: itemErr } = await admin.from("invoice_items").insert(itemRows);
      if (itemErr) throw itemErr;
      itemCount += itemRows.length;
    }
    inserted++;
  }

  return {
    inserted,
    skipped: parsed.length - inserted,
    items: itemCount,
    from,
    to,
  };
}

function resolveCategory(
  p: ParsedInvoice,
  catIdByKey: Map<string, number>,
  fallback: number | null,
): number | null {
  const key = categorizeKey(p.merchantName, p.items.map((i) => i.name));
  return catIdByKey.get(key) ?? fallback;
}
