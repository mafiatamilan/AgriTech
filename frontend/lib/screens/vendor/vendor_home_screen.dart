import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/shared.dart';

class VendorHomeScreen extends ConsumerStatefulWidget {
  const VendorHomeScreen({super.key});

  @override
  ConsumerState<VendorHomeScreen> createState() => _VendorHomeScreenState();
}

class _VendorHomeScreenState extends ConsumerState<VendorHomeScreen> {
  final _cropController = TextEditingController();
  final _qtyController = TextEditingController();
  final _priceController = TextEditingController();
  bool _signedUp = false;
  bool _submitting = false;

  @override
  void dispose() {
    _cropController.dispose();
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    setState(() => _submitting = true);
    try {
      await ref.read(backendProvider).vendorSignup();
      setState(() => _signedUp = true);
      ref.invalidate(vendorRequestsProvider);
      ref.invalidate(vendorOpportunitiesProvider);
    } on Exception catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _addRequest() async {
    final l10n = AppLocalizations.of(context);
    if (_cropController.text.trim().isEmpty) {
      if (mounted) showError(context, '${l10n.vendorCropName} is required');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(backendProvider)
          .vendorCreateRequest(
            cropName: _cropController.text.trim(),
            quantityNeeded: double.tryParse(_qtyController.text),
            expectedPrice: double.tryParse(_priceController.text),
          );
      ref.invalidate(vendorRequestsProvider);
      _cropController.clear();
      _qtyController.clear();
      _priceController.clear();
    } on Exception catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _accept(DemandRequest opportunity) async {
    final l10n = AppLocalizations.of(context);
    final available = opportunity.remainingQuantityKg ?? opportunity.quantityKg;
    var quantityText = available == null ? '' : available.toStringAsFixed(2);
    final quantity = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('How much ${opportunity.cropName} do you need?'),
        content: TextFormField(
          initialValue: quantityText,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Quantity (kg)'),
          onChanged: (value) => quantityText = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(quantityText.trim())),
            child: Text(l10n.vendorAccept),
          ),
        ],
      ),
    );
    if (!mounted || quantity == null || quantity <= 0) return;
    if (available != null && quantity > available) {
      showError(
        context,
        'Only ${available.toStringAsFixed(2)} kg is available',
      );
      return;
    }
    try {
      await ref.read(backendProvider).vendorAccept(opportunity.id, quantity);
      ref.invalidate(vendorOpportunitiesProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.vendorBidPlaced)));
      }
    } on Exception catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final requests = ref.watch(vendorRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop() ? const BackButton() : null,
        title: Text(l10n.appTitle),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: requests.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => !_signedUp
              ? _SignupView(submitting: _submitting, onSignup: _signup)
              : ErrorView(
                  onRetry: () => ref.invalidate(vendorRequestsProvider),
                ),
          data: (items) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.vendorNeedTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _cropController,
                        decoration: InputDecoration(
                          labelText: l10n.vendorCropName,
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _qtyController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l10n.vendorQuantity,
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l10n.vendorExpectedPrice,
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _submitting ? null : _addRequest,
                          child: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.vendorAdd),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  l10n.vendorRequests,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: Text(l10n.vendorEmpty)),
                )
              else
                for (final r in items) _VendorRequestTile(request: r),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  l10n.vendorOpportunities,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _VendorOpportunitiesList(onAccept: _accept),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(vendorRequestsProvider);
    ref.invalidate(vendorOpportunitiesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

class _VendorOpportunitiesList extends ConsumerWidget {
  const _VendorOpportunitiesList({required this.onAccept});

  final Future<void> Function(DemandRequest opportunity) onAccept;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final opportunities = ref.watch(vendorOpportunitiesProvider);

    return opportunities.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(8),
        child: ErrorView(
          onRetry: () => ref.invalidate(vendorOpportunitiesProvider),
        ),
      ),
      data: (ops) {
        final realOps = ops
            .where(
              (o) =>
                  o.cropName.trim().isNotEmpty &&
                  (o.remainingQuantityKg ?? o.quantityKg ?? 0) > 0,
            )
            .toList();
        return realOps.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Center(child: Text(l10n.vendorEmpty)),
              )
            : Column(
                children: [
                  for (final o in realOps)
                    _OpportunityTile(
                      opportunity: o,
                      onAccept: () => onAccept(o),
                    ),
                ],
              );
      },
    );
  }
}

class _SignupView extends StatelessWidget {
  const _SignupView({required this.submitting, required this.onSignup});

  final bool submitting;
  final VoidCallback onSignup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.storefront, size: 64, color: AppColors.green),
            const SizedBox(height: 16),
            Text(
              l10n.vendorSignupTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: submitting ? null : onSignup,
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.vendorSignup),
            ),
          ],
        ),
      ),
    );
  }
}

class _VendorRequestTile extends StatelessWidget {
  const _VendorRequestTile({required this.request});

  final VendorRequest request;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.shopping_basket_outlined),
        title: Text(request.cropName),
        subtitle: Text(
          '${request.quantityNeeded?.toStringAsFixed(0) ?? '—'} kg · '
          '${money(request.expectedPrice)} · ${request.status}',
        ),
      ),
    );
  }
}

class _OpportunityTile extends StatelessWidget {
  const _OpportunityTile({required this.opportunity, required this.onAccept});

  final DemandRequest opportunity;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final available = opportunity.remainingQuantityKg ?? opportunity.quantityKg;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.agriculture_outlined),
        title: Text(opportunity.cropName),
        subtitle: Text(
          '${available?.toStringAsFixed(0) ?? '—'} kg available · '
          '${money(opportunity.expectedPrice)} · '
          '${opportunity.harvestedDate != null ? fmtDate(opportunity.harvestedDate!) : '—'}',
        ),
        trailing: FilledButton.tonal(
          onPressed: available == null || available <= 0 ? null : onAccept,
          child: Text(l10n.vendorAccept),
        ),
      ),
    );
  }
}
