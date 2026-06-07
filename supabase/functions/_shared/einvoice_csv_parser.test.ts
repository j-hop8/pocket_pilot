// Parity test for the TS parser/categorizer ports. Uses the SAME fixture +
// expectations as the Dart test (test/einvoice_csv_parser_test.dart) so the two
// implementations stay in lockstep. Run with: `deno test supabase/functions`.

import {
  assertEquals,
  assert,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  invoiceTotalDollars,
  parseEinvoiceCsv,
} from "./einvoice_csv_parser.ts";
import { categorizeKey } from "./categorizer.ts";

// Real-format sample (UTF-8 BOM, header row, 2 trailing footnote lines). One
// single-line invoice and one multi-line invoice with a negative discount line.
const sample = "﻿" +
  "載具自訂名稱,發票日期,發票號碼,發票金額,發票狀態,折讓,賣方統一編號,賣方名稱,賣方地址,買方統編,消費明細_數量,消費明細_單價,消費明細_金額,消費明細_品名\n" +
  "手機條碼,20260530,BG13707200,202,開立已確認,否,69637110,佐亨國際有限公司,桃園市蘆竹區長安路二段226號1樓,,1,202,202,餐飲費\n" +
  "台新,20260530,AG17746093,30,開立已確認,否,90671330,全家便利商店股份有限公司,桃園市大園區春德路128號1樓,,1,30,30,乖乖玉米脆條\n" +
  "台新,20260530,AG17746093,29,開立已確認,否,90671330,全家便利商店股份有限公司,桃園市大園區春德路128號1樓,,1,29,29,御茶園特撰冰釀綠茶\n" +
  "台新,20260530,AG17746093,45,開立已確認,否,90671330,全家便利商店股份有限公司,桃園市大園區春德路128號1樓,,1,45,45,二配壹號醬炙烤牛飯糰\n" +
  "台新,20260530,AG17746093,30,開立已確認,否,90671330,全家便利商店股份有限公司,桃園市大園區春德路128號1樓,,1,30,30,二配鮪魚飯糰\n" +
  "台新,20260530,AG17746093,-22,開立已確認,否,90671330,全家便利商店股份有限公司,桃園市大園區春德路128號1樓,,1,0,-22,友善食光折扣\n" +
  "捐贈或作廢之發票，字軌號碼均會隱末3碼\n" +
  "注意：本功能所下載之雲端發票明細檔案可能因賣方營業人後續作廢或折讓等原因而產生誤差。\n";

Deno.test("groups line items by invoice number, skipping header + footnotes", () => {
  const invoices = parseEinvoiceCsv(sample);
  assertEquals(invoices.length, 2);
  const numbers = invoices.map((i) => i.invoiceNumber);
  assert(numbers.includes("BG13707200"));
  assert(numbers.includes("AG17746093"));
});

Deno.test("single-line invoice: total = line amount", () => {
  const inv = parseEinvoiceCsv(sample).find((i) => i.invoiceNumber === "BG13707200")!;
  assertEquals(inv.items.length, 1);
  assertEquals(invoiceTotalDollars(inv), 202);
  assertEquals(inv.merchantName, "佐亨國際有限公司");
  assertEquals(inv.carrierName, "手機條碼");
  assertEquals(inv.date, "2026-05-30");
});

Deno.test("multi-line invoice: total = sum of lines (discount nets out)", () => {
  const inv = parseEinvoiceCsv(sample).find((i) => i.invoiceNumber === "AG17746093")!;
  assertEquals(inv.items.length, 5);
  // 30 + 29 + 45 + 30 - 22 = 112 (NOT the per-line 發票金額 column).
  assertEquals(invoiceTotalDollars(inv), 112);
  assertEquals(inv.items[inv.items.length - 1].amount, -22);
});

Deno.test("empty input is handled", () => {
  assertEquals(parseEinvoiceCsv(""), []);
});

Deno.test("convenience store → groceries (merchant wins over food items)", () => {
  assertEquals(categorizeKey("全家便利商店股份有限公司", ["御茶園綠茶"]), "groceries");
});

Deno.test("restaurant merchant → dining", () => {
  assertEquals(categorizeKey("中羽餐飲貿易有限公司", ["神醬燒蔥肉串"]), "dining");
});

Deno.test("falls back to item keywords when merchant is unknown", () => {
  assertEquals(categorizeKey("佐亨國際有限公司", ["餐飲費"]), "dining");
});

Deno.test("gas station → transport", () => {
  assertEquals(categorizeKey("台灣中油股份有限公司", ["92無鉛汽油"]), "transport");
});

Deno.test("no signal → other", () => {
  assertEquals(categorizeKey("ACME Corp", ["widget"]), "other");
});
