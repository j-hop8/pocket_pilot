import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pp_core/pp_core.dart';

import '../../core/providers.dart';
import 'scan_decoder.dart';

/// Lifecycle of one queued receipt: waiting → being read → a terminal outcome.
enum ScanJobStatus { pending, processing, done, duplicate, failed }

/// A single receipt to ingest in the background. Carries either raw image
/// [bytes] (photo / gallery / web-capture, decoded by the worker) or an
/// already-[parsed] invoice (live-camera detection, which hands us the QR
/// payloads directly so no decode is needed).
@immutable
class ScanJob {
  final int id;
  final ScanJobStatus status;
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
    } catch (e) {
      _update(job.id, (j) => j.copyWith(status: ScanJobStatus.failed, error: '$e'));
    }
  }
}

final scanQueueProvider =
    NotifierProvider<ScanQueue, ScanQueueState>(ScanQueue.new);
