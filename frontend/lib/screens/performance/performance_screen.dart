import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/backend.dart';
import '../../widgets/shared.dart';

class PerformanceScreen extends ConsumerStatefulWidget {
  const PerformanceScreen({super.key});

  @override
  ConsumerState<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends ConsumerState<PerformanceScreen> {
  final _cropController = TextEditingController();
  final _seasonController = TextEditingController();
  final _yieldController = TextEditingController();
  final _revenueController = TextEditingController();
  final _costController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _plantedDate;
  DateTime? _harvestDate;
  bool _submitting = false;

  @override
  void dispose() {
    _cropController.dispose();
    _seasonController.dispose();
    _yieldController.dispose();
    _revenueController.dispose();
    _costController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isPlanted}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        if (isPlanted) {
          _plantedDate = picked;
        } else {
          _harvestDate = picked;
        }
      });
    }
  }

  Future<void> _recordPerformance() async {
    final l10n = AppLocalizations.of(context);
    if (_cropController.text.trim().isEmpty) {
      if (mounted) showError(context, l10n.performanceInvalidInput);
      return;
    }
    final farms = ref.read(farmsProvider);
    final farm = farms.currentFarm;
    if (farm == null) {
      if (mounted) showError(context, l10n.inventoryNoFarm);
      return;
    }

    final yieldKg = double.tryParse(_yieldController.text);
    final revenue = double.tryParse(_revenueController.text);
    final cost = double.tryParse(_costController.text);

    if (yieldKg == null && revenue == null) {
      if (mounted) showError(context, l10n.performanceInvalidInput);
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(backendProvider).recordCropPerformance(
            farmId: farm.id,
            crop: _cropController.text.trim(),
            season: _seasonController.text.trim().isEmpty
                ? null
                : _seasonController.text.trim(),
            plantedDate: _plantedDate?.toIso8601String(),
            harvestDate: _harvestDate?.toIso8601String(),
            yieldKg: yieldKg,
            revenue: revenue,
            cost: cost,
            profit: (revenue ?? 0) - (cost ?? 0),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      _cropController.clear();
      _seasonController.clear();
      _yieldController.clear();
      _revenueController.clear();
      _costController.clear();
      _notesController.clear();
      _plantedDate = null;
      _harvestDate = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.performanceRecorded)),
        );
      }
    } on Exception catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navPerformance)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const FarmSwitcher(),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.performanceRecordTitle,
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _cropController,
                    decoration: InputDecoration(
                      labelText: l10n.performanceCrop,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _seasonController,
                    decoration: InputDecoration(
                      labelText: l10n.performanceSeason,
                      hintText: 'e.g. 2026-Q2',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isPlanted: true),
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                            _plantedDate != null
                                ? DateFormat.yMMMd().format(_plantedDate!)
                                : l10n.performancePlantedDate,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isPlanted: false),
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                            _harvestDate != null
                                ? DateFormat.yMMMd().format(_harvestDate!)
                                : l10n.performanceHarvestDate,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _yieldController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.performanceYield,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _revenueController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: l10n.performanceRevenue,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _costController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: l10n.performanceCost,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: l10n.performanceNotes,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _recordPerformance,
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_chart),
                    label: Text(l10n.performanceRecordButton),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
