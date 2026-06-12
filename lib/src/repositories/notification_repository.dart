import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:venue_vibe/src/core/supabase_config.dart';
import 'package:venue_vibe/src/models/notification.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(SupabaseConfig.client);
});

final myNotificationsProvider =
    FutureProvider<List<AppNotification>>((ref) async {
  return ref.read(notificationRepositoryProvider).getMyNotifications();
});

/// Count of unread notifications, derived from [myNotificationsProvider].
final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref
          .watch(myNotificationsProvider)
          .valueOrNull
          ?.where((n) => !n.isRead)
          .length ??
      0;
});

class NotificationRepository {
  NotificationRepository(this._client);
  final SupabaseClient _client;

  Future<List<AppNotification>> getMyNotifications() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];
    final data = await _client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markRead(String id) async {
    await _client.from('notifications').update({'is_read': true}).eq('id', id);
  }

  Future<void> markAllRead() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }
}
