import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/shared.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navNotifications)),
      body: provider.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          onRetry: () => ref.invalidate(notificationsProvider),
        ),
        data: (items) => items.isEmpty
            ? Center(child: Text(l10n.homeNoNotifications))
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(notificationsProvider),
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final n = items[i];
                    return ListTile(
                      leading: Icon(_icon(n.type),
                          color: n.isRead ? Colors.grey : Colors.green),
                      title: Text(
                        n.title,
                        style: n.isRead
                            ? null
                            : const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.body),
                          Text(
                            DateFormat('dd MMM yyyy, HH:mm').format(n.createdAt ?? DateTime.now()),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      trailing: n.isRead ? null : const Icon(Icons.circle, size: 10),
                      onTap: () => _markRead(context, ref, n),
                    );
                  },
                ),
              ),
      ),
    );
  }

  Future<void> _markRead(
      BuildContext context, WidgetRef ref, AppNotification n) async {
    if (n.isRead) return;
    try {
      await ref.read(backendProvider).markNotificationRead(n.id);
      ref.invalidate(notificationsProvider);
    } on Exception catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  IconData _icon(String type) {
    switch (type) {
      case 'watering':
        return Icons.water_drop;
      case 'match':
        return Icons.storefront;
      case 'shelf_life_expiring':
        return Icons.schedule;
      case 'agent_result':
        return Icons.science_outlined;
      default:
        return Icons.notifications;
    }
  }
}