import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/mascots.dart';
import 'scan_queue.dart';

/// A Google-Drive-style progress card for the background scan queue, pinned to
/// the bottom-right corner. Renders nothing while the queue is empty; otherwise
/// shows either the full card (per-receipt rows + overall progress) or, when
/// minimized, a small count chip. Mounted in [ShellScaffold] so it survives tab
/// switches.
class ScanProgressOverlay extends ConsumerWidget {
  const ScanProgressOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanQueueProvider);
    if (state.isEmpty) return const SizedBox.shrink();

    return Positioned(
      right: 12,
      bottom: 12,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: state.minimized
            ? const _MinimizedChip()
            : const _ExpandedCard(),
      ),
    );
  }
}

class _ExpandedCard extends ConsumerWidget {
  const _ExpandedCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanQueueProvider);
    final s = ref.watch(stringsProvider);
    final notifier = ref.read(scanQueueProvider.notifier);
    final progress = state.total == 0 ? 0.0 : state.finished / state.total;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: PocketColors.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 4, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: state.active
                        ? const FittedBox(
                            fit: BoxFit.contain,
                            child: ScanningMascot(size: 96),
                          )
                        : const Icon(Icons.check_circle,
                            color: PocketColors.pine, size: 26),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.allDone ? s.queueAllDone : s.queueTitle(state.total),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: PocketColors.ink,
                          ),
                        ),
                        Text(
                          '${state.finished} / ${state.total}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: PocketColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: s.queueMinimize,
                    icon: const Icon(Icons.remove, size: 20),
                    onPressed: () => notifier.setMinimized(true),
                  ),
                  if (state.allDone)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: s.queueDismiss,
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: notifier.dismissFinished,
                    ),
                ],
              ),
            ),
            ClipRRect(
              child: LinearProgressIndicator(
                value: state.active ? (progress == 0 ? null : progress) : 1,
                minHeight: 3,
                backgroundColor: PocketColors.paper2,
              ),
            ),
            // ── Job list ────────────────────────────────────────────────
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 252),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (final job in state.jobs) _JobRow(job: job, s: s),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  final ScanJob job;
  final AppStrings s;

  const _JobRow({required this.job, required this.s});

  @override
  Widget build(BuildContext context) {
    final label = (job.merchantName != null && job.merchantName!.isNotEmpty)
        ? job.merchantName!
        : (job.invoiceNumber ?? s.scanReading);

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _Leading(job: job),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: PocketColors.ink,
                  ),
                ),
                if (job.totalDollars != null)
                  Text(
                    formatTwd(dollarsToCents(job.totalDollars!)),
                    style: const TextStyle(
                      fontSize: 11,
                      color: PocketColors.inkSoft,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Trailing(job: job, s: s),
        ],
      ),
    );

    if (job.status == ScanJobStatus.done && job.savedInvoiceId != null) {
      return InkWell(
        onTap: () => context.push('/invoice/${job.savedInvoiceId}'),
        child: row,
      );
    }
    return row;
  }
}

class _Leading extends StatelessWidget {
  final ScanJob job;
  const _Leading({required this.job});

  @override
  Widget build(BuildContext context) {
    const size = 36.0;
    if (job.bytes != null) {
      // `cacheWidth`/`cacheHeight` make Flutter decode the full-res receipt JPEG
      // down to the 36 px box once, instead of re-decoding the whole image into
      // memory on every overlay rebuild (the overlay rebuilds on each job state
      // change). Scale by DPR so it stays crisp on hi-dpi screens.
      final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          job.bytes!,
          width: size,
          height: size,
          cacheWidth: px,
          cacheHeight: px,
          fit: BoxFit.cover,
        ),
      );
    }
    // Live-camera jobs have no image — show a QR glyph instead.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: PocketColors.paper2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.qr_code_2, size: 20, color: PocketColors.inkSoft),
    );
  }
}

class _Trailing extends StatelessWidget {
  final ScanJob job;
  final AppStrings s;
  const _Trailing({required this.job, required this.s});

  @override
  Widget build(BuildContext context) {
    switch (job.status) {
      case ScanJobStatus.pending:
        return const Icon(Icons.schedule, size: 18, color: PocketColors.inkSoft);
      case ScanJobStatus.processing:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case ScanJobStatus.done:
        return const Icon(Icons.check_circle, size: 20, color: PocketColors.pine);
      case ScanJobStatus.duplicate:
        return Text(
          s.queueDuplicate,
          style: const TextStyle(fontSize: 11, color: PocketColors.inkSoft),
        );
      case ScanJobStatus.failed:
        return Tooltip(
          message: job.error ?? s.queueFailed,
          child: Icon(Icons.error_outline,
              size: 20, color: Theme.of(context).colorScheme.error),
        );
    }
  }
}

class _MinimizedChip extends ConsumerWidget {
  const _MinimizedChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scanQueueProvider);
    final s = ref.watch(stringsProvider);
    final progress = state.total == 0 ? 0.0 : state.finished / state.total;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => ref.read(scanQueueProvider.notifier).setMinimized(false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: PocketColors.ink,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: state.allDone
                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                    : CircularProgressIndicator(
                        value: progress == 0 ? null : progress,
                        strokeWidth: 2.5,
                        color: PocketColors.persimmon,
                        backgroundColor: Colors.white24,
                      ),
              ),
              const SizedBox(width: 10),
              Text(
                state.allDone ? s.queueAllDone : '${state.finished}/${state.total}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
