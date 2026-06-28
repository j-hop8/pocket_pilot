import 'package:supabase_flutter/supabase_flutter.dart'
    show FunctionException, FunctionResponse;

import '../../core/supabase.dart';
import '../../data/invoice_repository.dart';
import '../../models/category.dart';

/// Thrown when the user has used up their daily auto-categorize quota (the Edge
/// Function answers 429 `{code: 'rate_limited'}`). Carries the server-reported
/// [limit] so the UI can show "N per day".
class CategorizeLimitReached implements Exception {
  const CategorizeLimitReached(this.limit);
  final int limit;

  @override
  String toString() => 'CategorizeLimitReached(limit: $limit)';
}

/// Thrown when a demo (anonymous) account tries to auto-categorize — the Edge
/// Function answers 403, mirroring the demo carrier-sync block.
class CategorizeForbidden implements Exception {
  const CategorizeForbidden();

  @override
  String toString() => 'CategorizeForbidden';
}

/// How many rows each level of the run categorized.
typedef CategorizeOutcome = ({int items, int merchants, int headers});

/// Step 3 of the categorize flow (history → keyword rules → Gemini). Sends the
/// names the cheaper steps couldn't place to the `categorize` Edge Function,
/// writes the AI's choices back, then fills any still-null invoice header from
/// its item-category mode. Keeping the orchestration here (not in the Edge
/// Function) means the DB reads/writes go through [InvoiceRepository] under RLS.
class AutoCategorizeService {
  AutoCategorizeService(this._invoices);

  final InvoiceRepository _invoices;

  /// Runs the AI fallback over the user's uncategorized rows. [categories]
  /// supplies the vocabulary Gemini chooses from and resolves the returned keys
  /// to ids. Returns per-level counts (all zero when there was nothing to do).
  Future<CategorizeOutcome> run(List<Category> categories) async {
    // The sweep only touches expense rows (see InvoiceRepository), so the model
    // only ever chooses from — and we only resolve — expense categories. This
    // keeps an expense key from ever landing on an income row.
    final expense = categories.where((c) => !c.isIncome).toList();
    final itemNames = await _invoices.uncategorizedItemNames();
    final merchants = await _invoices.uncategorizedMerchants();
    if (itemNames.isEmpty && merchants.isEmpty) {
      return (items: 0, merchants: 0, headers: 0);
    }

    final res = await _invoke(
      itemNames: itemNames,
      merchants: merchants,
      categories: expense,
    );

    final catIdByKey = {for (final c in expense) c.key: c.id};
    final itemUpdates = _idMap(res['items'], catIdByKey);
    final merchantUpdates = _idMap(res['merchants'], catIdByKey);

    final items = itemUpdates.isEmpty
        ? 0
        : await _invoices.setItemCategoryByName(itemUpdates);
    final merchants2 = merchantUpdates.isEmpty
        ? 0
        : await _invoices.setMerchantCategoryByName(merchantUpdates);
    // Any header still null can now take the mode of its (freshly-filled) items.
    final headers = await _invoices.fillInvoiceCategoryFromItemMode();

    return (items: items, merchants: merchants2, headers: headers);
  }

  /// Turns a `{name: key}` map from the function into a `{name: categoryId}` map,
  /// dropping entries with a null/unknown key.
  Map<String, int> _idMap(dynamic raw, Map<String, int> catIdByKey) {
    final out = <String, int>{};
    if (raw is Map) {
      raw.forEach((name, key) {
        if (name is String && key is String) {
          final id = catIdByKey[key];
          if (id != null) out[name] = id;
        }
      });
    }
    return out;
  }

  Future<Map<String, dynamic>> _invoke({
    required List<String> itemNames,
    required List<String> merchants,
    required List<Category> categories,
  }) async {
    final FunctionResponse fnRes;
    try {
      fnRes = await supabase.functions.invoke('categorize', body: {
        'items': itemNames,
        'merchants': merchants,
        'categories': [
          for (final c in categories) {'key': c.key, 'label': c.label},
        ],
      });
    } on FunctionException catch (e) {
      // functions_client throws on any non-2xx; map the gated statuses to typed
      // exceptions the UI shows as friendly messages.
      if (e.status == 429) {
        final details = e.details;
        final limit = details is Map && details['limit'] is int
            ? details['limit'] as int
            : 20;
        throw CategorizeLimitReached(limit);
      }
      if (e.status == 403) throw const CategorizeForbidden();
      rethrow;
    }
    final data = fnRes.data;
    if (data is! Map) {
      throw StateError('categorize returned an unexpected response');
    }
    if (data['error'] != null) {
      throw StateError('categorize failed: ${data['error']}');
    }
    return Map<String, dynamic>.from(data);
  }
}
