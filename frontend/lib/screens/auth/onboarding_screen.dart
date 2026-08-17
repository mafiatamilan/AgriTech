import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
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

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _phone = TextEditingController();
  final _locality = TextEditingController();
  String? _soilType;
  bool _saving = false;

  @override
  void dispose() {
    _phone.dispose();
    _locality.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final l10n = AppLocalizations.of(context);
    if (_phone.text.trim().isEmpty) {
      showError(context, l10n.onboardingPhoneInvalid);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(authProvider.notifier).completeOnboarding(
            phone: _phone.text.trim(),
            soilType: _soilType ?? 'loamy',
            areaLocality: _locality.text.trim(),
          );
    } on Exception catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.onboardingTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.onboardingSubtitle),
          const SizedBox(height: 16),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: l10n.onboardingPhone),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _soilType,
            decoration: InputDecoration(labelText: l10n.onboardingSoilType),
            items: [
              for (final t in _soilTypes)
                DropdownMenuItem(value: t, child: Text(_soilLabel(l10n, t))),
            ],
            onChanged: (v) => setState(() => _soilType = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _locality,
            decoration: InputDecoration(labelText: l10n.onboardingLocality),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _finish,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.onboardingFinish),
          ),
        ],
      ),
    );
  }

  String _soilLabel(AppLocalizations l10n, String t) {
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