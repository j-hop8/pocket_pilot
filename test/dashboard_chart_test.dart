import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:pocketpilot/core/providers.dart';
import 'package:pocketpilot/core/settings_provider.dart';
import 'package:pocketpilot/core/strings.dart';
import 'package:pocketpilot/core/theme.dart';
import 'package:pocketpilot/features/dashboard/dashboard_screen.dart';
import 'package:pocketpilot/models/budget.dart';
import 'package:pocketpilot/models/category.dart';
import 'package:pocketpilot/models/invoice.dart';

/// Renders the real [DashboardScreen] with stubbed providers to verify the
/// unified budget + category card: budgeted categories show spent/limit progress
/// (persimmon + "over by" when exceeded) and non-budgeted categories show a
/// plain spend bar. The donut chart is gone.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final now = DateTime.now();
  const en = AppStrings(AppLang.en);

  final cats = <int, Category>{
    1: const Category(id: 1, key: 'dining', label: 'Dining'),
    2: const Category(id: 2, key: 'transport', label: 'Transport'),
    3: const Category(id: 3, key: 'shopping', label: 'Shopping'),
  };

  // Expenses: dining 300, transport 200, shopping 100 (total 600) + income 500.
  Invoice exp(int cat, int cents) =>
      Invoice(invoiceDate: now, totalAmount: cents, source: 'manual', categoryId: cat);
  final invoices = <Invoice>[
    exp(1, 30000),
    exp(2, 20000),
    exp(3, 10000),
    Invoice(invoiceDate: now, totalAmount: 50000, source: 'manual', kind: 'income'),
  ];

  Widget app({
    required List<Invoice> data,
    required Map<int?, Budget> budgets,
  }) =>
      ProviderScope(
        overrides: [
          invoiceListProvider.overrideWith((ref) => data),
          categoriesByIdProvider.overrideWith((ref) => cats),
          budgetsByCategoryProvider.overrideWith((ref) => budgets),
          stringsProvider.overrideWithValue(en),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: DashboardScreen()),
        ),
      );

  testWidgets('budgeted + non-budgeted rows render with a % status',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    await tester.pumpWidget(app(
      data: invoices,
      budgets: {
        // Overall cap 500 < spend 600 → 120% (over).
        null: const Budget(id: 10, categoryId: null, amount: 50000),
        // Dining budget 200 < spend 300 → 150% (over).
        1: const Budget(id: 11, categoryId: 1, amount: 20000),
        // Transport budget 400 > spend 200 → 50% (forecast, under budget).
        2: const Budget(id: 12, categoryId: 2, amount: 40000),
      },
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // Bar chart restored, no donut leftovers.
    expect(find.byType(LinearProgressIndicator), findsAtLeastNWidgets(3));
    expect(find.text('EXPENSE'), findsNothing);

    // A divider separates the overall (total) budget from the category rows.
    expect(find.byType(Divider), findsOneWidget);

    // Overall cap row: spent/limit + "120% · Over by NT$100".
    expect(find.text(en.spentOfText(60000, 50000)), findsOneWidget); // NT$600 / NT$500
    expect(find.text('120% · ${en.overByText(10000)}'), findsOneWidget);

    // Dining over: "150% · Over by NT$100".
    expect(find.text(en.spentOfText(30000, 20000)), findsOneWidget); // NT$300 / NT$200
    expect(find.text('150% · ${en.overByText(10000)}'), findsOneWidget);

    // Transport under: "50% · NT$200 left" — the forecast case.
    expect(find.text(en.spentOfText(20000, 40000)), findsOneWidget); // NT$200 / NT$400
    expect(find.text('50% · ${en.remainingText(20000)}'), findsOneWidget);

    // Shopping has no budget → plain spend bar with just the amount.
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('no budgets: every spending category shows a plain bar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    await tester.pumpWidget(app(data: invoices, budgets: const {}));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(LinearProgressIndicator), findsAtLeastNWidgets(3));
    expect(find.text('Dining'), findsOneWidget);
    expect(find.text('300'), findsOneWidget); // dining plain amount
    // No budget => no spent/limit text anywhere.
    expect(find.text(en.spentOfText(30000, 20000)), findsNothing);
    // No overall budget => no divider.
    expect(find.byType(Divider), findsNothing);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('income-only, no budgets: shows the set-a-budget prompt, no crash',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(app(
      data: [
        Invoice(invoiceDate: now, totalAmount: 50000, source: 'manual', kind: 'income'),
      ],
      budgets: const {},
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(en.setABudgetCta), findsOneWidget);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
