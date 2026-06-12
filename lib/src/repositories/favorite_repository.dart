import 'package:book_it/src/core/supabase_config.dart';
import 'package:book_it/src/models/resource.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final favoriteRepositoryProvider = Provider<FavoriteRepository>((ref) {
  return FavoriteRepository(SupabaseConfig.client);
});

/// Set of resource ids the current user has favorited.
final favoriteIdsProvider = FutureProvider<Set<String>>((ref) async {
  return ref.read(favoriteRepositoryProvider).getFavoriteIds();
});

final favoriteResourcesProvider = FutureProvider<List<Resource>>((ref) async {
  return ref.read(favoriteRepositoryProvider).getFavoriteResources();
});

class FavoriteRepository {
  FavoriteRepository(this._client);
  final SupabaseClient _client;

  Future<Set<String>> getFavoriteIds() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return {};
    final data = await _client
        .from('favorites')
        .select('resource_id')
        .eq('user_id', userId);
    return (data as List)
        .map((e) => (e as Map<String, dynamic>)['resource_id'] as String)
        .toSet();
  }

  Future<List<Resource>> getFavoriteResources() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];
    final data = await _client
        .from('favorites')
        .select('resources(*, tenants(name), categories(name))')
        .eq('user_id', userId);
    return (data as List)
        .map((e) => (e as Map<String, dynamic>)['resources'])
        .whereType<Map<String, dynamic>>()
        .map(Resource.fromJson)
        .toList();
  }

  Future<void> toggleFavorite(
    String resourceId, {
    required bool makeFavorite,
  }) async {
    final userId = _client.auth.currentUser!.id;
    if (makeFavorite) {
      await _client
          .from('favorites')
          .upsert({'user_id': userId, 'resource_id': resourceId});
    } else {
      await _client
          .from('favorites')
          .delete()
          .eq('user_id', userId)
          .eq('resource_id', resourceId);
    }
  }
}
