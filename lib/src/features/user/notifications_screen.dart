import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:venue_vibe/src/repositories/notification_repository.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(myNotificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(notificationRepositoryProvider).markAllRead();
              ref.invalidate(myNotificationsProvider);
            },
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: async.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "You're all caught up",
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final n = items[index];
              return ListTile(
                tileColor: n.isRead
                    ? null
                    : AppTheme.primaryBlue.withValues(alpha: 0.04),
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  child: Icon(_iconFor(n.type), color: AppTheme.primaryBlue),
                ),
                title: Text(
                  n.title,
                  style: TextStyle(
                    fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.message),
                    const SizedBox(height: 2),
                    Text(
                      timeago.format(n.createdAt),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey[500]),
                    ),
                  ],
                ),
                trailing: n.isRead
                    ? null
                    : const Icon(
                        Icons.circle,
                        size: 10,
                        color: AppTheme.primaryBlue,
                      ),
                onTap: () async {
                  if (!n.isRead) {
                    await ref
                        .read(notificationRepositoryProvider)
                        .markRead(n.id);
                    ref.invalidate(myNotificationsProvider);
                  }
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  IconData _iconFor(String? type) {
    switch (type) {
      case 'booking':
        return Icons.event_available;
      case 'payment':
        return Icons.payments_outlined;
      case 'cancellation':
        return Icons.event_busy;
      default:
        return Icons.notifications_outlined;
    }
  }
}
