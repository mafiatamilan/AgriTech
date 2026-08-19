import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'providers/providers.dart';
import 'screens/account/account_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/impact/impact_screen.dart';
import 'screens/inventory/inventory_screen.dart';
import 'screens/market/market_screen.dart';
import 'screens/motor/motor_screen.dart';
import 'screens/performance/performance_screen.dart';
import 'screens/recommendations/recommendations_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/upload/upload_screen.dart';

/// Bottom-nav destinations (the rest live in the drawer).
const _primaryTabs = [0, 1, 2, 3];

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _go(int i) => setState(() => _index = i);

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    // Keep the realtime subscription alive while logged in.
    ref.watch(realtimeController);
    final l10n = AppLocalizations.of(context);
    final pages = <Widget>[
      HomeScreen(onNavigate: _go, onOpenDrawer: _openDrawer),
      const MotorScreen(),
      const MarketScreen(),
      const UploadScreen(),
      const RecommendationsScreen(),
      const ImpactScreen(),
      const SettingsScreen(),
      const AccountScreen(),
      const InventoryScreen(),
      const PerformanceScreen(),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(context, l10n),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _primaryTabs.contains(_index) ? _index : 0,
        onDestinationSelected: _go,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.water_drop_outlined),
            selectedIcon: const Icon(Icons.water_drop),
            label: l10n.navMotor,
          ),
          NavigationDestination(
            icon: const Icon(Icons.storefront_outlined),
            selectedIcon: const Icon(Icons.storefront),
            label: l10n.navMarket,
          ),
          NavigationDestination(
            icon: const Icon(Icons.camera_alt_outlined),
            selectedIcon: const Icon(Icons.camera_alt),
            label: l10n.navUpload,
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, AppLocalizations l10n) {
    final entries = <(int, String, IconData)>[
      (0, l10n.navHome, Icons.home_outlined),
      (1, l10n.navMotor, Icons.water_drop_outlined),
      (2, l10n.navMarket, Icons.storefront_outlined),
      (3, l10n.navUpload, Icons.camera_alt_outlined),
      (4, l10n.navRecommendations, Icons.insights_outlined),
      (5, l10n.navImpact, Icons.leaderboard_outlined),
      (6, l10n.navSettings, Icons.settings_outlined),
      (7, l10n.navAccount, Icons.person_outline),
      (8, l10n.navInventory, Icons.inventory_2_outlined),
      (9, l10n.navPerformance, Icons.bar_chart_outlined),
    ];
    return Drawer(
      child: ListView(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
            ),
            child: Text(
              l10n.appTitle,
              style: const TextStyle(color: Colors.white, fontSize: 22),
            ),
          ),
          for (final (i, label, icon) in entries)
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              selected: _index == i,
              onTap: () {
                Navigator.pop(context);
                _go(i);
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l10n.commonSignOut),
            onTap: () {
              Navigator.pop(context);
              ref.read(authProvider.notifier).signOut();
            },
          ),
        ],
      ),
    );
  }
}
