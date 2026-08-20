import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell.dart';
import 'core/theme.dart';
import 'l10n/app_localizations.dart';
import 'providers/providers.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/identity_onboarding_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/vendor/vendor_home_screen.dart';

class AgriTechApp extends ConsumerWidget {
  const AgriTechApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final accountType = ref.watch(accountTypeProvider);
    final child = switch (auth.status) {
      AuthStatus.loading => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      AuthStatus.needsLogin => const LoginScreen(),
      AuthStatus.needsVerification => const IdentityOnboardingScreen(),
      AuthStatus.needsOnboarding =>
        accountType == AccountType.vendor
            ? const VendorHomeScreen()
            : const OnboardingScreen(),
      AuthStatus.ready =>
        accountType == AccountType.vendor
            ? const VendorHomeScreen()
            : const AppShell(),
    };

    return MaterialApp(
      title: 'AgriTech',
      theme: buildTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }
}
