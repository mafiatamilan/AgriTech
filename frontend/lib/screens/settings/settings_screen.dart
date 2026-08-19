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

// Soil values the irrigation agent supports (agents/agri_agents/models.py).
const _fieldSoilTypes = ['sandy', 'loamy', 'silty', 'clay', 'peaty'];

const _cropTypes = ['tomato', 'okra', 'spinach', 'onion', 'potato', 'maize'];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _localityController = TextEditingController();
  final _areaController = TextEditingController();
  final _pumpController = TextEditingController();
  AppSettings? _settings;
  FieldArea? _field;
  DateTime? _plantedDate;
  String _cropType = 'tomato';
  String _fieldSoilType = 'loamy';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _localityController.dispose();
    _areaController.dispose();
    _pumpController.dispose();
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
    await _loadField();
  }

  Future<void> _loadField() async {
    final farm = ref.read(farmsProvider).currentFarm;
    if (farm == null) return;
    try {
      final fields = await ref.read(backendProvider).getFields(farm.id);
      if (!mounted) return;
      final field = fields.isNotEmpty ? fields.first : null;
      setState(() {
        _field = field;
        _areaController.text = field?.areaSize?.toString() ?? '';
        _pumpController.text = field?.pumpFlowLpm?.toString() ?? '';
        _cropType = field?.cropType ?? 'tomato';
        _fieldSoilType = _fieldSoilTypes.contains(field?.soilType)
            ? field!.soilType!
            : 'loamy';
        _plantedDate = DateTime.tryParse(field?.plantedDate ?? '');
      });
    } on Exception {
      // keep defaults; user can fill in
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
      await _saveField(l10n);
    } on Exception catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveField(AppLocalizations l10n) async {
    final farm = ref.read(farmsProvider).currentFarm;
    if (farm == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.settingsNoFarm)));
      }
      return;
    }

    final area = double.tryParse(_areaController.text.trim());
    final pump = double.tryParse(_pumpController.text.trim());
    final planted =
        _plantedDate?.toIso8601String().substring(0, 10);

    if (area != null && area <= 0) {
      if (mounted) {
        showError(context, Exception(l10n.settingsFieldInvalidArea));
      }
      return;
    }
    if (pump != null && pump <= 0) {
      if (mounted) {
        showError(context, Exception(l10n.settingsFieldInvalidPump));
      }
      return;
    }

    final backend = ref.read(backendProvider);
    if (_field == null) {
      _field = await backend.createField(farm.id, FieldArea(
            id: '',
            areaSize: area,
            cropType: _cropType,
            plantedDate: planted,
            soilType: _fieldSoilType,
            pumpFlowLpm: pump,
          ));
    } else {
      _field = await backend.updateField(
        farm.id,
        _field!.id,
        FieldArea(
          id: _field!.id,
          areaSize: area,
          cropType: _cropType,
          plantedDate: planted,
          soilType: _fieldSoilType,
          pumpFlowLpm: pump,
        ),
      );
    }
    ref.invalidate(fieldsProvider(farm.id));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.settingsFieldSaved)));
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
                const Divider(height: 24),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(l10n.settingsIrrigationSetup,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    l10n.settingsIrrigationSetupHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<String>(
                    initialValue: _fieldSoilType,
                    decoration:
                        InputDecoration(labelText: l10n.settingsSoilType),
                    items: [
                      for (final t in _fieldSoilTypes)
                        DropdownMenuItem(value: t, child: Text(_label(l10n, t))),
                    ],
                    onChanged: (v) => setState(() => _fieldSoilType = v ?? 'loamy'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _areaController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.settingsFieldArea,
                      suffixText: 'm²',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<String>(
                    initialValue: _cropType,
                    decoration: InputDecoration(labelText: l10n.settingsCropType),
                    items: [
                      for (final c in _cropTypes)
                        DropdownMenuItem(value: c, child: Text(_cropLabel(l10n, c))),
                      const DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) =>
                        setState(() => _cropType = v ?? 'tomato'),
                  ),
                ),
                ListTile(
                  title: Text(l10n.settingsPlantedDate),
                  subtitle: Text(_plantedDate == null
                      ? l10n.commonCancel
                      : _plantedDate!.toIso8601String().substring(0, 10)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _plantedDate ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _plantedDate = picked);
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _pumpController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.settingsPumpFlow,
                      suffixText: 'L/min',
                    ),
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

  String _cropLabel(AppLocalizations l10n, String c) {
    switch (c) {
      case 'tomato':
        return l10n.cropTomato;
      case 'okra':
        return l10n.cropOkra;
      case 'spinach':
        return l10n.cropSpinach;
      case 'onion':
        return l10n.cropOnion;
      case 'potato':
        return l10n.cropPotato;
      case 'maize':
        return l10n.cropMaize;
      default:
        return c;
    }
  }
}