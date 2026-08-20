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

const _navigationEntries =
    <({int index, IconData icon, IconData selectedIcon})>[
      (index: 0, icon: Icons.home_outlined, selectedIcon: Icons.home),
      (
        index: 1,
        icon: Icons.water_drop_outlined,
        selectedIcon: Icons.water_drop,
      ),
      (
        index: 2,
        icon: Icons.storefront_outlined,
        selectedIcon: Icons.storefront,
      ),
      (
        index: 3,
        icon: Icons.camera_alt_outlined,
        selectedIcon: Icons.camera_alt,
      ),
      (index: 4, icon: Icons.insights_outlined, selectedIcon: Icons.insights),
      (
        index: 5,
        icon: Icons.leaderboard_outlined,
        selectedIcon: Icons.leaderboard,
      ),
      (index: 6, icon: Icons.settings_outlined, selectedIcon: Icons.settings),
      (index: 7, icon: Icons.person_outline, selectedIcon: Icons.person),
      (
        index: 8,
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2,
      ),
      (index: 9, icon: Icons.bar_chart_outlined, selectedIcon: Icons.bar_chart),
    ];

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  final List<int> _history = [0];
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _go(int i) => setState(() {
    if (i != _index) {
      _history.add(i);
      _index = i;
    }
  });

  void _back() => setState(() {
    if (_history.length > 1) {
      _history.removeLast();
      _index = _history.last;
    } else {
      _index = 0;
    }
  });

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    // Keep the realtime subscription alive while logged in.
    ref.watch(realtimeController);
    final l10n = AppLocalizations.of(context);
    final labels = _labels(l10n);
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
      drawer: _buildDrawer(context, l10n, labels),
      body: Stack(
        children: [
          IndexedStack(index: _index, children: pages),
          if (_index != 0)
            Positioned(
              top: MediaQuery.of(context).padding.top + 6,
              left: 8,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 2,
                borderRadius: BorderRadius.circular(8),
                child: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _back,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _primaryTabs.contains(_index) ? _index : 0,
        onDestinationSelected: _go,
        destinations: [
          for (final entry in _navigationEntries.take(4))
            NavigationDestination(
              icon: Icon(entry.icon),
              selectedIcon: Icon(entry.selectedIcon),
              label: labels[entry.index],
            ),
        ],
      ),
    );
  }

  Widget _buildDrawer(
    BuildContext context,
    AppLocalizations l10n,
    List<String> labels,
  ) {
    final theme = Theme.of(context);
    final profile = ref.watch(authProvider).profile;
    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.of(context).padding.top + 20,
              20,
              20,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1B5E20),
                  Color(0xFF2E7D32),
                  Color(0xFF8D5A2B),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white,
                  foregroundColor: Color(0xFF1B5E20),
                  child: Icon(Icons.agriculture, size: 28),
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.appTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (profile?.name.isNotEmpty ?? false) ...[
                  const SizedBox(height: 4),
                  Text(
                    profile!.name,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Navigate',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 4),
          for (final entry in _navigationEntries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: ListTile(
                selected: _index == entry.index,
                selectedTileColor: theme.colorScheme.primaryContainer,
                selectedColor: theme.colorScheme.onPrimaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                leading: Icon(
                  _index == entry.index ? entry.selectedIcon : entry.icon,
                ),
                title: Text(labels[entry.index]),
                trailing: _index == entry.index
                    ? const Icon(Icons.chevron_right)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _go(entry.index);
                },
              ),
            ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              leading: const Icon(Icons.logout),
              title: Text(l10n.commonSignOut),
              onTap: () {
                Navigator.pop(context);
                ref.read(authProvider.notifier).signOut();
              },
            ),
          ),
        ],
      ),
    );
  }

  List<String> _labels(AppLocalizations l10n) => [
    l10n.navHome,
    l10n.navMotor,
    l10n.navMarket,
    l10n.navUpload,
    l10n.navRecommendations,
    l10n.navImpact,
    l10n.navSettings,
    l10n.navAccount,
    l10n.navInventory,
    l10n.navPerformance,
  ];
}
