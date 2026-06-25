# PocketPilot

> A Taiwan-first personal expense tracker — scan an e-invoice or snap a receipt, and your spending sorts itself out.

**English** · [繁體中文](README.zh-TW.md)

PocketPilot turns the everyday paperwork of spending in Taiwan into a tidy, searchable
ledger. It speaks the local format natively — Ministry of Finance (財政部) **e-invoices**
and the **carrier (載具)** — and falls back to an AI receipt reader for everything else,
so a photo of any receipt becomes a structured record with line items and a category.
It's built with Flutter and Supabase.

## 🚀 Live demo

**Live demo:** https://pocketpilot.pocketpilot.workers.dev/

## ✨ Features

- **Dashboard** — this month's total spend and transaction count, with a by-category
  pie chart and a clear income-vs-expense split.
- **AI receipt scanning** — snap or upload a photo of any receipt and it's read
  server-side into structured fields (merchant, total, items). Handles a wide range of
  receipt formats and languages, so you're not locked to one layout.
- **Taiwan e-invoice QR scan** — scan the QR codes on Taiwan e-invoices, including a
  Big5 decoder for the item names many local POS systems emit.
- **E-invoice carrier sync** — import your MOF carrier (載具) statement: invoices and
  line items are parsed, auto-categorized, and de-duplicated by invoice number, with an
  always-on backend for scheduled auto-sync.
- **History & detail** — browse every invoice with filters, and drill into full
  line-item detail.
- **Manual entry** — add or edit an invoice and its items by hand when you need to.
- **Custom categories** — use the built-in categories or create your own with a custom
  icon and color.
- **Bilingual** — full Traditional Chinese (繁體中文) and English throughout the app.

## 🗺️ Roadmap

Where PocketPilot is headed next:

- [ ] **Smarter auto-categorization** — automatic, AI-assisted categorization across
  every way you add a transaction, not just carrier imports.
- [ ] **Budgets** — set monthly and per-category budgets and track spending against them.
- [ ] **Overseas-trip expenses** — record foreign-currency spending with exchange-rate
  conversion. (The AI receipt reader already copes with other languages and formats, so
  foreign receipts aren't a blocker.)
- [ ] **Payment methods** — tag how each transaction was paid (cash, card, …) and break
  spending down by method.
- [ ] **Reconciliation** — match your records against your bank's monthly statement to
  catch missing, duplicate, or mismatched transactions.
- [ ] **Native mobile apps** — iOS and Android builds from the same Flutter codebase
  (today PocketPilot ships as the web app).

## 🧱 Tech stack

| Layer | Technology |
| --- | --- |
| App | Flutter (Dart) |
| Backend / data | Supabase (Postgres, Auth, Edge Functions) |
| AI receipt OCR | Gemini, via a Supabase Edge Function |
| Carrier auto-sync | Node + TypeScript, Playwright |
| Hosting | Cloudflare Pages (web), GitHub Actions CI/CD |
