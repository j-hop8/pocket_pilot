import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pp_core/pp_core.dart';

import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import 'receipt_extraction_service.dart';
import 'scan_decoder.dart';

/// Lifecycle of one queued receipt: waiting → being read → a terminal outcome.
enum ScanJobStatus { pending, processing, done, duplicate, failed }

/// Which pipeline a byte-job goes through: decode an e-invoice QR locally, or
/// send the photo to Gemini for OCR extraction. (Live-camera jobs are always
/// e-invoice and arrive pre-[parsed].)
enum ScanJobKind { einvoice, receipt }

/// A single receipt to ingest in the background. Carries either raw image
/// [bytes] (photo / gallery / web-capture, processed by the worker) or an
/// already-[parsed] invoice (live-camera detection, which hands us the QR
/// payloads directly so no decode is needed). [kind] selects which pipeline a
/// byte-job runs through.
@immutable
class ScanJob {
  final int id;
  final ScanJobStatus status;
  final ScanJobKind kind;
  final Uint8List? bytes;
  final ParsedQrInvoice? parsed;
  final String? invoiceNumber;
  final String? merchantName;
  final String? savedInvoiceId;
  final String? error;
  final int? totalDollars;

  const ScanJob({
    required this.id,
    required this.status,
    this.kind = ScanJobKind.einvoice,
    this.bytes,
    this.parsed,
    this.invoiceNumber,
    this.merchantName,
    this.savedInvoiceId,
    this.error,
    this.totalDollars,
  });

  bool get isFinished =>
      status == ScanJobStatus.done ||
      status == ScanJobStatus.duplicate ||
      status == ScanJobStatus.failed;

  ScanJob copyWith({
    ScanJobStatus? status,
    ParsedQrInvoice? parsed,
    String? invoiceNumber,
    String? merchantName,
    String? savedInvoiceId,
    String? error,
    int? totalDollars,
  }) {
    return ScanJob(
      id: id,
      status: status ?? this.status,
      kind: kind,
      bytes: bytes,
      parsed: parsed ?? this.parsed,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      merchantName: merchantName ?? this.merchantName,
      savedInvoiceId: savedInvoiceId ?? this.savedInvoiceId,
      error: error ?? this.error,
      totalDollars: totalDollars ?? this.totalDollars,
    );
  }
}

@immutable
class ScanQueueState {
  final List<ScanJob> jobs;
  final bool minimized;

  const ScanQueueState({required this.jobs, required this.minimized});

  bool get isEmpty => jobs.isEmpty;
  int get total => jobs.length;
  int get finished => jobs.where((j) => j.isFinished).length;

  /// True while any job is still pending or being read.
  bool get active => jobs.any((j) =>
      j.status == ScanJobStatus.pending ||
      j.status == ScanJobStatus.processing);

  /// True when there's at least one job and they've all reached a terminal state.
  bool get allDone => jobs.isNotEmpty && !active;

  ScanQueueState copyWith({List<ScanJob>? jobs, bool? minimized}) =>
      ScanQueueState(
        jobs: jobs ?? this.jobs,
        minimized: minimized ?? this.minimized,
      );
}

/// App-lifetime queue that ingests scanned e-invoices in the background, one at
/// a time. UI only enqueues and watches; the worker ([_pump]) decodes → dedups →
/// resolves merchant + category → saves, mirroring the old (blocking) review-sheet
/// flow but without any modal — receipts are auto-saved and edited later.
///
/// Deliberately a plain (non-autoDispose) [Notifier] so processing keeps running
/// across tab switches and the scanner panel being disposed.
class ScanQueue extends Notifier<ScanQueueState> {
  int _nextId = 0;
  bool _pumping = false;

  @override
  ScanQueueState build() => const ScanQueueState(jobs: [], minimized: false);

  /// Queue raw photos (gallery multi-select, recent thumbnails, web capture).
  void enqueueImages(List<Uint8List> images) {
    if (images.isEmpty) return;
    final added = [
      for (final bytes in images)
        ScanJob(id: _nextId++, status: ScanJobStatus.pending, bytes: bytes),
    ];
    state = state.copyWith(jobs: [...state.jobs, ...added], minimized: false);
    _pump();
  }

  /// Queue raw receipt / invoice photos for background AI extraction + save
  /// (the OCR path: photo → Gemini → store as `ocr`). Same shape as
  /// [enqueueImages] but tagged so the worker runs the receipt pipeline.
  void enqueueReceiptImages(List<Uint8List> images) {
    if (images.isEmpty) return;
    final added = [
      for (final bytes in images)
        ScanJob(
          id: _nextId++,
          status: ScanJobStatus.pending,
          kind: ScanJobKind.receipt,
          bytes: bytes,
        ),
    ];
    state = state.copyWith(jobs: [...state.jobs, ...added], minimized: false);
    _pump();
  }

  /// Queue an already-parsed invoice from the live camera (no decode needed).
  void enqueueParsed(ParsedQrInvoice qr) {
    final job = ScanJob(
      id: _nextId++,
      status: ScanJobStatus.pending,
      parsed: qr,
      invoiceNumber: qr.invoiceNumber,
      totalDollars: qr.totalDollars,
    );
    state = state.copyWith(jobs: [...state.jobs, job], minimized: false);
    _pump();
  }

  void setMinimized(bool v) => state = state.copyWith(minimized: v);

  /// Remove every finished job; if nothing is left the overlay disappears.
  void dismissFinished() {
    state = state.copyWith(
      jobs: state.jobs.where((j) => !j.isFinished).toList(),
    );
  }

  void _update(int id, ScanJob Function(ScanJob) f) {
    state = state.copyWith(
      jobs: [for (final j in state.jobs) if (j.id == id) f(j) else j],
    );
  }

  ScanJob? _firstPending() {
    for (final j in state.jobs) {
      if (j.status == ScanJobStatus.pending) return j;
    }
    return null;
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      for (var job = _firstPending(); job != null; job = _firstPending()) {
        await _process(job);
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _process(ScanJob job) async {
    _update(job.id, (j) => j.copyWith(status: ScanJobStatus.processing));
    try {
      switch (job.kind) {
        case ScanJobKind.einvoice:
          await _processEinvoice(job);
        case ScanJobKind.receipt:
          await _processReceipt(job);
      }
    } catch (e) {
      // The daily-cap case gets a friendly localized message; anything else
      // falls back to the raw error (shown in the failed row's tooltip).
      final error = e is ExtractionLimitReached
          ? ref.read(stringsProvider).scanLimitReached
          : '$e';
      _update(job.id,
          (j) => j.copyWith(status: ScanJobStatus.failed, error: error));
    }
  }

  /// E-invoice QR pipeline: decode (or use the live-camera parse) → dedup →
  /// resolve merchant + category → save. Failures bubble to [_process].
  Future<void> _processEinvoice(ScanJob job) async {
    final parsed = job.parsed ?? await decodeInvoiceFromBytes(job.bytes!);
    if (parsed == null) {
      _update(job.id, (j) => j.copyWith(status: ScanJobStatus.failed));
      return;
    }
    final svc = ref.read(einvoiceQrServiceProvider);
    if (await svc.alreadyExists(parsed.invoiceNumber)) {
      _update(
        job.id,
        (j) => j.copyWith(
          status: ScanJobStatus.duplicate,
          invoiceNumber: parsed.invoiceNumber,
          totalDollars: parsed.totalDollars,
        ),
      );
      return;
    }
    // Best-effort store name (may be null) then the same category resolution
    // the review sheet used.
    final merchant = await ref
        .read(merchantLookupServiceProvider)
        .nameForTaxId(parsed.sellerTaxId);
    final expense = (await ref.read(categoriesProvider.future))
        .where((c) => !c.isIncome)
        .toList();
    final categoryId = await svc.defaultCategoryId(
      parsed,
      merchantName: merchant,
      categories: expense,
    );
    final id = await svc.save(
      parsed,
      merchantName: merchant,
      categoryId: categoryId,
    );
    _update(
      job.id,
      (j) => j.copyWith(
        status: ScanJobStatus.done,
        invoiceNumber: parsed.invoiceNumber,
        merchantName: merchant,
        totalDollars: parsed.totalDollars,
        savedInvoiceId: id,
      ),
    );
    // Refresh History live as each receipt lands.
    ref.invalidate(invoiceListProvider);
  }

  /// Receipt OCR pipeline: photo → Gemini extraction → optional dedup (only when
  /// the model read an e-invoice number off a 電子發票) → resolve category → save
  /// as an editable `ocr` invoice. Failures bubble to [_process].
  Future<void> _processReceipt(ScanJob job) async {
    final receipt =
        await ref.read(receiptExtractionServiceProvider).extract(job.bytes!);
    final svc = ref.read(receiptOcrServiceProvider);

    final number = receipt.invoiceNumber;
    if (number != null && await svc.alreadyExists(number)) {
      _update(
        job.id,
        (j) => j.copyWith(
          status: ScanJobStatus.duplicate,
          invoiceNumber: number,
          merchantName: receipt.merchantName,
          totalDollars: receipt.totalDollars,
        ),
      );
      return;
    }

    // Categorise against the matching pool (income vs expense), mirroring the
    // QR path's expense-only resolution but honouring the AI's kind guess.
    final categories = await ref.read(categoriesProvider.future);
    final pool = receipt.kind == 'income'
        ? categories.where((c) => c.isIncome).toList()
        : categories.where((c) => !c.isIncome).toList();
    final categoryId = await svc.defaultCategoryId(
      receipt,
      merchantName: receipt.merchantName,
      categories: pool,
    );
    final id = await svc.save(
      receipt,
      merchantName: receipt.merchantName,
      categoryId: categoryId,
    );
    _update(
      job.id,
      (j) => j.copyWith(
        status: ScanJobStatus.done,
        invoiceNumber: number,
        merchantName: receipt.merchantName,
        totalDollars: receipt.totalDollars,
        savedInvoiceId: id,
      ),
    );
    // Refresh History live as each receipt lands.
    ref.invalidate(invoiceListProvider);
  }
}

final scanQueueProvider =
    NotifierProvider<ScanQueue, ScanQueueState>(ScanQueue.new);
