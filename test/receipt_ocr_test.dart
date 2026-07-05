import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketpilot/core/providers.dart';
import 'package:pocketpilot/core/settings_provider.dart';
import 'package:pocketpilot/data/invoice_repository.dart';
import 'package:pocketpilot/features/scan/extracted_receipt.dart';
import 'package:pocketpilot/features/scan/receipt_extraction_service.dart';
import 'package:pocketpilot/features/scan/receipt_ocr_service.dart';
import 'package:pocketpilot/features/scan/scan_queue.dart';
import 'package:pocketpilot/models/category.dart';
import 'package:pocketpilot/models/trip.dart';

/// Fakes the Gemini call so the worker never touches the Edge Function.
class _FakeExtraction extends ReceiptExtractionService {
  _FakeExtraction({
    this.receipt,
    this.throwOnExtract = false,
    this.throwLimit = false,
  });

  final ExtractedReceipt? receipt;
  final bool throwOnExtract;
  final bool throwLimit;

  /// The [targetLang] passed to the last [extract] — lets a test assert that
  /// translation is requested.
  String? lastTargetLang;

  @override
  Future<ExtractedReceipt> extract(
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
    String? targetLang,
    String? currencyHint,
  }) async {
    lastTargetLang = targetLang;
    if (throwLimit) throw const ExtractionLimitReached(30);
    if (throwOnExtract) throw Exception('extract boom');
    return receipt!;
  }
}

/// Fakes the ingest so it never touches Supabase. Plain overrides return canned
/// results (the class isn't final).
class _FakeOcr extends ReceiptOcrService {
  _FakeOcr({this.existing = false, this.throwOnSave = false})
      : super(InvoiceRepository());

  final bool existing;
  final bool throwOnSave;

  /// The trip passed to the last [save] — lets a test assert which trip a
  /// scanned receipt was assigned to.
  Trip? lastTrip;

  @override
  Future<bool> alreadyExists(String invoiceNumber) async => existing;

  @override
  Future<String> save(
    ExtractedReceipt receipt, {
    required String? merchantName,
    required List<Category> categories,
    Trip? trip,
    double? fxRate,
  }) async {
    if (throwOnSave) throw Exception('save boom');
    lastTrip = trip;
    return 'saved-ocr';
  }
}

ExtractedReceipt _sample({String? invoiceNumber}) => ExtractedReceipt(
      merchantName: 'Corner Cafe',
      date: DateTime(2026, 6, 1),
      totalDollars: 120,
      invoiceNumber: invoiceNumber,
      items: const [],
    );

final _bytes = Uint8List.fromList([1, 2, 3]);

Trip _trip(String id, String currency, DateTime start, DateTime end) => Trip(
      id: id,
      name: id,
      countryCode: 'XX',
      currencyCode: currency,
      startDate: start,
      endDate: end,
    );

ProviderContainer _container({
  required ReceiptExtractionService extraction,
  required ReceiptOcrService ocr,
}) {
  final c = ProviderContainer(overrides: [
    receiptExtractionServiceProvider.overrideWithValue(extraction),
    receiptOcrServiceProvider.overrideWithValue(ocr),
    categoriesProvider.overrideWith((ref) async => <Category>[]),
    // No active trip / no trips → the worker runs the domestic path (no
    // Supabase, no FX) and finds no trip to assign by date.
    activeTripProvider.overrideWith((ref) async => null),
    tripsProvider.overrideWith((ref) async => <Trip>[]),
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
  test('a receipt photo is extracted, resolved and saved → done', () async {
    final c = _container(
      extraction: _FakeExtraction(receipt: _sample()),
      ocr: _FakeOcr(),
    );
    c.read(scanQueueProvider.notifier).enqueueReceiptImages([_bytes]);
    await _settle(c);

    final job = c.read(scanQueueProvider).jobs.single;
    expect(job.kind, ScanJobKind.receipt);
    expect(job.status, ScanJobStatus.done);
    expect(job.savedInvoiceId, 'saved-ocr');
    expect(job.merchantName, 'Corner Cafe');
    expect(job.totalDollars, 120);
  });

  test('an extraction failure fails just that job', () async {
    final c = _container(
      extraction: _FakeExtraction(throwOnExtract: true),
      ocr: _FakeOcr(),
    );
    c.read(scanQueueProvider.notifier).enqueueReceiptImages([_bytes]);
    await _settle(c);

    expect(c.read(scanQueueProvider).jobs.single.status, ScanJobStatus.failed);
  });

  test('an extracted e-invoice number that already exists → duplicate', () async {
    final c = _container(
      extraction: _FakeExtraction(receipt: _sample(invoiceNumber: 'AB12345678')),
      ocr: _FakeOcr(existing: true),
    );
    c.read(scanQueueProvider.notifier).enqueueReceiptImages([_bytes]);
    await _settle(c);

    final job = c.read(scanQueueProvider).jobs.single;
    expect(job.status, ScanJobStatus.duplicate);
    expect(job.savedInvoiceId, isNull);
  });

  test('a receipt with no invoice number never dedups → saved', () async {
    // existing:true would only matter if alreadyExists were consulted; without
    // an invoice number it must be skipped and the receipt saved.
    final c = _container(
      extraction: _FakeExtraction(receipt: _sample()),
      ocr: _FakeOcr(existing: true),
    );
    c.read(scanQueueProvider.notifier).enqueueReceiptImages([_bytes]);
    await _settle(c);

    expect(c.read(scanQueueProvider).jobs.single.status, ScanJobStatus.done);
  });

  test('hitting the daily quota fails the job with a friendly message', () async {
    final c = _container(
      extraction: _FakeExtraction(throwLimit: true),
      ocr: _FakeOcr(),
    );
    c.read(scanQueueProvider.notifier).enqueueReceiptImages([_bytes]);
    await _settle(c);

    final job = c.read(scanQueueProvider).jobs.single;
    expect(job.status, ScanJobStatus.failed);
    // Not the raw exception — the localized "daily limit reached" string,
    // carrying the server-reported limit (30 from the fake).
    expect(job.error, c.read(stringsProvider).scanLimitReached(30));
  });

  test('a save error fails just that job', () async {
    final c = _container(
      extraction: _FakeExtraction(receipt: _sample()),
      ocr: _FakeOcr(throwOnSave: true),
    );
    c.read(scanQueueProvider.notifier).enqueueReceiptImages([_bytes]);
    await _settle(c);

    expect(c.read(scanQueueProvider).jobs.single.status, ScanJobStatus.failed);
  });

  test('translation is requested for every receipt, even with no trip',
      () async {
    // _container overrides activeTripProvider + tripsProvider to empty, so there
    // is no trip context at all — targetLang must still be sent so any foreign
    // merchant / items get translated.
    final extraction = _FakeExtraction(receipt: _sample());
    final c = _container(extraction: extraction, ocr: _FakeOcr());
    c.read(scanQueueProvider.notifier).enqueueReceiptImages([_bytes]);
    await _settle(c);

    expect(c.read(scanQueueProvider).jobs.single.status, ScanJobStatus.done);
    expect(extraction.lastTargetLang, isNotNull);
  });

  test('scanning from a trip forces that trip, overriding the receipt date',
      () async {
    // The sample receipt is dated 2026-06-01 — outside this trip's range, so a
    // date match would NOT pick it. The forced trip must win anyway.
    final forced = _trip('jp', 'JPY', DateTime(2026, 1, 1), DateTime(2026, 1, 5));
    final ocr = _FakeOcr();
    final c = _container(
      extraction: _FakeExtraction(receipt: _sample()),
      ocr: ocr,
    );
    c.read(scanQueueProvider.notifier).enqueueReceiptImages([_bytes], trip: forced);
    await _settle(c);

    expect(c.read(scanQueueProvider).jobs.single.status, ScanJobStatus.done);
    expect(ocr.lastTrip?.id, 'jp');
  });

  group('tripForReceipt (assign by receipt date)', () {
    // jp and kr overlap on 6/8–6/10.
    final jp = _trip('jp', 'JPY', DateTime(2026, 6, 1), DateTime(2026, 6, 10));
    final kr = _trip('kr', 'KRW', DateTime(2026, 6, 8), DateTime(2026, 6, 15));

    test('date inside exactly one trip → that trip', () {
      expect(tripForReceipt([jp, kr], DateTime(2026, 6, 3), 'JPY')?.id, 'jp');
      expect(tripForReceipt([jp, kr], DateTime(2026, 6, 13), 'KRW')?.id, 'kr');
    });

    test('date in no trip → null (undecided)', () {
      expect(tripForReceipt([jp, kr], DateTime(2026, 7, 1), 'JPY'), isNull);
      expect(tripForReceipt(const [], DateTime(2026, 6, 3), 'JPY'), isNull);
    });

    test('date in several trips → currency picks the matching one', () {
      // 6/9 is covered by both trips; the receipt currency disambiguates.
      expect(tripForReceipt([jp, kr], DateTime(2026, 6, 9), 'JPY')?.id, 'jp');
      expect(tripForReceipt([jp, kr], DateTime(2026, 6, 9), 'KRW')?.id, 'kr');
    });

    test('currency match is case-insensitive', () {
      expect(tripForReceipt([jp, kr], DateTime(2026, 6, 9), 'jpy')?.id, 'jp');
    });

    test('date in several trips, currency matches none → null', () {
      expect(tripForReceipt([jp, kr], DateTime(2026, 6, 9), 'USD'), isNull);
    });

    test('date in several trips sharing a currency → null (ambiguous)', () {
      final fr = _trip('fr', 'EUR', DateTime(2026, 6, 1), DateTime(2026, 6, 10));
      final de = _trip('de', 'EUR', DateTime(2026, 6, 5), DateTime(2026, 6, 15));
      expect(tripForReceipt([fr, de], DateTime(2026, 6, 7), 'EUR'), isNull);
    });
  });
}
