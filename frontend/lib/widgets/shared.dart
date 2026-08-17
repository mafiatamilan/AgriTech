import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../l10n/app_localizations.dart';

String fmtDate(DateTime? d) =>
    d == null ? '—' : DateFormat('dd MMM yyyy, HH:mm').format(d);

String fmtDays(DateTime? from) =>
    from == null ? '—' : '${from.difference(DateTime.now()).inDays}';

String money(num? v) => v == null
    ? '—'
    : NumberFormat.currency(locale: 'en', symbol: '₹').format(v);

/// Farm dropdown shown on farm-scoped pages. Falls back to a hint if
/// the farmer has no farms yet.
class FarmSwitcher extends ConsumerWidget {
  const FarmSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final farms = ref.watch(farmsProvider);
    final farm = farms.currentFarm;
    if (farms.farms.length <= 1) {
      return farm == null
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                children: [
                  Text(AppLocalizations.of(context).homeNoFarm),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _promptCreateFarm(context, ref),
                    icon: const Icon(Icons.add),
                    label: Text(AppLocalizations.of(context).homeCreateFarm),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: DropdownButtonFormField<String>(
        initialValue: farm?.id,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.agriculture),
          isDense: true,
        ),
        items: [
          for (final f in farms.farms)
            DropdownMenuItem(value: f.id, child: Text(f.name)),
        ],
        onChanged: (id) {
          if (id != null) ref.read(farmsProvider.notifier).select(id);
        },
      ),
    );
  }
}

/// Error + retry view used when a provider throws and no cache exists.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.onRetry, this.message});

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message ?? l10n.commonError, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: Text(l10n.commonRetry)),
        ],
      ),
    );
  }
}

Future<void> _promptCreateFarm(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppLocalizations.of(context).homeCreateFarm),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'My Farm'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context).commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text(AppLocalizations.of(context).homeCreateFarm),
        ),
      ],
    ),
  );
  if (name == null || name.isEmpty) return;
  try {
    await ref.read(farmsProvider.notifier).create(name);
    final farm = ref.read(farmsProvider).currentFarm;
    if (farm != null && context.mounted) {
      await setFarmLocation(context, ref, farm);
    }
  } on Exception catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Asks for device location; falls back to a manual lat/lon dialog if the
/// permission is denied, so farmers can always set their farm location.
Future<void> setFarmLocation(
  BuildContext context,
  WidgetRef ref,
  Farm farm,
) async {
  final l10n = AppLocalizations.of(context);
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  final denied = permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever;
  double? lat, lon;
  if (denied) {
    if (!context.mounted) return;
    final manual = await _promptManualLocation(context);
    if (manual == null) return;
    lat = manual.$1;
    lon = manual.$2;
  } else {
    try {
      final pos = await Geolocator.getCurrentPosition();
      lat = pos.latitude;
      lon = pos.longitude;
    } on Exception {
      if (!context.mounted) return;
      final manual = await _promptManualLocation(context);
      if (manual == null) return;
      lat = manual.$1;
      lon = manual.$2;
    }
  }
  try {
    await ref.read(backendProvider).updateFarmLocation(farm.id, lat, lon);
    ref.invalidate(marketRequestsProvider);
    ref.invalidate(farmsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.locationSet)),
      );
    }
  } on Exception catch (e) {
    if (context.mounted) showError(context, e);
  }
}

Future<(double, double)?> _promptManualLocation(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final latCtl = TextEditingController();
  final lonCtl = TextEditingController();
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.locationEnterManually),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: latCtl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: l10n.locationLatitude),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: lonCtl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: l10n.locationLongitude),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.commonSave),
        ),
      ],
    ),
  );
  if (saved != true) return null;
  final lat = double.tryParse(latCtl.text.trim());
  final lon = double.tryParse(lonCtl.text.trim());
  if (lat == null || lon == null) {
    if (context.mounted) showError(context, l10n.locationInvalid);
    return null;
  }
  return (lat, lon);
}

/// "Showing last saved data · updated …" banner when data came from cache.
class StaleBanner extends StatelessWidget {
  const StaleBanner({super.key, required this.savedAt});

  final DateTime savedAt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      color: Colors.orange.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        l10n.motorStaleData(DateFormat('dd MMM HH:mm').format(savedAt)),
        style: TextStyle(color: Colors.orange.shade900, fontSize: 12),
      ),
    );
  }
}

void showError(BuildContext context, Object? error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString())),
  );
}

Widget moistureLineChart(List<MoistureReading> readings) {
  if (readings.length < 2) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Text('Not enough sensor data yet.'),
    );
  }
  final minPct =
      readings.map((r) => r.moisturePct).reduce((a, b) => a < b ? a : b);
  final maxPct =
      readings.map((r) => r.moisturePct).reduce((a, b) => a > b ? a : b);
  final span = (maxPct - minPct).clamp(5.0, double.infinity);

  return SizedBox(
    height: 180,
    child: CustomPaint(
      painter: _LinePainter(readings, minPct, span),
    ),
  );
}

/// Hand-rolled line chart — fl_chart is heavy for a single sparkline.
class _LinePainter extends CustomPainter {
  _LinePainter(this.readings, this.minPct, this.span);

  final List<MoistureReading> readings;
  final double minPct;
  final double span;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFF2E7D32)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = const Color(0x332E7D32);
    final path = Path();
    final fillPath = Path();
    final stepX = readings.length <= 1 ? 0.0 : size.width / (readings.length - 1);
    for (var i = 0; i < readings.length; i++) {
      final x = stepX * i;
      final y = size.height -
          ((readings[i].moisturePct - minPct) / span) * (size.height - 10);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fill);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.readings != readings || old.minPct != minPct;
}