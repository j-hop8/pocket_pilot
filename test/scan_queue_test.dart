import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pp_core/pp_core.dart';

import 'package:pocketpilot/core/providers.dart';
import 'package:pocketpilot/data/invoice_repository.dart';
import 'package:pocketpilot/features/scan/einvoice_qr_service.dart';
import 'package:pocketpilot/features/scan/merchant_lookup_service.dart';
import 'package:pocketpilot/features/scan/scan_queue.dart';
import 'package:pocketpilot/models/category.dart';

/// Fakes [EinvoiceQrService] so the worker never touches Supabase. Methods are
/// plain overrides (the class isn't final), each returning canned results.
class _FakeService extends EinvoiceQrService {
  _FakeService({this.existing = false, this.throwOnSave = false})
      : super(InvoiceRepository());

  final bool existing;
  final bool throwOnSave;

  @override
  Future<bool> alreadyExists(String invoiceNumber) async => existing;

  @override
  Future<int?> defaultCategoryId(
    ParsedQrInvoice qr, {
    required String? merchantName,
    required List<Category> categories,
  }) async =>
      7;

  @override
  Future<String> save(
    ParsedQrInvoice qr, {
    required String? merchantName,
    required int? categoryId,
  }) async {
    if (throwOnSave) throw Exception('boom');
    return 'saved-${qr.invoiceNumber}';
  }
}

class _FakeLookup extends MerchantLookupService {
  @override
  Future<String?> nameForTaxId(String? taxId) async => 'Test Store';
}

ParsedQrInvoice _sample(String number) => ParsedQrInvoice(
      invoiceNumber: number,
      date: DateTime(2026, 6, 1),
      randomCode: '1234',
      salesAmountDollars: 100,
      totalDollars: 100,
      sellerTaxId: '12345678',
      rawLeft: 'x',
    );

ProviderContainer _container(EinvoiceQrService svc) {
  final c = ProviderContainer(overrides: [
    einvoiceQrServiceProvider.overrideWithValue(svc),
    merchantLookupServiceProvider.overrideWithValue(_FakeLookup()),
    categoriesProvider.overrideWith((ref) async => <Category>[]),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// Waits for the fire-and-forget worker to drain the queue.
Future<void> _settle(ProviderContainer c) async {
  for (var i = 0; i < 200; i++) {
    if (c.read(scanQueueProvider).allDone) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('queue did not settle');
}

void main() {
  test('a new invoice is decoded, resolved and saved → done', () async {
    final c = _container(_FakeService());
    c.read(scanQueueProvider.notifier).enqueueParsed(_sample('AB12345678'));
    await _settle(c);

    final job = c.read(scanQueueProvider).jobs.single;
    expect(job.status, ScanJobStatus.done);
    expect(job.savedInvoiceId, 'saved-AB12345678');
    expect(job.merchantName, 'Test Store');
    expect(job.totalDollars, 100);
  });

  test('an already-stored invoice is flagged duplicate (not re-saved)', () async {
    final c = _container(_FakeService(existing: true));
    c.read(scanQueueProvider.notifier).enqueueParsed(_sample('AB12345678'));
    await _settle(c);

    final job = c.read(scanQueueProvider).jobs.single;
    expect(job.status, ScanJobStatus.duplicate);
    expect(job.savedInvoiceId, isNull);
  });

  test('a save error fails just that job', () async {
    final c = _container(_FakeService(throwOnSave: true));
    c.read(scanQueueProvider.notifier).enqueueParsed(_sample('AB12345678'));
    await _settle(c);

    expect(c.read(scanQueueProvider).jobs.single.status, ScanJobStatus.failed);
  });

  test('multiple receipts process sequentially to completion', () async {
    final c = _container(_FakeService());
    final n = c.read(scanQueueProvider.notifier);
    n.enqueueParsed(_sample('AB11111111'));
    n.enqueueParsed(_sample('AB22222222'));
    n.enqueueParsed(_sample('AB33333333'));
    await _settle(c);

    final state = c.read(scanQueueProvider);
    expect(state.total, 3);
    expect(state.finished, 3);
    expect(state.jobs.every((j) => j.status == ScanJobStatus.done), isTrue);
  });

  test('dismissFinished removes terminal jobs and empties the overlay', () async {
    final c = _container(_FakeService());
    c.read(scanQueueProvider.notifier).enqueueParsed(_sample('AB12345678'));
    await _settle(c);

    c.read(scanQueueProvider.notifier).dismissFinished();
    expect(c.read(scanQueueProvider).isEmpty, isTrue);
  });
}
