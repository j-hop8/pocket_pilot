import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/providers.dart';
import '../../models/carrier_config.dart';
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
  bool _prefilled = false;
  SyncResult? _result;

  @override
  void initState() {
    super.initState();
    ref.read(carrierConfigProvider.future).then((config) {
      if (!mounted || _prefilled || config == null) return;
      setState(() {
        _prefilled = true;
        _phone.text = config.phone ?? '';
        _password.text = config.password ?? '';
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
            CarrierConfig(phone: _phone.text, password: _password.text),
          );
      ref.invalidate(carrierConfigProvider);
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Credentials saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Save failed: $e');
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

  const _CredentialsCard({
    required this.phone,
    required this.password,
    required this.obscure,
    required this.onToggleObscure,
    required this.saving,
    required this.onSave,
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
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
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
