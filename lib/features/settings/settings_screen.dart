import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s    = ref.watch(stringsProvider);
    final lang = ref.watch(languageProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
      children: [
        _SectionCard(
          label: s.languageLabel,
          child: _LangPicker(
            selected: lang,
            onSelect: (l) => ref.read(languageProvider.notifier).set(l),
            s: s,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String label;
  final Widget child;

  const _SectionCard({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: PocketColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceMono(
              fontSize: 10,
              letterSpacing: 0.14,
              color: PocketColors.inkSoft,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _LangPicker extends StatelessWidget {
  final AppLang selected;
  final ValueChanged<AppLang> onSelect;
  final AppStrings s;

  const _LangPicker({
    required this.selected,
    required this.onSelect,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LangChip(
          label: s.langZh,
          active: selected == AppLang.zh,
          onTap: () => onSelect(AppLang.zh),
        ),
        const SizedBox(width: 10),
        _LangChip(
          label: s.langEn,
          active: selected == AppLang.en,
          onTap: () => onSelect(AppLang.en),
        ),
      ],
    );
  }
}

class _LangChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _LangChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
          color: active ? PocketColors.ink : PocketColors.paper2,
          borderRadius: BorderRadius.circular(999),
          border: active
              ? null
              : Border.all(color: PocketColors.line, width: 1),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: active ? PocketColors.paper : PocketColors.inkSoft,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}
