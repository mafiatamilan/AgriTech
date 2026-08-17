import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/providers.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.agriculture, size: 72, color: AppColors.green),
              const SizedBox(height: 16),
              Text(
                l10n.appTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => ref
                    .read(authProvider.notifier)
                    .signInWithGoogle(),
                icon: const Icon(Icons.login),
                label: Text(l10n.continueWithGoogle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}