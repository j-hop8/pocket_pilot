// Parity test for the TS parser/categorizer ports. Uses the SAME fixture +
// expectations as the Dart test (test/einvoice_csv_parser_test.dart) so the two
// implementations stay in lockstep. Run with: `npm test`.

import { test, expect } from "vitest";
import {
  invoiceTotalDollars,
  parseEinvoiceCsv,
} from "./einvoice_csv_parser";
import { categorizeKey } from "./categorizer";

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

test("groups line items by invoice number, skipping header + footnotes", () => {
  const invoices = parseEinvoiceCsv(sample);
  expect(invoices.length).toEqual(2);
  const numbers = invoices.map((i) => i.invoiceNumber);
  expect(numbers).toContain("BG13707200");
  expect(numbers).toContain("AG17746093");
});

test("single-line invoice: total = line amount", () => {
  const inv = parseEinvoiceCsv(sample).find((i) => i.invoiceNumber === "BG13707200")!;
  expect(inv.items.length).toEqual(1);
  expect(invoiceTotalDollars(inv)).toEqual(202);
  expect(inv.merchantName).toEqual("佐亨國際有限公司");
  expect(inv.carrierName).toEqual("手機條碼");
  expect(inv.date).toEqual("2026-05-30");
});

test("multi-line invoice: total = sum of lines (discount nets out)", () => {
  const inv = parseEinvoiceCsv(sample).find((i) => i.invoiceNumber === "AG17746093")!;
  expect(inv.items.length).toEqual(5);
  // 30 + 29 + 45 + 30 - 22 = 112 (NOT the per-line 發票金額 column).
  expect(invoiceTotalDollars(inv)).toEqual(112);
  expect(inv.items[inv.items.length - 1].amount).toEqual(-22);
});

test("empty input is handled", () => {
  expect(parseEinvoiceCsv("")).toEqual([]);
});

test("convenience store → groceries (merchant wins over food items)", () => {
  expect(categorizeKey("全家便利商店股份有限公司", ["御茶園綠茶"])).toEqual("groceries");
});

test("restaurant merchant → dining", () => {
  expect(categorizeKey("中羽餐飲貿易有限公司", ["神醬燒蔥肉串"])).toEqual("dining");
});

test("falls back to item keywords when merchant is unknown", () => {
  expect(categorizeKey("佐亨國際有限公司", ["餐飲費"])).toEqual("dining");
});

test("gas station → transport", () => {
  expect(categorizeKey("台灣中油股份有限公司", ["92無鉛汽油"])).toEqual("transport");
});

test("no signal → other", () => {
  expect(categorizeKey("ACME Corp", ["widget"])).toEqual("other");
});
