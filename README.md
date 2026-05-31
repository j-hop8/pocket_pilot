# PocketPilot

A Taiwan expense tracker (Flutter + Supabase). Track spending by category from a
dashboard, browse invoice history, add invoices manually, and sync invoices from
the Ministry of Finance (財政部) e-invoice carrier.

## Features

- **Dashboard** — monthly spend total + by-category breakdown (pie chart).
- **History** — all invoices with line-item detail.
- **Manual entry** — add an invoice with items.
- **E-Invoice Carrier Sync** (Feature 1) — import the MOF carrier CSV
  (消費明細 export): parses headers + line items, auto-assigns a category, and
  stores them in Supabase, deduped by invoice number. Carrier login credentials
  are entered + saved on the same screen for the future auto-sync path.

## Run

```sh
cp dart_defines.example.json dart_defines.json   # fill in your Supabase URL + anon key
flutter pub get
flutter run -d chrome --dart-define-from-file=dart_defines.json
```

See [`supabase/README.md`](supabase/README.md) for the database schema,
migrations, and the carrier-sync credential security notes.

## Test

```sh
flutter test       # includes the e-invoice CSV parser + categorizer tests
flutter analyze
```
