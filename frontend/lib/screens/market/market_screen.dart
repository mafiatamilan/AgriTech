import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/shared.dart';

class MarketScreen extends ConsumerStatefulWidget {
  const MarketScreen({super.key});

  @override
  ConsumerState<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends ConsumerState<MarketScreen> {
  final _cropController = TextEditingController();
  final _quantityController = TextEditingController();
  final _shelfLifeController = TextEditingController();
  final _priceController = TextEditingController();
  DateTime? _harvestedDate;
  String _inventoryChoice = _manualCropChoice;
  CropMatchResult? _lastResult;
  bool _submitting = false;
  bool _locating = false;

  static const _manualCropChoice = '__manual__';

  @override
  void dispose() {
    _cropController.dispose();
    _quantityController.dispose();
    _shelfLifeController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null) setState(() => _harvestedDate = picked);
  }

  Future<void> _submitMatch() async {
    final l10n = AppLocalizations.of(context);
    final quantity = double.tryParse(_quantityController.text.trim());
    if (_cropController.text.trim().isEmpty ||
        quantity == null ||
        quantity <= 0 ||
        _harvestedDate == null) {
      if (mounted) showError(context, l10n.marketInvalidInput);
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await ref
          .read(backendProvider)
          .cropMatch(
            cropName: _cropController.text.trim(),
            quantityKg: quantity,
            shelfLifeDays: int.tryParse(_shelfLifeController.text),
            harvestedDate: _harvestedDate!.toIso8601String(),
            expectedPrice: double.tryParse(_priceController.text),
          );
      setState(() => _lastResult = result);
      ref.invalidate(marketRequestsProvider);
      _cropController.clear();
      _quantityController.clear();
      _shelfLifeController.clear();
      _priceController.clear();
      setState(() {
        _harvestedDate = null;
        _inventoryChoice = _manualCropChoice;
      });
    } on Exception catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _selectInventoryCrop(String value, List<InventoryItem> inventory) {
    setState(() {
      _inventoryChoice = value;
      if (value == _manualCropChoice) {
        return;
      }
      final matches = inventory.where((item) => item.id == value);
      if (matches.isEmpty) {
        _inventoryChoice = _manualCropChoice;
        return;
      }
      final item = matches.first;
      _cropController.text = item.cropName;
      _quantityController.text = item.quantity.toStringAsFixed(2);
      _harvestedDate = DateTime.tryParse(item.harvestedDate ?? '');
    });
  }

  Future<void> _setAddress(Farm farm) async {
    setState(() => _locating = true);
    try {
      await setFarmLocation(context, ref, farm);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _extendShelfLife(DemandRequest request) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final days = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.marketExtendShelfLife),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l10n.marketAdditionalDays),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text)),
            child: Text(l10n.marketExtend),
          ),
        ],
      ),
    );
    if (days == null || days <= 0) return;
    try {
      await ref.read(backendProvider).extendShelfLife(request.id, days);
      ref.invalidate(marketRequestsProvider);
      ref.invalidate(notificationsProvider);
    } on Exception catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _confirmSale(RescueMatch match) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.marketConfirmSaleTitle),
        content: Text(l10n.marketConfirmSaleBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.marketConfirmSale),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(backendProvider).confirmMatch(match.id);
      ref.invalidate(marketRequestsProvider);
      ref.invalidate(inventoryProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.marketSaleConfirmed)));
      }
    } on Exception catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final requests = ref.watch(marketRequestsProvider);
    final inventory =
        ref.watch(inventoryProvider).value ?? const <InventoryItem>[];
    final availableInventory = inventory
        .where((item) => item.cropName.trim().isNotEmpty && item.quantity > 0)
        .toList();
    final selectedInventoryId =
        _inventoryChoice == _manualCropChoice ||
            availableInventory.any((item) => item.id == _inventoryChoice)
        ? _inventoryChoice
        : _manualCropChoice;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navMarket)),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(marketRequestsProvider),
        child: ListView(
          children: [
            const FarmSwitcher(),
            _AddressPrompt(onSet: _setAddress),
            _AddMatchForm(
              cropController: _cropController,
              quantityController: _quantityController,
              shelfLifeController: _shelfLifeController,
              priceController: _priceController,
              harvestedDate: _harvestedDate,
              inventoryItems: availableInventory,
              selectedInventoryId: selectedInventoryId,
              submitting: _submitting,
              locating: _locating,
              onInventoryChanged: (value) =>
                  _selectInventoryCrop(value, availableInventory),
              onPickDate: _pickDate,
              onSubmit: _submitMatch,
            ),
            if (_lastResult != null) _MatchResultCard(result: _lastResult!),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                l10n.marketRequests,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            requests.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: ErrorView(
                  onRetry: () => ref.invalidate(marketRequestsProvider),
                ),
              ),
              data: (items) => Column(
                children: items.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(child: Text(l10n.marketNoMatches)),
                        ),
                      ]
                    : [
                        for (final r in items)
                          _RequestCard(
                            request: r,
                            onExtend: () => _extendShelfLife(r),
                            onConfirm: r.matches.isEmpty
                                ? null
                                : () => _confirmSale(
                                    r.matches
                                            .where((m) => !m.isConfirmed)
                                            .firstOrNull ??
                                        r.matches.first,
                                  ),
                          ),
                      ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _AddressPrompt extends ConsumerWidget {
  const _AddressPrompt({required this.onSet});

  final void Function(Farm farm) onSet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final farms = ref.watch(farmsProvider).farms;
    final missingLocation = farms.where((f) => f.location == null).toList();
    if (missingLocation.isEmpty) return const SizedBox.shrink();

    return Card(
      color: const Color(0xFFFFF8E1),
      child: ListTile(
        leading: const Icon(Icons.location_on_outlined),
        title: Text(l10n.marketNeedAddress),
        trailing: FilledButton.tonal(
          onPressed: () => onSet(missingLocation.first),
          child: Text(l10n.marketSetAddress),
        ),
      ),
    );
  }
}

class _AddMatchForm extends StatelessWidget {
  const _AddMatchForm({
    required this.cropController,
    required this.quantityController,
    required this.shelfLifeController,
    required this.priceController,
    required this.harvestedDate,
    required this.inventoryItems,
    required this.selectedInventoryId,
    required this.submitting,
    required this.locating,
    required this.onInventoryChanged,
    required this.onPickDate,
    required this.onSubmit,
  });

  final TextEditingController cropController;
  final TextEditingController quantityController;
  final TextEditingController shelfLifeController;
  final TextEditingController priceController;
  final DateTime? harvestedDate;
  final List<InventoryItem> inventoryItems;
  final String selectedInventoryId;
  final bool submitting;
  final bool locating;
  final ValueChanged<String> onInventoryChanged;
  final VoidCallback onPickDate;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selectedValue =
        selectedInventoryId == _MarketScreenState._manualCropChoice ||
            inventoryItems.any((item) => item.id == selectedInventoryId)
        ? selectedInventoryId
        : _MarketScreenState._manualCropChoice;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedValue,
              decoration: const InputDecoration(
                labelText: 'Crop source',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(
                  value: _MarketScreenState._manualCropChoice,
                  child: Text('Manual entry'),
                ),
                for (final item in inventoryItems)
                  DropdownMenuItem(
                    value: item.id,
                    child: Text(
                      '${item.cropName} (${item.quantity.toStringAsFixed(0)} kg)',
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onInventoryChanged(value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cropController,
              decoration: InputDecoration(
                labelText: l10n.marketCropName,
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: quantityController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Quantity available (kg)',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: shelfLifeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.marketShelfLife,
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.marketExpectedPrice,
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: onPickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.marketHarvestedDate,
                  isDense: true,
                ),
                child: Text(
                  harvestedDate == null
                      ? l10n.marketHarvestedDate
                      : fmtDate(harvestedDate),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (submitting || locating) ? null : onSubmit,
                child: submitting || locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.marketFindBuyers),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showBuyerDetails(BuildContext context, MarketMatch match) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(match.buyerName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DetailRow(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: match.buyerPhone,
          ),
          _DetailRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: match.buyerEmail,
          ),
          _DetailRow(
            icon: Icons.location_on_outlined,
            label: 'Address',
            value: match.buyerAddress,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value == null || value!.trim().isEmpty ? '—' : value!),
    );
  }
}

class _MatchResultCard extends StatelessWidget {
  const _MatchResultCard({required this.result});

  final CropMatchResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      color: result.matches.isEmpty ? null : const Color(0xFFE8F5E9),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: result.matches.isEmpty
            ? Text(l10n.marketNoMatches)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.marketFindBuyers,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  for (final m in result.matches)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.storefront),
                      title: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => _showBuyerDetails(context, m),
                          child: Text(m.buyerName),
                        ),
                      ),
                      subtitle: Text(
                        '${money(m.offeredPrice)} · '
                        '${m.distanceKm?.toStringAsFixed(1) ?? '—'} km',
                      ),
                      trailing: Text(
                        m.shelfLifeCompatible == null
                            ? l10n.marketShelfLifeUnknown
                            : m.shelfLifeCompatible!
                            ? l10n.marketShelfLifeCompatible
                            : l10n.marketShelfLifeUnknown,
                        style: TextStyle(
                          color: m.shelfLifeCompatible == true
                              ? Colors.green.shade700
                              : Colors.grey,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.onExtend,
    required this.onConfirm,
  });

  final DemandRequest request;
  final VoidCallback onExtend;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isMatched = request.status == 'matched';
    final daysLeft = request.shelfLifeExpiry?.difference(DateTime.now()).inDays;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(request.cropName),
            subtitle: Text(
              '${request.remainingQuantityKg?.toStringAsFixed(0) ?? '—'} kg remaining · '
              '${money(request.expectedPrice)} · '
              '${isMatched ? l10n.marketStatusMatched : l10n.marketStatusOpen}'
              '${daysLeft != null ? ' · ${l10n.marketDaysLeft(daysLeft)}' : ''}',
            ),
            trailing: Chip(
              label: Text(
                isMatched ? l10n.marketStatusMatched : l10n.marketStatusOpen,
              ),
              backgroundColor: isMatched ? const Color(0xFFE8F5E9) : null,
            ),
          ),
          for (final m in request.matches)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: m.buyerInfo == null
                      ? null
                      : () => _showBuyerDetails(context, m.buyerInfo!),
                  child: Text(m.buyerInfo?.buyerName ?? 'Vendor'),
                ),
              ),
              subtitle: Text(
                '${m.quantityKg?.toStringAsFixed(0) ?? '—'} kg · '
                '${money(m.buyerInfo?.offeredPrice)} · '
                '${m.buyerInfo?.distanceKm?.toStringAsFixed(1) ?? '—'} km',
              ),
              trailing: m.isConfirmed
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : FilledButton.tonal(
                      onPressed: onConfirm,
                      child: Text(l10n.marketConfirmSale),
                    ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onExtend,
                  icon: const Icon(Icons.update),
                  label: Text(l10n.marketExtendShelfLife),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
