import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/shared.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _cropController = TextEditingController();
  final _quantityController = TextEditingController();
  final _storageController = TextEditingController();
  DateTime? _harvestedDate;
  bool _submitting = false;

  @override
  void dispose() {
    _cropController.dispose();
    _quantityController.dispose();
    _storageController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked != null) setState(() => _harvestedDate = picked);
  }

  Future<void> _addInventory() async {
    final l10n = AppLocalizations.of(context);
    if (_cropController.text.trim().isEmpty ||
        _quantityController.text.trim().isEmpty) {
      if (mounted) showError(context, l10n.inventoryInvalidInput);
      return;
    }
    final farms = ref.read(farmsProvider);
    final farm = farms.currentFarm;
    if (farm == null) {
      if (mounted) showError(context, l10n.inventoryNoFarm);
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(backendProvider).addInventory(
            farmId: farm.id,
            cropName: _cropController.text.trim(),
            quantity: double.parse(_quantityController.text.trim()),
            harvestedDate: _harvestedDate?.toIso8601String(),
            storageType: _storageController.text.trim().isEmpty
                ? null
                : _storageController.text.trim(),
          );
      ref.invalidate(inventoryProvider);
      _cropController.clear();
      _quantityController.clear();
      _storageController.clear();
      _harvestedDate = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.inventoryAdded)),
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
    final inventory = ref.watch(inventoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navInventory)),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(inventoryProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const FarmSwitcher(),
            const SizedBox(height: 16),
            _AddInventoryForm(
              cropController: _cropController,
              quantityController: _quantityController,
              storageController: _storageController,
              harvestedDate: _harvestedDate,
              submitting: _submitting,
              onPickDate: _pickDate,
              onSubmit: _addInventory,
            ),
            const SizedBox(height: 24),
            Text(l10n.inventoryList,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            inventory.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(e.toString())),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l10n.inventoryEmpty)),
                  );
                }
                return Column(
                  children: items.map((item) => _InventoryCard(item: item)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AddInventoryForm extends StatelessWidget {
  const _AddInventoryForm({
    required this.cropController,
    required this.quantityController,
    required this.storageController,
    required this.harvestedDate,
    required this.submitting,
    required this.onPickDate,
    required this.onSubmit,
  });

  final TextEditingController cropController;
  final TextEditingController quantityController;
  final TextEditingController storageController;
  final DateTime? harvestedDate;
  final bool submitting;
  final VoidCallback onPickDate;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dateLabel = harvestedDate != null
        ? DateFormat.yMMMd().format(harvestedDate!)
        : l10n.inventoryHarvestDate;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.inventoryAddTitle,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            TextField(
              controller: cropController,
              decoration: InputDecoration(
                labelText: l10n.inventoryCropName,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: quantityController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.inventoryQuantity,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onPickDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(dateLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: storageController,
              decoration: InputDecoration(
                labelText: l10n.inventoryStorageType,
                hintText: 'e.g. cold_storage, open_air',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: submitting ? null : onSubmit,
              icon: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text(l10n.inventoryAddButton),
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusInfo = item.statusInfo;
    final statusColor = statusInfo?.status == 'fresh'
        ? Colors.green
        : statusInfo?.status == 'expiring_soon'
            ? Colors.orange
            : statusInfo?.status == 'expired'
                ? Colors.red
                : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.cropName,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusInfo?.status ?? 'unknown',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _InfoChip(
                  icon: Icons.scale,
                  label: '${item.quantity} kg',
                ),
                if (item.harvestedDate != null) ...[
                  const SizedBox(width: 12),
                  _InfoChip(
                    icon: Icons.calendar_today,
                    label: item.harvestedDate!,
                  ),
                ],
                if (item.storageType != null) ...[
                  const SizedBox(width: 12),
                  _InfoChip(
                    icon: Icons.warehouse,
                    label: item.storageType!,
                  ),
                ],
              ],
            ),
            if (statusInfo?.remainingDays != null) ...[
              const SizedBox(height: 8),
              Text(
                '${statusInfo!.remainingDays} days remaining',
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
