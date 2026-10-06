import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pp_core/pp_core.dart';

import 'package:pocketpilot/core/providers.dart';
import 'package:pocketpilot/core/settings_provider.dart';
import 'package:pocketpilot/data/invoice_repository.dart';
import 'package:pocketpilot/features/scan/einvoice_qr_service.dart';
import 'package:pocketpilot/features/scan/extracted_receipt.dart';
import 'package:pocketpilot/features/scan/merchant_lookup_service.dart';
import 'package:pocketpilot/features/scan/receipt_extraction_service.dart';
import 'package:pocketpilot/features/scan/receipt_ocr_service.dart';
import 'package:pocketpilot/features/scan/scan_queue.dart';
import 'package:pocketpilot/models/category.dart';
import 'package:pocketpilot/models/trip.dart';

// An e-invoice photo whose QR can't be decoded (e.g. a dense, dithered thermal
// print) falls back to the AI receipt pipeline instead of failing silently.

class _FakeQr extends EinvoiceQrService {
  _FakeQr() : super(InvoiceRepository());

  @override
  Future<bool> alreadyExists(String invoiceNumber) async => false;

  @override
  Future<String> save(
    ParsedQrInvoice qr, {
    required String? merchantName,
    required List<Category> categories,
  }) async => 'saved-${qr.invoiceNumber}';
}

class _FakeLookup extends MerchantLookupService {
  @override
  Future<String?> nameForTaxId(String? taxId) async => 'Test Store';
}

class _FakeExtraction extends ReceiptExtractionService {
  _FakeExtraction({this.throwOnExtract = false, this.throwLimit = false});

  final bool throwOnExtract;
  final bool throwLimit;
  int calls = 0;

  @override
  Future<ExtractedReceipt> extract(
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
    String? targetLang,
    String? currencyHint,
  }) async {
    calls++;
    if (throwLimit) throw const ExtractionLimitReached(30);
    if (throwOnExtract) throw Exception('extract boom');
    return ExtractedReceipt(
      merchantName: 'TSUTAYA BOOKSTORE',
      date: DateTime(2026, 9, 9),
      totalDollars: 1200,
      invoiceNumber: 'FM02316916',
      items: const [],
    );
  }
}

class _FakeOcr extends ReceiptOcrService {
  _FakeOcr({this.existing = false}) : super(InvoiceRepository());

  final bool existing;

  @override
  Future<bool> alreadyExists(String invoiceNumber) async => existing;

  @override
  Future<String> save(
    ExtractedReceipt receipt, {
    required String? merchantName,
    required List<Category> categories,
    Trip? trip,
    double? fxRate,
  }) async => 'saved-ocr';
}

final _bytes = Uint8List.fromList([1, 2, 3]);

ParsedQrInvoice _parsed(String number) => ParsedQrInvoice(
  invoiceNumber: number,
  date: DateTime(2026, 6, 1),
  randomCode: '1234',
  salesAmountDollars: 100,
  totalDollars: 100,
  sellerTaxId: '12345678',
  rawLeft: 'x',
);

ProviderContainer _container({
  required ParsedQrInvoice? decoded,
  required ReceiptExtractionService extraction,
  ReceiptOcrService? ocr,
}) {
  final c = ProviderContainer(
    overrides: [
      einvoiceDecoderProvider.overrideWithValue((_) async => decoded),
      einvoiceQrServiceProvider.overrideWithValue(_FakeQr()),
      merchantLookupServiceProvider.overrideWithValue(_FakeLookup()),
      receiptExtractionServiceProvider.overrideWithValue(extraction),
      receiptOcrServiceProvider.overrideWithValue(ocr ?? _FakeOcr()),
      categoriesProvider.overrideWith((ref) async => <Category>[]),
      activeTripProvider.overrideWith((ref) async => null),
      tripsProvider.overrideWith((ref) async => <Trip>[]),
    ],
  );
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
  test(
    'an unreadable QR photo falls back to AI extraction and saves',
    () async {
      final extraction = _FakeExtraction();
      final c = _container(decoded: null, extraction: extraction);
      c.read(scanQueueProvider.notifier).enqueueImages([_bytes]);
      await _settle(c);

      final job = c.read(scanQueueProvider).jobs.single;
      expect(extraction.calls, 1);
      expect(job.status, ScanJobStatus.done);
      expect(job.savedInvoiceId, 'saved-ocr');
      expect(job.invoiceNumber, 'FM02316916');
      expect(job.merchantName, 'TSUTAYA BOOKSTORE');
      expect(job.totalDollars, 1200);
    },
  );

  test('a readable QR never calls the AI extractor', () async {
    final extraction = _FakeExtraction();
    final c = _container(
      decoded: _parsed('AB12345678'),
      extraction: extraction,
    );
    c.read(scanQueueProvider.notifier).enqueueImages([_bytes]);
    await _settle(c);

    final job = c.read(scanQueueProvider).jobs.single;
    expect(extraction.calls, 0);
    expect(job.status, ScanJobStatus.done);
    expect(job.savedInvoiceId, 'saved-AB12345678');
  });

  test('the fallback dedups on the invoice number the AI read', () async {
    final c = _container(
      decoded: null,
      extraction: _FakeExtraction(),
      ocr: _FakeOcr(existing: true),
    );
    c.read(scanQueueProvider.notifier).enqueueImages([_bytes]);
    await _settle(c);

    final job = c.read(scanQueueProvider).jobs.single;
    expect(job.status, ScanJobStatus.duplicate);
    expect(job.invoiceNumber, 'FM02316916');
  });

  test(
    'a failed fallback fails the job with the unreadable-QR message',
    () async {
      final c = _container(
        decoded: null,
        extraction: _FakeExtraction(throwOnExtract: true),
      );
      c.read(scanQueueProvider.notifier).enqueueImages([_bytes]);
      await _settle(c);

      final job = c.read(scanQueueProvider).jobs.single;
      expect(job.status, ScanJobStatus.failed);
      expect(job.error, startsWith(c.read(stringsProvider).scanQrUnreadable));
    },
  );

  test('a fallback at the daily cap says both', () async {
    final c = _container(
      decoded: null,
      extraction: _FakeExtraction(throwLimit: true),
    );
    c.read(scanQueueProvider.notifier).enqueueImages([_bytes]);
    await _settle(c);

    final job = c.read(scanQueueProvider).jobs.single;
    expect(job.status, ScanJobStatus.failed);
    expect(job.error, c.read(stringsProvider).scanQrUnreadableLimit(30));
  });
}
