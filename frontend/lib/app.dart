import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell.dart';
import 'core/theme.dart';
import 'l10n/app_localizations.dart';
import 'providers/providers.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/onboarding_screen.dart';

class AgriTechApp extends ConsumerWidget {
  const AgriTechApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final child = switch (auth.status) {
      AuthStatus.loading => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      AuthStatus.needsLogin => const LoginScreen(),
      AuthStatus.needsOnboarding => const OnboardingScreen(),
      AuthStatus.ready => const AppShell(),
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