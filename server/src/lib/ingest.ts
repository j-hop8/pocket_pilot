// Server-side ingestion: mirrors lib/features/carrier_sync/carrier_sync_service.dart
// (importCsv) — parse → auto-categorize → dedupe → insert → record sync — but
// runs with the service-role client and an explicit user_id.

import type { SupabaseClient } from "@supabase/supabase-js";
import { invoiceTotalDollars, parseEinvoiceCsv } from "./einvoice_csv_parser";
import { categorizeKey } from "./categorizer";
import {
  distinctTrimmed,
  foldMostRecentCategory,
  type HistoryRow,
  resolveInvoiceCategory,
  resolveItemCategory,
} from "./category_resolver";
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

  // Categories are per-user now (the admin client bypasses RLS, so scope by hand).
  const { data: cats, error: catErr } = await admin
    .from("categories")
    .select("id, key")
    .eq("user_id", userId);
  if (catErr) throw catErr;
  const catIdByKey = new Map<string, number>();
  for (const c of cats ?? []) catIdByKey.set(c.key as string, c.id as number);
  const fallback = catIdByKey.get("other") ?? null;

  // Learn from the user's own history first: an item or merchant they've
  // categorized before keeps that category (item wins over merchant); the keyword
  // categorizer is only the fallback. Most-recent past choice wins.
  const itemHist = await recentCategoryByItemName(
    admin,
    userId,
    parsed.flatMap((p) => p.items.map((i) => i.name)),
  );
  const merchantHist = await recentCategoryByMerchant(
    admin,
    userId,
    parsed.map((p) => p.merchantName).filter((m): m is string => m !== null),
  );

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

    // Keyword categorizer result (current logic) — fallback for items/merchants
    // with no history. Header reflects the whole receipt: merchant history → keyword.
    const keywordCatId =
      catIdByKey.get(categorizeKey(p.merchantName, p.items.map((i) => i.name))) ??
      fallback;
    const categoryId = resolveInvoiceCategory(
      p.merchantName,
      merchantHist,
      keywordCatId,
    );
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
        // Per item: its own history → merchant history → keyword.
        category_id: resolveItemCategory(
          it.name,
          p.merchantName,
          itemHist,
          merchantHist,
          keywordCatId,
        ),
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

// ── Category history (learning from past categorizations) ────────────────────
// Mirrors lib/data/invoice_repository.dart. Scoped to userId by hand (the admin
// client bypasses RLS); the most-recent-wins reduction lives in category_resolver.

/// Most-recent category_id the user assigned to a line item with each name.
/// Item recency comes from the parent invoice (items carry no timestamp).
async function recentCategoryByItemName(
  admin: SupabaseClient,
  userId: string,
  names: string[],
): Promise<Map<string, number>> {
  const distinct = distinctTrimmed(names);
  if (distinct.length === 0) return new Map();
  const { data, error } = await admin
    .from("invoice_items")
    .select("name, category_id, invoices!inner(invoice_date, created_at)")
    .eq("user_id", userId)
    .in("name", distinct)
    .not("category_id", "is", null);
  if (error) throw error;
  return foldMostRecentCategory(
    // deno-lint-ignore no-explicit-any
    (data ?? []).map((r: any): HistoryRow => ({
      key: r.name,
      categoryId: r.category_id,
      stamp: stampOf(r.invoices),
    })),
  );
}

/// Most-recent category_id the user assigned to invoices from each merchant.
async function recentCategoryByMerchant(
  admin: SupabaseClient,
  userId: string,
  merchants: string[],
): Promise<Map<string, number>> {
  const distinct = distinctTrimmed(merchants);
  if (distinct.length === 0) return new Map();
  const { data, error } = await admin
    .from("invoices")
    .select("merchant_name, category_id, invoice_date, created_at")
    .eq("user_id", userId)
    .in("merchant_name", distinct)
    .not("category_id", "is", null);
  if (error) throw error;
  return foldMostRecentCategory(
    // deno-lint-ignore no-explicit-any
    (data ?? []).map((r: any): HistoryRow => ({
      key: r.merchant_name,
      categoryId: r.category_id,
      stamp: stampOf(r),
    })),
  );
}

/// 'invoice_date|created_at' — both ISO strings, so string compare is chronological.
function stampOf(rec: Record<string, unknown> | null | undefined): string {
  const r = rec ?? {};
  return `${r.invoice_date ?? ""}|${r.created_at ?? ""}`;
}
