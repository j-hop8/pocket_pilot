// Verifies the batched ingest: a multi-invoice CSV becomes a single invoices
// insert + single items insert (not 100+ sequential round-trips), dedup skips
// already-present invoice numbers, and the returned counts/dates are correct.
// Uses a hand-rolled fake of the supabase-js builder that records insert batches
// and answers the category-history reads with empty results (so categorization
// falls back to the keyword categorizer — irrelevant to the counts under test).

import type { SupabaseClient } from "@supabase/supabase-js";
import { expect, test } from "vitest";
import { ingestCsv } from "./ingest";

const HEADER =
  "載具自訂名稱,發票日期,發票號碼,發票金額,發票狀態,折讓,賣方統一編號,賣方名稱,賣方地址,買方統編,消費明細_數量,消費明細_單價,消費明細_金額,消費明細_品名";
// BG13707200 = 1 item (2026-05-30); AG17746093 = 2 items (2026-05-31).
const CSV =
  [
    HEADER,
    "手機條碼,20260530,BG13707200,202,開立已確認,否,69637110,佐亨,桃園,,1,202,202,餐飲費",
    "台新,20260531,AG17746093,30,開立已確認,否,90671330,全家,桃園,,1,30,30,乖乖",
    "台新,20260531,AG17746093,29,開立已確認,否,90671330,全家,桃園,,1,29,29,綠茶",
  ].join("\n") + "\n";

interface Recorded {
  invoices: Record<string, unknown>[][];
  items: Record<string, unknown>[][];
}

// A chainable, thenable stand-in for a PostgREST read builder. select/eq/in/not
// all return `this`; awaiting resolves to a fixed { data, error }.
class Query {
  constructor(private readonly rows: unknown[]) {}
  select() { return this; }
  eq() { return this; }
  in() { return this; }
  not() { return this; }
  then<T>(onF: (v: { data: unknown[]; error: null }) => T): Promise<T> {
    return Promise.resolve({ data: this.rows, error: null }).then(onF);
  }
}

function fakeAdmin(
  existing: string[],
  cats: { id: number; key: string }[] = [{ id: 1, key: "other" }],
): { admin: SupabaseClient; rec: Recorded } {
  const rec: Recorded = { invoices: [], items: [] };
  let seq = 1;
  const admin = {
    from(table: string) {
      if (table === "categories") {
        return { select: () => new Query(cats) };
      }
      if (table === "invoices") {
        return {
          // dedup (.select().eq().in()) and merchant-history (.…in().not()) both
          // read here; history rows carry no category_id so they fold to empty.
          select: () => new Query(existing.map((n) => ({ invoice_number: n }))),
          insert: (rows: Record<string, unknown>[]) => {
            rec.invoices.push(rows);
            const withIds = rows.map((r) => ({ id: `inv-${seq++}`, invoice_number: r.invoice_number }));
            return { select: () => Promise.resolve({ data: withIds, error: null }) };
          },
        };
      }
      if (table === "invoice_items") {
        return {
          // item-history read (.select().eq().in().not()) → no history.
          select: () => new Query([]),
          insert: (rows: Record<string, unknown>[]) => {
            rec.items.push(rows);
            return Promise.resolve({ error: null });
          },
        };
      }
      throw new Error(`unexpected table ${table}`);
    },
  };
  return { admin: admin as unknown as SupabaseClient, rec };
}

test("inserts all invoices + items in one batch each", async () => {
  const { admin, rec } = fakeAdmin([]);
  const result = await ingestCsv(admin, "user-1", CSV);

  expect(result).toMatchObject({ inserted: 2, skipped: 0, items: 3, from: "2026-05-30", to: "2026-05-31" });
  expect(rec.invoices.length).toBe(1);
  expect(rec.invoices[0].length).toBe(2);
  expect(rec.items.length).toBe(1);
  expect(rec.items[0].length).toBe(3);
});

test("skips invoice numbers that already exist", async () => {
  const { admin, rec } = fakeAdmin(["AG17746093"]);
  const result = await ingestCsv(admin, "user-1", CSV);

  expect(result).toMatchObject({ inserted: 1, skipped: 1, items: 1 });
  expect(rec.invoices[0].length).toBe(1);
  expect(rec.invoices[0][0].invoice_number).toBe("BG13707200");
  expect(rec.items[0].length).toBe(1);
});

test("no-ops (no inserts) when everything is already imported", async () => {
  const { admin, rec } = fakeAdmin(["BG13707200", "AG17746093"]);
  const result = await ingestCsv(admin, "user-1", CSV);

  expect(result).toMatchObject({ inserted: 0, skipped: 2, items: 0, from: "2026-05-30", to: "2026-05-31" });
  expect(rec.invoices.length).toBe(0);
  expect(rec.items.length).toBe(0);
});

test("items resolve independently; header falls back to the item-category mode", async () => {
  const cats = [{ id: 2, key: "dining" }, { id: 3, key: "groceries" }];
  const { admin, rec } = fakeAdmin([], cats);
  await ingestCsv(admin, "user-1", CSV);

  const invoices = rec.invoices[0];
  const items = rec.items[0];
  const inv = (n: string) => invoices.find((r) => r.invoice_number === n)!;
  const item = (n: string) => items.find((r) => r.name === n)!;

  // BG13707200: merchant 佐亨 matches no rule, but its item 餐飲費 → dining, so the
  // header takes the item-category mode.
  expect(inv("BG13707200").category_id).toBe(2);
  expect(item("餐飲費").category_id).toBe(2);

  // AG17746093: merchant 全家 → groceries (merchant keyword beats the item mode).
  expect(inv("AG17746093").category_id).toBe(3);
  // Items still resolve on their own name: 綠茶 → dining (茶); 乖乖 matches no rule
  // and stays null — it does NOT inherit the groceries header.
  expect(item("綠茶").category_id).toBe(2);
  expect(item("乖乖").category_id).toBeNull();
});
