import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../models/sync_result.dart';

/// Carrier sync screen: enter/store the e-invoice carrier credentials, and
/// import the MOF "消費明細" CSV (Phase 1 ingestion path).
class CarrierSyncScreen extends ConsumerStatefulWidget {
  const CarrierSyncScreen({super.key});

  @override
  ConsumerState<CarrierSyncScreen> createState() => _CarrierSyncScreenState();
}

class _CarrierSyncScreenState extends ConsumerState<CarrierSyncScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();

  bool _obscure = true;
  bool _saving = false;
  bool _importing = false;
  bool _syncingNow = false;
  bool _prefilled = false;
  bool _editing = false;
  SyncResult? _result;

  @override
  void initState() {
    super.initState();
    ref.read(carrierConfigProvider.future).then((config) {
      if (!mounted || _prefilled || config == null) return;
      setState(() {
        _prefilled = true;
        _phone.text = config.phone ?? '';
        // Password is write-only (stored in Vault), so it is never read back —
        // the field stays blank and "leave blank to keep current" applies.
      });
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _saveCredentials() async {
    setState(() => _saving = true);
    try {
      await ref.read(carrierRepositoryProvider).saveCredentials(
            phone: _phone.text,
            password: _password.text,
          );
      ref.invalidate(carrierConfigProvider);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editing = false;
        _password.clear();
      });
      _snack('Credentials saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Save failed: $e');
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncingNow = true);
    try {
      final result = await ref.read(carrierRepositoryProvider).syncNow();
      ref.invalidate(invoiceListProvider);
      ref.invalidate(carrierConfigProvider);
      if (!mounted) return;
      // The detailed result card (_result) is driven by the CSV import, which
      // has the full breakdown; the server sync only knows the inserted count.
      setState(() => _syncingNow = false);
      _snack(result.isEmpty
          ? 'No new invoices.'
          : 'Synced ${result.inserted} new invoice(s).');
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncingNow = false);
      _snack('Sync failed: $e');
    }
  }

  Future<void> _importCsv() async {
    setState(() => _importing = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        setState(() => _importing = false);
        return;
      }
      final bytes = picked.files.single.bytes;
      if (bytes == null) {
        setState(() => _importing = false);
        _snack('Could not read file contents.');
        return;
      }
      final content = utf8.decode(bytes, allowMalformed: true);
      final categories = await ref.read(categoriesProvider.future);
      final result = await ref
          .read(carrierSyncServiceProvider)
          .importCsv(content, categories);

      ref.invalidate(invoiceListProvider);
      ref.invalidate(carrierConfigProvider);
      if (!mounted) return;
      setState(() {
        _importing = false;
        _result = result;
      });
      _snack(result.isEmpty
          ? 'No invoices found in that file.'
          : 'Imported ${result.inserted} new, skipped ${result.skipped}.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      _snack('Import failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(carrierConfigProvider).asData?.value;
    final hasSavedCredentials = config != null && (config.phone?.isNotEmpty ?? false);
    final showForm = _editing || !hasSavedCredentials;

    return Scaffold(
      appBar: AppBar(title: const Text('Carrier sync')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CredentialsCard(
            phone: _phone,
            password: _password,
            obscure: _obscure,
            onToggleObscure: () => setState(() => _obscure = !_obscure),
            saving: _saving,
            onSave: _saving ? null : _saveCredentials,
            showForm: showForm,
            savedPhone: config?.phone,
            lastSyncedAt: config?.lastSyncedAt,
            lastSyncCount: config?.lastSyncCount,
            onEdit: () => setState(() => _editing = true),
            onCancelEdit: hasSavedCredentials
                ? () => setState(() {
                      _editing = false;
                      _phone.text = config.phone ?? '';
                      _password.clear();
                    })
                : null,
          ),
          const SizedBox(height: 16),
          _SyncNowCard(
            syncing: _syncingNow,
            onSync: _syncingNow ? null : _syncNow,
            connected: hasSavedCredentials,
          ),
          const SizedBox(height: 16),
          _ImportCard(
            importing: _importing,
            onImport: _importing ? null : _importCsv,
            lastSyncedAt: config?.lastSyncedAt,
            lastSyncCount: config?.lastSyncCount,
            result: _result,
          ),
        ],
      ),
    );
  }
}

class _CredentialsCard extends StatelessWidget {
  final TextEditingController phone;
  final TextEditingController password;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool saving;
  final VoidCallback? onSave;

  /// When false, the card shows the compact "connected" summary instead of the
  /// editable form.
  final bool showForm;
  final String? savedPhone;
  final DateTime? lastSyncedAt;
  final int? lastSyncCount;
  final VoidCallback onEdit;

  /// Null when there are no saved credentials to fall back to (so the form
  /// can't be cancelled into an empty state).
  final VoidCallback? onCancelEdit;

  const _CredentialsCard({
    required this.phone,
    required this.password,
    required this.obscure,
    required this.onToggleObscure,
    required this.saving,
    required this.onSave,
    required this.showForm,
    required this.savedPhone,
    required this.lastSyncedAt,
    required this.lastSyncCount,
    required this.onEdit,
    required this.onCancelEdit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Carrier credentials',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '財政部電子發票 portal login. Saved for future auto-sync; '
              'Phase 1 imports via CSV below.',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
            const SizedBox(height: 16),
            if (showForm) ..._formChildren(context) else ..._summaryChildren(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _summaryChildren(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: scheme.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Credentials saved',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _maskPhone(savedPhone),
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Icon(Icons.sync_outlined, size: 16, color: scheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              lastSyncedAt != null
                  ? 'Last sync ${formatDate(lastSyncedAt!)} · '
                      '${lastSyncCount ?? 0} invoices'
                  : 'Not synced yet — import a CSV below to get started.',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Update credentials'),
        ),
      ),
    ];
  }

  List<Widget> _formChildren(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [
      TextField(
        controller: phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          labelText: 'Phone 手機號碼',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.phone_outlined),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: password,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: 'Password 密碼',
          helperText: savedPhone != null ? 'Leave blank to keep current' : null,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
            onPressed: onToggleObscure,
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: scheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Stored in Supabase for this demo. Don\'t use a real '
              'password in a shared environment.',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (onCancelEdit != null)
            TextButton(
              onPressed: saving ? null : onCancelEdit,
              child: const Text('Cancel'),
            ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onSave,
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Save credentials'),
          ),
        ],
      ),
    ];
  }
}

/// "0912345678" -> "0912•••678", keeping the carrier prefix and last 3 digits.
String _maskPhone(String? phone) {
  final p = phone?.trim() ?? '';
  if (p.length < 8) return p;
  return '${p.substring(0, 4)}•••${p.substring(p.length - 3)}';
}

/// Primary on-demand sync: invokes the server-side carrier-sync (login →
/// download CSV → ingest). The CSV import below remains the manual fallback.
class _SyncNowCard extends StatelessWidget {
  final bool syncing;
  final VoidCallback? onSync;

  /// Whether credentials have been saved; the sync can't run without them.
  final bool connected;

  const _SyncNowCard({
    required this.syncing,
    required this.onSync,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sync now',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              connected
                  ? 'Log in and pull your latest invoices automatically.'
                  : 'Save your carrier credentials above first, then run a sync.',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: connected ? onSync : null,
                icon: syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.sync),
                label: Text(syncing ? 'Syncing…' : 'Sync now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportCard extends StatelessWidget {
  final bool importing;
  final VoidCallback? onImport;
  final DateTime? lastSyncedAt;
  final int? lastSyncCount;
  final SyncResult? result;

  const _ImportCard({
    required this.importing,
    required this.onImport,
    required this.lastSyncedAt,
    required this.lastSyncCount,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Import invoices',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Download your invoice CSV from the e-invoice portal '
              '(消費明細), then import it here. Duplicates are skipped '
              'automatically.',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, size: 16, color: scheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                        children: const [
                          TextSpan(
                            text: 'When to use this  使用時機\n',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text:
                                'Automatic carrier sync isn\'t live yet, so CSV '
                                'import is the way to pull in invoices for now. '
                                'It\'s also the fallback if a sync fails or your '
                                'latest invoices haven\'t shown up — re-import '
                                'the CSV and any new ones will be added '
                                '(duplicates skipped).',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: onImport,
                icon: importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file_outlined),
                label: Text(importing ? 'Importing…' : 'Choose CSV file'),
              ),
            ),
            if (lastSyncedAt != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.history, size: 16, color: scheme.outline),
                  const SizedBox(width: 6),
                  Text(
                    'Last sync: ${formatDate(lastSyncedAt!)} '
                    '(${lastSyncCount ?? 0} invoices)',
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                ],
              ),
            ],
            if (result != null) ...[
              const Divider(height: 28),
              _ResultSummary(result: result!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultSummary extends StatelessWidget {
  final SyncResult result;
  const _ResultSummary({required this.result});

  @override
  Widget build(BuildContext context) {
    final range = (result.from != null && result.to != null)
        ? '${formatDate(result.from!)} – ${formatDate(result.to!)}'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Last import',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _statRow(context, Icons.add_circle_outline,
            '${result.inserted} new invoices'),
        _statRow(
            context, Icons.list_alt_outlined, '${result.items} line items'),
        _statRow(context, Icons.skip_next_outlined,
            '${result.skipped} already present (skipped)'),
        if (range != null)
          _statRow(context, Icons.date_range_outlined, range),
      ],
    );
  }

  Widget _statRow(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }
}
