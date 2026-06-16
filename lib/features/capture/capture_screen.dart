import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../widgets/mascots.dart';
import '../scan/einvoice_scan_panel.dart';
import '../scan/receipt_scan_panel.dart';

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  int _sourceIndex = 1; // 0 = manual, 1 = e-invoice QR, 2 = receipt

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    // The scanner's camera should only run while the Add tab is the one showing.
    final onAddTab = ref.watch(bottomTabIndexProvider) == 1;

    return Column(
      children: [
        _SourceTabs(
          selected: _sourceIndex,
          labels: [s.tabManual, s.tabEInvoice, s.tabReceipt],
          onSelect: (i) => setState(() => _sourceIndex = i),
        ),
        Expanded(child: _body(s, onAddTab)),
      ],
    );
  }

  Widget _body(AppStrings s, bool onAddTab) => switch (_sourceIndex) {
        0 => _ManualPanel(
            title: s.manualPanelTitle,
            hint: s.manualPanelHint,
            addLabel: s.addInvoice,
            onAdd: () => context.push('/add'),
          ),
        // Active only when the e-invoice sub-tab is selected AND the Add tab shows.
        1 => EInvoiceScanPanel(active: onAddTab && _sourceIndex == 1),
        // Receipt OCR: photo → Gemini extraction → auto-saved as an editable row.
        _ => ReceiptScanPanel(active: onAddTab && _sourceIndex == 2),
      };
}

// ─────────────────────────────────────────────────────────────────────────────

class _ManualPanel extends StatelessWidget {
  final String title;
  final String hint;
  final String addLabel;
  final VoidCallback onAdd;

  const _ManualPanel({
    required this.title,
    required this.hint,
    required this.addLabel,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
          decoration: BoxDecoration(
            color: PocketColors.card,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NoteMascot(size: 88),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: PocketColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceMono(
                  fontSize: 12,
                  color: PocketColors.inkSoft,
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: onAdd,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: PocketColors.persimmon,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: PocketColors.persimmon.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Text(
                    '✏️  $addLabel',
                    style: GoogleFonts.spaceMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: PocketColors.paper,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SourceTabs extends StatelessWidget {
  final int selected;
  final List<String> labels;
  final ValueChanged<int> onSelect;

  const _SourceTabs({
    required this.selected,
    required this.labels,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(labels.length, (i) {
          final active = i == selected;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  color: active ? PocketColors.ink : PocketColors.paper2,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  labels[i],
                  style: GoogleFonts.spaceMono(
                    fontSize: 12,
                    color: active ? PocketColors.paper : PocketColors.inkSoft,
                    fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// The receipt tab body now lives in `ReceiptScanPanel`; the e-invoice tab brings
// its own live-camera viewfinder, so this screen no longer needs a static one.
