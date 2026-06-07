import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/auth_providers.dart';
import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../core/settings_provider.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../models/carrier_config.dart';

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
          label: s.accountLabel,
          child: _AccountTile(s: s),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          label: s.languageLabel,
          child: _LangPicker(
            selected: lang,
            onSelect: (l) => ref.read(languageProvider.notifier).set(l),
            s: s,
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          label: s.carrierSyncLabel,
          child: _CarrierSyncControls(s: s),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Signed-in Google account (avatar · name · email) + sign-out. Signing out
/// clears the Supabase session; the router redirect returns the user to /login.
class _AccountTile extends ConsumerWidget {
  final AppStrings s;
  const _AccountTile({required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final meta = user?.userMetadata ?? const {};
    final name = (meta['full_name'] ?? meta['name'] ?? user?.email ?? '') as String;
    final email = user?.email ?? '';
    final avatarUrl = (meta['avatar_url'] ?? meta['picture']) as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: PocketColors.paper2,
              foregroundImage:
                  (avatarUrl != null && avatarUrl.isNotEmpty)
                      ? NetworkImage(avatarUrl)
                      : null,
              child: const Icon(Icons.person_outline, color: PocketColors.inkSoft),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (name.isNotEmpty)
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: PocketColors.ink,
                        letterSpacing: -0.2,
                      ),
                    ),
                  if (email.isNotEmpty)
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceMono(
                        fontSize: 12,
                        color: PocketColors.inkSoft,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => ref.read(authServiceProvider).signOut(),
            icon: const Icon(Icons.logout, size: 18),
            label: Text(s.signOut),
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
        _PillChip(
          label: s.langZh,
          active: selected == AppLang.zh,
          onTap: () => onSelect(AppLang.zh),
        ),
        const SizedBox(width: 10),
        _PillChip(
          label: s.langEn,
          active: selected == AppLang.en,
          onTap: () => onSelect(AppLang.en),
        ),
      ],
    );
  }
}

/// Pill-shaped selectable chip — the building block for the language picker and
/// the sync-interval picker.
class _PillChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PillChip({
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

// ─────────────────────────────────────────────────────────────────────────────

/// Auto-sync toggle + interval picker + "Sync now" for the carrier sync. Reads
/// the persisted settings from [carrierConfigProvider]; writes go through
/// [CarrierRepository] and invalidate the provider so the UI reflects them.
class _CarrierSyncControls extends ConsumerStatefulWidget {
  final AppStrings s;
  const _CarrierSyncControls({required this.s});

  @override
  ConsumerState<_CarrierSyncControls> createState() =>
      _CarrierSyncControlsState();
}

class _CarrierSyncControlsState extends ConsumerState<_CarrierSyncControls> {
  static const _intervals = [60, 360, 720, 1440];
  bool _syncing = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save({
    bool? enabled,
    int? intervalMinutes,
    required CarrierConfig? config,
  }) async {
    try {
      await ref.read(carrierRepositoryProvider).saveSyncSettings(
            enabled: enabled ?? config?.autoSyncEnabled ?? true,
            intervalMinutes:
                intervalMinutes ?? config?.syncIntervalMinutes ?? 60,
          );
      ref.invalidate(carrierConfigProvider);
    } catch (e) {
      _snack(widget.s.syncFailedError(e));
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final result = await ref.read(carrierRepositoryProvider).syncNow();
      ref.invalidate(invoiceListProvider);
      ref.invalidate(carrierConfigProvider);
      if (!mounted) return;
      setState(() => _syncing = false);
      _snack(widget.s.syncOkSnack(result.inserted));
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncing = false);
      _snack(widget.s.syncFailedError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final config = ref.watch(carrierConfigProvider).asData?.value;
    final enabled = config?.autoSyncEnabled ?? true;
    final interval = config?.syncIntervalMinutes ?? 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.autoSyncLabel,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: PocketColors.ink,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.autoSyncHint,
                    style: GoogleFonts.spaceMono(
                      fontSize: 11,
                      color: PocketColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: (v) => _save(enabled: v, config: config),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          s.syncIntervalLabel.toUpperCase(),
          style: GoogleFonts.spaceMono(
            fontSize: 10,
            letterSpacing: 0.14,
            color: PocketColors.inkSoft,
          ),
        ),
        const SizedBox(height: 12),
        Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final m in _intervals)
                _PillChip(
                  label: s.syncIntervalOption(m),
                  active: interval == m,
                  onTap: () => _save(intervalMinutes: m, config: config),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _syncing ? null : _syncNow,
            icon: _syncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync, size: 18),
            label: Text(_syncing ? s.syncing : s.syncNow),
          ),
        ),
        const SizedBox(height: 12),
        _SyncStatusLine(config: config, s: s),
      ],
    );
  }
}

/// One-line "last synced …" / error summary under the Sync now button.
class _SyncStatusLine extends StatelessWidget {
  final CarrierConfig? config;
  final AppStrings s;
  const _SyncStatusLine({required this.config, required this.s});

  @override
  Widget build(BuildContext context) {
    final c = config;
    final isError = c?.hasError ?? false;
    final color = isError ? Theme.of(context).colorScheme.error : PocketColors.inkSoft;
    final text = isError
        ? '${s.syncStatusErrorPrefix}: ${c?.lastSyncError ?? ''}'
        : (c?.lastSyncedAt == null
            ? s.syncNever
            : s.lastSyncedText(formatDate(c!.lastSyncedAt!), c.lastSyncCount));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(isError ? Icons.error_outline : Icons.history, size: 15, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.spaceMono(fontSize: 11, color: color),
          ),
        ),
      ],
    );
  }
}
