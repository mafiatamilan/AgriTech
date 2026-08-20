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
  final _businessNameController = TextEditingController();
  final _vendorPhoneController = TextEditingController();
  final _vendorEmailController = TextEditingController();
  final _vendorAddressController = TextEditingController();
  final _cropController = TextEditingController();
  final _qtyController = TextEditingController();
  final _priceController = TextEditingController();
  bool _signedUp = false;
  bool _submitting = false;
  bool _planningRoute = false;

  @override
  void dispose() {
    _businessNameController.dispose();
    _vendorPhoneController.dispose();
    _vendorEmailController.dispose();
    _vendorAddressController.dispose();
    _cropController.dispose();
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    final businessName = _businessNameController.text.trim();
    final phone = _vendorPhoneController.text.trim();
    final email = _vendorEmailController.text.trim();
    final address = _vendorAddressController.text.trim();
    if (businessName.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        address.isEmpty) {
      if (mounted) {
        showError(context, 'Enter vendor name, phone, email, and address');
      }
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(backendProvider)
          .vendorSignup(
            name: businessName,
            businessName: businessName,
            phone: phone,
            email: email,
            address: address,
          );
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

  Future<void> _planTransport(DemandRequest opportunity) async {
    final available = opportunity.remainingQuantityKg ?? opportunity.quantityKg;
    final request = await showDialog<_TransportPlanInput>(
      context: context,
      builder: (context) => _TransportPlanDialog(
        opportunity: opportunity,
        defaultQuantityKg: available,
      ),
    );
    if (!mounted || request == null) return;

    setState(() => _planningRoute = true);
    try {
      final recommendation = await ref
          .read(backendProvider)
          .vendorPlanRoute(
            requestId: opportunity.id,
            pickupLatitude: request.pickupLatitude,
            pickupLongitude: request.pickupLongitude,
            deliveryLatitude: request.deliveryLatitude,
            deliveryLongitude: request.deliveryLongitude,
            quantityKg: request.quantityKg,
            vehicleType: request.vehicleType,
            vehicleCapacityKg: request.vehicleCapacityKg,
            transportCostPerKm: request.transportCostPerKm,
            refrigerated: request.refrigerated,
            shelfLifeHours: request.shelfLifeHours,
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) =>
            _TransportRecommendationDialog(recommendation: recommendation),
      );
    } on Exception catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _planningRoute = false);
    }
  }

  Future<void> _planConfirmedSaleTransport(ConfirmedSale sale) async {
    final request = await showDialog<_TransportPlanInput>(
      context: context,
      builder: (context) => _TransportPlanDialog(
        opportunity: DemandRequest(
          id: sale.matchId,
          cropName: sale.cropName,
          quantityKg: sale.quantityKg,
          remainingQuantityKg: sale.quantityKg,
        ),
        defaultQuantityKg: sale.quantityKg,
      ),
    );
    if (!mounted || request == null) return;

    setState(() => _planningRoute = true);
    try {
      final recommendation = await ref
          .read(backendProvider)
          .vendorPlanTransportRoute(
            deliveryDay: request.deliveryDay,
            pickupLatitude: request.pickupLatitude,
            pickupLongitude: request.pickupLongitude,
            deliveryLatitude: request.deliveryLatitude,
            deliveryLongitude: request.deliveryLongitude,
            quantityKg: request.quantityKg,
            cropName: sale.cropName,
            vehicleType: request.vehicleType,
            vehicleCapacityKg: request.vehicleCapacityKg,
            transportCostPerKm: request.transportCostPerKm,
            refrigerated: request.refrigerated,
          );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) =>
            _TransportRecommendationDialog(recommendation: recommendation),
      );
    } on Exception catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _planningRoute = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final requests = ref.watch(vendorRequestsProvider);
    final badge = ref.watch(authProvider).profile?.verificationBadge;

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop() ? const BackButton() : null,
        title: Text(l10n.appTitle),
        actions: [
          if (badge == 'VERIFIED_VENDOR')
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Chip(
                avatar: Icon(Icons.verified, size: 18),
                label: Text('Verified Buyer'),
              ),
            ),
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
              ? _SignupView(
                  businessNameController: _businessNameController,
                  phoneController: _vendorPhoneController,
                  emailController: _vendorEmailController,
                  addressController: _vendorAddressController,
                  submitting: _submitting,
                  onSignup: _signup,
                )
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
              _VendorKpiGrid(provider: ref.watch(vendorKpisProvider)),
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
              _VendorOpportunitiesList(
                planningRoute: _planningRoute,
                onAccept: _accept,
                onPlanTransport: _planTransport,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Confirmed sales for transport',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _ConfirmedSalesList(
                planningRoute: _planningRoute,
                onPlanTransport: _planConfirmedSaleTransport,
              ),
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
    ref.invalidate(vendorKpisProvider);
    ref.invalidate(vendorConfirmedSalesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

class _VendorKpiGrid extends StatelessWidget {
  const _VendorKpiGrid({required this.provider});

  final AsyncValue<List<KpiItem>> provider;

  @override
  Widget build(BuildContext context) {
    final items = provider.value ?? const <KpiItem>[];
    if (provider.isLoading && items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.7,
        children: [
          for (final item in items)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${item.value.toStringAsFixed(item.value.truncateToDouble() == item.value ? 0 : 1)} ${item.unit ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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

class _VendorOpportunitiesList extends ConsumerWidget {
  const _VendorOpportunitiesList({
    required this.planningRoute,
    required this.onAccept,
    required this.onPlanTransport,
  });

  final bool planningRoute;
  final Future<void> Function(DemandRequest opportunity) onAccept;
  final Future<void> Function(DemandRequest opportunity) onPlanTransport;

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
                      planningRoute: planningRoute,
                      onAccept: () => onAccept(o),
                      onPlanTransport: () => onPlanTransport(o),
                    ),
                ],
              );
      },
    );
  }
}

class _ConfirmedSalesList extends ConsumerWidget {
  const _ConfirmedSalesList({
    required this.planningRoute,
    required this.onPlanTransport,
  });

  final bool planningRoute;
  final Future<void> Function(ConfirmedSale sale) onPlanTransport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = ref.watch(vendorConfirmedSalesProvider);
    return sales.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(8),
        child: ErrorView(
          onRetry: () => ref.invalidate(vendorConfirmedSalesProvider),
        ),
      ),
      data: (items) => items.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('No confirmed sales yet')),
            )
          : Column(
              children: [
                for (final sale in items)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.local_shipping_outlined),
                      title: Text(sale.cropName),
                      subtitle: Text(
                        '${sale.quantityKg.toStringAsFixed(0)} kg'
                        '${sale.farmerProfile?.name == null ? '' : ' · ${sale.farmerProfile!.name}'}',
                      ),
                      trailing: FilledButton.tonalIcon(
                        onPressed: planningRoute
                            ? null
                            : () => onPlanTransport(sale),
                        icon: const Icon(Icons.route_outlined),
                        label: const Text('Route'),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _SignupView extends StatelessWidget {
  const _SignupView({
    required this.businessNameController,
    required this.phoneController,
    required this.emailController,
    required this.addressController,
    required this.submitting,
    required this.onSignup,
  });

  final TextEditingController businessNameController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController addressController;
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
            const SizedBox(height: 16),
            TextField(
              controller: businessNameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Vendor name',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email address',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressController,
              minLines: 2,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Address',
                isDense: true,
              ),
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

void _showFarmerDetails(BuildContext context, PartyProfile farmer) {
  final name = farmer.name?.trim().isNotEmpty == true ? farmer.name! : 'Farmer';
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProfileDetailRow(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: farmer.phone,
          ),
          _ProfileDetailRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: farmer.email,
          ),
          _ProfileDetailRow(
            icon: Icons.location_on_outlined,
            label: 'Address',
            value: farmer.address,
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

class _ProfileDetailRow extends StatelessWidget {
  const _ProfileDetailRow({
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

class _TransportPlanInput {
  _TransportPlanInput({
    required this.deliveryDay,
    required this.pickupLatitude,
    required this.pickupLongitude,
    required this.deliveryLatitude,
    required this.deliveryLongitude,
    required this.quantityKg,
    required this.vehicleType,
    required this.vehicleCapacityKg,
    required this.transportCostPerKm,
    required this.refrigerated,
    this.shelfLifeHours,
  });

  final DateTime deliveryDay;
  final double pickupLatitude;
  final double pickupLongitude;
  final double deliveryLatitude;
  final double deliveryLongitude;
  final double quantityKg;
  final String vehicleType;
  final double vehicleCapacityKg;
  final double transportCostPerKm;
  final bool refrigerated;
  final double? shelfLifeHours;
}

class _TransportPlanDialog extends StatefulWidget {
  const _TransportPlanDialog({
    required this.opportunity,
    required this.defaultQuantityKg,
  });

  final DemandRequest opportunity;
  final double? defaultQuantityKg;

  @override
  State<_TransportPlanDialog> createState() => _TransportPlanDialogState();
}

class _TransportPlanDialogState extends State<_TransportPlanDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _pickupLat;
  late final TextEditingController _pickupLon;
  late final TextEditingController _deliveryLat;
  late final TextEditingController _deliveryLon;
  late final TextEditingController _quantity;
  late final TextEditingController _capacity;
  late final TextEditingController _costPerKm;
  late final TextEditingController _shelfLife;
  String _vehicleType = 'small_truck';
  bool _refrigerated = false;
  DateTime _deliveryDay = DateTime.now().add(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    _pickupLat = TextEditingController();
    _pickupLon = TextEditingController();
    _deliveryLat = TextEditingController();
    _deliveryLon = TextEditingController();
    _quantity = TextEditingController(
      text: widget.defaultQuantityKg == null
          ? ''
          : widget.defaultQuantityKg!.toStringAsFixed(2),
    );
    _capacity = TextEditingController(text: '1000');
    _costPerKm = TextEditingController(text: '15');
    _shelfLife = TextEditingController(
      text: widget.opportunity.shelfLifeDays == null
          ? ''
          : (widget.opportunity.shelfLifeDays! * 24).toString(),
    );
  }

  @override
  void dispose() {
    _pickupLat.dispose();
    _pickupLon.dispose();
    _deliveryLat.dispose();
    _deliveryLon.dispose();
    _quantity.dispose();
    _capacity.dispose();
    _costPerKm.dispose();
    _shelfLife.dispose();
    super.dispose();
  }

  double? _readPositive(TextEditingController controller) {
    final value = double.tryParse(controller.text.trim());
    if (value == null || value <= 0) return null;
    return value;
  }

  double? _readCoordinate(TextEditingController controller) {
    return double.tryParse(controller.text.trim());
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _TransportPlanInput(
        deliveryDay: _deliveryDay,
        pickupLatitude: _readCoordinate(_pickupLat)!,
        pickupLongitude: _readCoordinate(_pickupLon)!,
        deliveryLatitude: _readCoordinate(_deliveryLat)!,
        deliveryLongitude: _readCoordinate(_deliveryLon)!,
        quantityKg: _readPositive(_quantity)!,
        vehicleType: _vehicleType,
        vehicleCapacityKg: _readPositive(_capacity)!,
        transportCostPerKm: _readPositive(_costPerKm)!,
        refrigerated: _refrigerated,
        shelfLifeHours: _shelfLife.text.trim().isEmpty
            ? null
            : _readPositive(_shelfLife),
      ),
    );
  }

  String? _validateCoordinate(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    return parsed == null ? 'Enter a valid number' : null;
  }

  String? _validatePositive(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    return parsed == null || parsed <= 0 ? 'Enter a value above 0' : null;
  }

  String? _validateOptionalPositive(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _validatePositive(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Plan transport for ${widget.opportunity.cropName}'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Delivery day'),
                subtitle: Text(fmtDate(_deliveryDay)),
                trailing: TextButton(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _deliveryDay,
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 60)),
                    );
                    if (picked != null) {
                      setState(() => _deliveryDay = picked);
                    }
                  },
                  child: const Text('Change'),
                ),
              ),
              TextFormField(
                controller: _pickupLat,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: 'Pickup latitude'),
                validator: _validateCoordinate,
              ),
              TextFormField(
                controller: _pickupLon,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Pickup longitude',
                ),
                validator: _validateCoordinate,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _deliveryLat,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Delivery latitude',
                ),
                validator: _validateCoordinate,
              ),
              TextFormField(
                controller: _deliveryLon,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Delivery longitude',
                ),
                validator: _validateCoordinate,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _vehicleType,
                decoration: const InputDecoration(labelText: 'Vehicle type'),
                items: const [
                  DropdownMenuItem(
                    value: 'small_truck',
                    child: Text('Small truck'),
                  ),
                  DropdownMenuItem(
                    value: 'large_truck',
                    child: Text('Large truck'),
                  ),
                  DropdownMenuItem(
                    value: 'refrigerated_van',
                    child: Text('Refrigerated van'),
                  ),
                  DropdownMenuItem(
                    value: 'reefer_truck',
                    child: Text('Reefer truck'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _vehicleType = value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Refrigerated transport'),
                value: _refrigerated,
                onChanged: (value) => setState(() => _refrigerated = value),
              ),
              TextFormField(
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Quantity (kg)'),
                validator: _validatePositive,
              ),
              TextFormField(
                controller: _capacity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Vehicle capacity (kg)',
                ),
                validator: _validatePositive,
              ),
              TextFormField(
                controller: _costPerKm,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Cost per km'),
                validator: _validatePositive,
              ),
              TextFormField(
                controller: _shelfLife,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Remaining shelf life (hours, optional)',
                ),
                validator: _validateOptionalPositive,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.local_shipping_outlined),
          label: const Text('Plan route'),
        ),
      ],
    );
  }
}

class _TransportRecommendationDialog extends StatelessWidget {
  const _TransportRecommendationDialog({required this.recommendation});

  final TransportRouteRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final best = recommendation.bestRoute;
    return AlertDialog(
      title: const Text('Transport recommendation'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              recommendation.crop,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _TransportMetric(label: 'Best route', value: best.label),
            _TransportMetric(
              label: 'Distance',
              value:
                  '${recommendation.estimatedDistanceKm.toStringAsFixed(1)} km',
            ),
            _TransportMetric(
              label: 'Duration',
              value: '${recommendation.estimatedDurationMinutes} min',
            ),
            _TransportMetric(
              label: 'Cost',
              value: money(recommendation.estimatedTransportCost),
            ),
            _TransportMetric(
              label: 'Spoilage risk',
              value: recommendation.spoilageRisk,
            ),
            _TransportMetric(
              label: 'Delay risk',
              value: recommendation.delayRisk,
            ),
            _TransportMetric(
              label: 'Capacity',
              value: best.vehicleCapacityFit ? 'Fits vehicle' : 'Too large',
            ),
            if (recommendation.reasonLabels.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Reasons', style: Theme.of(context).textTheme.titleSmall),
              for (final reason in recommendation.reasonLabels)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(reason)),
                    ],
                  ),
                ),
            ],
            if (recommendation.routeOptions.length > 1) ...[
              const SizedBox(height: 12),
              Text(
                'Other options',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final option in recommendation.routeOptions.skip(1))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(option.label),
                  subtitle: Text(
                    '${option.distanceKm.toStringAsFixed(1)} km · '
                    '${option.estimatedTimeHours.toStringAsFixed(1)} h · '
                    '${money(option.estimatedTransportCost)}',
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _TransportMetric extends StatelessWidget {
  const _TransportMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _OpportunityTile extends StatelessWidget {
  const _OpportunityTile({
    required this.opportunity,
    required this.planningRoute,
    required this.onAccept,
    required this.onPlanTransport,
  });

  final DemandRequest opportunity;
  final bool planningRoute;
  final VoidCallback onAccept;
  final VoidCallback onPlanTransport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final available = opportunity.remainingQuantityKg ?? opportunity.quantityKg;
    final farmer = opportunity.farmerProfile;
    final farmerName = farmer?.name?.trim().isNotEmpty == true
        ? farmer!.name!
        : 'Farmer';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.agriculture_outlined),
        title: Text(opportunity.cropName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${available?.toStringAsFixed(0) ?? '—'} kg available · '
              '${money(opportunity.expectedPrice)} · '
              '${opportunity.harvestedDate != null ? fmtDate(opportunity.harvestedDate!) : '—'}',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: farmer == null
                    ? null
                    : () => _showFarmerDetails(context, farmer),
                icon: const Icon(Icons.person_outline, size: 18),
                label: Text(farmerName),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed:
                      available == null || available <= 0 || planningRoute
                      ? null
                      : onPlanTransport,
                  icon: planningRoute
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.local_shipping_outlined),
                  label: const Text('Plan route'),
                ),
                FilledButton.tonal(
                  onPressed: available == null || available <= 0
                      ? null
                      : onAccept,
                  child: Text(l10n.vendorAccept),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
