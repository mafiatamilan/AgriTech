import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/shared.dart';

const _soilTypes = [
  'sandy',
  'loamy',
  'clay',
  'silty',
  'peaty',
  'chalky',
];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _localityController = TextEditingController();
  AppSettings? _settings;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _localityController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(backendProvider).getSettings();
      if (!mounted) return;
      _localityController.text = s.areaLocality ?? '';
      setState(() => _settings = s);
    } on Exception {
      // show nothing; form stays hidden
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final s = _settings;
    if (s == null) return;
    s.areaLocality = _localityController.text.trim();
    setState(() => _saving = true);
    try {
      await ref.read(backendProvider).updateSettings(s);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.settingsSaved)));
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
    final s = _settings;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<String>(
                    initialValue: s.preferredLanguage,
                    decoration:
                        InputDecoration(labelText: l10n.settingsLanguage),
                    items: const [
                      DropdownMenuItem(value: 'en', child: Text('English')),
                    ],
                    onChanged: (v) => setState(() => s.preferredLanguage = v ?? 'en'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<String>(
                    initialValue: s.soilType,
                    decoration: InputDecoration(labelText: l10n.settingsSoilType),
                    items: [
                      for (final t in _soilTypes)
                        DropdownMenuItem(value: t, child: Text(_label(l10n, t))),
                    ],
                    onChanged: (v) => setState(() => s.soilType = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _localityController,
                    decoration:
                        InputDecoration(labelText: l10n.settingsLocality),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(l10n.settingsNotifications,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                SwitchListTile(
                  title: Text(l10n.settingsNotifWatering),
                  value: s.notificationWatering,
                  onChanged: (v) => setState(() => s.notificationWatering = v),
                ),
                SwitchListTile(
                  title: Text(l10n.settingsNotifMatch),
                  value: s.notificationMatch,
                  onChanged: (v) => setState(() => s.notificationMatch = v),
                ),
                SwitchListTile(
                  title: Text(l10n.settingsNotifSystem),
                  value: s.notificationSystem,
                  onChanged: (v) => setState(() => s.notificationSystem = v),
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
                        : Text(l10n.settingsSave),
                  ),
                ),
              ],
            ),
    );
  }

  String _label(AppLocalizations l10n, String t) {
    switch (t) {
      case 'sandy':
        return l10n.soilSandy;
      case 'loamy':
        return l10n.soilLoamy;
      case 'clay':
        return l10n.soilClay;
      case 'silty':
        return l10n.soilSilty;
      case 'peaty':
        return l10n.soilPeaty;
      default:
        return l10n.soilChalky;
    }
  }
}