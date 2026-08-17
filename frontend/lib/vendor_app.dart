import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'l10n/app_localizations.dart';
import 'providers/providers.dart';
import 'screens/auth/login_screen.dart';
import 'screens/vendor/vendor_home_screen.dart';

/// Second entry point (Market Vendors App). Same codebase, separate
/// auth role + UI. Build with:
///   flutter run -t lib/main_vendor.dart
class VendorApp extends ConsumerWidget {
  const VendorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final child = switch (auth.status) {
      AuthStatus.loading => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      AuthStatus.needsLogin || AuthStatus.needsOnboarding => const LoginScreen(),
      AuthStatus.ready => const VendorHomeScreen(),
    };

    return MaterialApp(
      title: 'AgriTech Vendors',
      theme: buildTheme(),
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: child,
    );
  }
}