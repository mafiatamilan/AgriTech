import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/shared.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _phoneController = TextEditingController();
  bool _saving = false;
  bool _phoneSet = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(backendProvider)
          .updateAccount(phone: _phoneController.text.trim());
      ref.invalidate(accountProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.accountSaved)));
      }
    } on Exception catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final account = ref.watch(accountProvider);
    final user = supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navAccount)),
      body: account.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          onRetry: () => ref.invalidate(accountProvider),
        ),
        data: (info) {
          final avatarUrl = user?.userMetadata?['avatar_url']?.toString();
          if (!_phoneSet) {
            _phoneController.text = info.profile.phone ?? '';
            _phoneSet = true;
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundImage:
                          avatarUrl == null ? null : NetworkImage(avatarUrl),
                      child: avatarUrl == null
                          ? const Icon(Icons.person, size: 32)
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user?.userMetadata?['full_name']?.toString() ??
                              info.profile.name,
                              style: Theme.of(context).textTheme.titleLarge),
                          Text(user?.email ?? info.profile.email ?? ''),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: l10n.accountPhone),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l10n.accountSave),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(l10n.accountImpact,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              if (info.impactMetrics.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text(l10n.accountNoImpact)),
                )
              else
                for (final m in info.impactMetrics) _MetricTile(metric: m),
            ],
          );
        },
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});

  final ImpactMetric metric;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        metric.metricType.contains('water') ? Icons.water_drop : Icons.eco,
        color: const Color(0xFF2E7D32),
      ),
      title: Text(metric.metricType.replaceAll('_', ' ')),
      subtitle: Text(fmtDate(metric.createdAt)),
      trailing: Text(_value(metric.metricValue)),
    );
  }

  String _value(dynamic v) {
    if (v == null) return '—';
    if (v is num) return '${v.toStringAsFixed(1)} L';
    return v.toString();
  }
}
